import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';
import 'package:miao_dock_flutter/features/music/controller/music_login_controller.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/data/api/netease_api.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/login_modal.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 扫码登录必须**真正完成登录**：803 之后 Cookie 落盘 + 账号置已登录。
///
/// 破坏点：
/// · 803 分支依赖 `loginStatus()` 成功才置登录 → `loginStatus` 抛错时用例失败；
/// · Cookie 合并漏掉 `MUSIC_U` → 用例失败（只收到 NMTID 不算登录）；
/// · 成功态没有回到 UI（phase 不是 succeeded）→ 弹窗关闭断言失败。
class _FakeApi extends NeteaseApi {
  _FakeApi({this.qrCookie = 'MUSIC_U=abc; __csrf=xyz', this.statusThrows = false, this.code = 803});

  /// 轮询下发的 Cookie（藏在私有字段里，避免与 [NeteaseApi.cookie] 撞名）。
  final String qrCookie;
  final bool statusThrows;
  final int code;

  int keyCalls = 0;

  @override
  Future<String> qrKey() async {
    keyCalls += 1;
    return 'key-1';
  }

  @override
  Future<({int code, String message, String? cookie, String? nick, String raw})> qrCheck(
    String key, {
    bool noCookie = false,
  }) async => (code: code, message: '', cookie: qrCookie, nick: null, raw: '{"code":$code}');

  @override
  Future<({bool loggedIn, String userId, String nick})> loginStatus() async {
    if (statusThrows) throw StateError('loginStatus blocked');
    return (loggedIn: true, userId: '42', nick: '测试昵称');
  }
}

class _FakeAuth extends MusicAuthNotifier {
  @override
  MusicAuthState build() => const MusicAuthState(cookies: {}, loading: false);

  @override
  Future<void> save(MusicPlatform p, String cookie) async {
    state = state.copyWith(cookies: {...state.cookies, p: cookie});
  }
}

class _ControlledLogin extends MusicLoginController {
  _ControlledLogin(this.api);

  final NeteaseApi api;

  @override
  NeteaseApi createApi({String cookie = ''}) => api;

  /// 把倒计时压到只剩一拍，方便用例驱动超时。
  void forceSecondsLeft(int v) => state = state.copyWith(secondsLeft: v);
}

/// 弹窗用例专用：不启动真实轮询（否则 fake async 里的 2s 定时器会悬挂），
/// 由测试直接推成功态，验证 UI 是否响应。
class _ManualLogin extends MusicLoginController {
  @override
  MusicQrState build() => const MusicQrState(phase: MusicQrPhase.waiting, key: 'k', secondsLeft: 200);

  @override
  Future<void> start(MusicPlatform platform) async {}

  void succeed() => state = state.copyWith(phase: MusicQrPhase.succeeded, nick: 'n');

  void fail(String reason) => state = state.copyWith(phase: MusicQrPhase.failed, message: reason);
}

class _OpenLoginUi extends MusicUiNotifier {
  @override
  MusicUiState build() => const MusicUiState(loginOpen: true, loginPlatform: MusicPlatform.netease);
}

Widget host(Widget child) => MaterialApp(
  theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  ProviderContainer containerWith(NeteaseApi api) {
    final container = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(_FakeAuth.new),
        musicLoginProvider.overrideWith(() => _ControlledLogin(api)),
        musicUiProvider.overrideWith(_OpenLoginUi.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('扫码 803：Cookie 落盘后账号即登录成功', () async {
    final container = containerWith(_FakeApi());
    await container.read(musicLoginProvider.notifier).start(MusicPlatform.netease);
    // 等轮询一拍（start 内部 2s 定时器；这里直接驱动首拍）。
    await Future<void>.delayed(const Duration(milliseconds: 5400)); // 首拍在 5s

    final login = container.read(musicLoginProvider);
    final account = container.read(musicAccountProvider);
    // 破坏点：803 不置 succeeded / 不写账号 → 两条失败。
    expect(login.phase, MusicQrPhase.succeeded);
    expect(account.logged, isTrue);
    expect(container.read(musicAuthProvider).cookieOf(MusicPlatform.netease), contains('MUSIC_U='));
    expect(account.nick, '测试昵称');
  });

  test('扫码 803：loginStatus 失败也要登录成功（昵称缺失可接受）', () async {
    final container = containerWith(_FakeApi(statusThrows: true));
    await container.read(musicLoginProvider.notifier).start(MusicPlatform.netease);
    await Future<void>.delayed(const Duration(milliseconds: 5400)); // 首拍在 5s

    // 破坏点：把 loginStatus 放在置登录之前并让它抛错吞掉成功 → 这里失败。
    expect(container.read(musicLoginProvider).phase, MusicQrPhase.succeeded);
    expect(container.read(musicAccountProvider).logged, isTrue);
  });

  test('只有 NMTID 没有 MUSIC_U：不算登录成功', () async {
    final container = containerWith(_FakeApi(qrCookie: 'NMTID=only-stats'));
    await container.read(musicLoginProvider.notifier).start(MusicPlatform.netease);
    await Future<void>.delayed(const Duration(milliseconds: 5400)); // 首拍在 5s

    // 破坏点：不做 MUSIC_U 校验 → 统计 Cookie 被当成登录态，账号误报已登录。
    expect(container.read(musicLoginProvider).phase, MusicQrPhase.failed);
    expect(container.read(musicAccountProvider).logged, isFalse);
  });

  test('风控 8821：立即失败并停轮询（不再空等到超时）', () async {
    final container = containerWith(_FakeApi(code: 8821));
    await container.read(musicLoginProvider.notifier).start(MusicPlatform.netease);
    await Future<void>.delayed(const Duration(milliseconds: 5400)); // 首拍在 5s

    final s = container.read(musicLoginProvider);
    // 破坏点：8821 落进 default 被忽略 → phase 仍是 waiting / 最终 expired。
    expect(s.phase, MusicQrPhase.failed);
    expect(s.message, 'risk_control');
    expect(container.read(musicAccountProvider).logged, isFalse);
  });

  test('Cookie 解析：合并多行 Set-Cookie 并识别登录票据', () {
    expect(NeteaseApi.cookieHasLogin('MUSIC_U=abc; __csrf=x'), isTrue);
    expect(NeteaseApi.cookieHasLogin('NMTID=abc'), isFalse);
    expect(NeteaseApi.cookieHasLogin('MUSIC_U='), isFalse);
    expect(NeteaseApi.cookieHasLogin(null), isFalse);
  });

  testWidgets('扫码成功：登录弹窗自动关闭', (tester) async {
    final container = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(_FakeAuth.new),
        musicLoginProvider.overrideWith(_ManualLogin.new),
        musicUiProvider.overrideWith(_OpenLoginUi.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: host(const LoginModal())));
    await tester.pump();

    (container.read(musicLoginProvider.notifier) as _ManualLogin).succeed();
    await tester.pump();

    // 破坏点：成功态不回 UI → 弹窗一直开着，用户以为没登上。
    expect(container.read(musicUiProvider).loginOpen, isFalse);

    // 成功轻提示自带 3.2s 自动消失定时器：卸载后把它跑完再收尾。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('二维码状态：等待态画码、不显示重试；过期后转重试态且不自动换码', (tester) async {
    final api = _FakeApi();
    final container = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(_FakeAuth.new),
        // 用真实控制器 + 假接口：这样「超时是否重新取 key」能被 api.k 次数观测到。
        musicLoginProvider.overrideWith(() => _ControlledLogin(api)),
        musicUiProvider.overrideWith(_OpenLoginUi.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: host(const LoginModal())));
    await tester.pump();
    // 等首码下来（start 里有 Future.delayed(zero) + 取 key）。
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('music-login-qr')), findsOneWidget);
    expect(find.byKey(const ValueKey('music-login-qr-retry')), findsNothing);
    final keyCallsBefore = api.keyCalls;

    // 把剩余时间压到只剩一拍，驱动超时。
    final notifier = container.read(musicLoginProvider.notifier) as _ControlledLogin;
    notifier.forceSecondsLeft(5);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    // 超时：进入重试态，且**没有**再取新 key。
    expect(container.read(musicLoginProvider).phase, MusicQrPhase.expired);
    expect(find.byKey(const ValueKey('music-login-qr-retry')), findsOneWidget);
    // 破坏点：超时自动重新取码 → keyCalls 增加，本条失败。
    expect(api.keyCalls, keyCallsBefore, reason: '超时后不得自动换码');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('登录失败：弹 toast 且二维码进入失败态（不关弹窗）', (tester) async {
    final container = ProviderContainer(
      overrides: [
        musicAuthProvider.overrideWith(_FakeAuth.new),
        musicLoginProvider.overrideWith(_ManualLogin.new),
        musicUiProvider.overrideWith(_OpenLoginUi.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: host(const LoginModal())));
    await tester.pump();

    (container.read(musicLoginProvider.notifier) as _ManualLogin).fail('risk_control');
    await tester.pump();

    // 破坏点：失败不提示 / 关掉弹窗 → 用户不知道发生了什么。
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginModal)));
    expect(find.text(l10n.musicLoginRiskControl), findsWidgets);
    expect(container.read(musicUiProvider).loginOpen, isTrue, reason: '失败时弹窗应保留供重试');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });
}
