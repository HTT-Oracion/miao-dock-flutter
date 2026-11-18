import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_auth.dart';
import 'package:miao_dock_flutter/features/music/controller/music_login_controller.dart';
import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/data/webview/webview_cookie.dart';
import 'package:miao_dock_flutter/features/music/data/webview/webview_login_config.dart';
import 'package:miao_dock_flutter/features/music/domain/js_music_source.dart';
import 'package:miao_dock_flutter/features/music/domain/music_login_info.dart';

import 'support/stub_engine.dart';
import 'support/stub_registry.dart';

import 'package:miao_dock_flutter/features/music/domain/music_source_manifest.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/login_modal.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/music_state_box.dart';
import 'package:miao_dock_flutter/features/music/ui/login/webview_login_launcher.dart';
import 'package:miao_dock_flutter/features/music/ui/login/webview_login_provider.dart';
import 'package:miao_dock_flutter/features/music/ui/widgets/platform_logo.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 计数的假启动器：验证「弹窗一出现就自动开窗」。
class _CountingLauncher implements WebviewLoginLauncher {
  int opens = 0;
  WebviewLoginConfig? lastConfig;

  @override
  Future<bool> open(WebviewLoginConfig config, Future<bool> Function(List<RawWebviewCookie>) onCookies) async {
    opens += 1;
    lastConfig = config;
    return false; // 模拟用户直接关窗
  }
}

/// 捕获「登录窗口把 Cookie 交回控制器」的回调，窗口不自行结束。
class _CaptureLauncher implements WebviewLoginLauncher {
  WebviewLoginConfig? config;
  Future<bool> Function(List<RawWebviewCookie>)? onCookies;

  @override
  Future<bool> open(WebviewLoginConfig config, Future<bool> Function(List<RawWebviewCookie>) onCookies) {
    this.config = config;
    this.onCookies = onCookies;
    return Completer<bool>().future; // 用户还没完成登录：窗口保持打开
  }
}

class _OpenLoginUi extends MusicUiNotifier {
  @override
  MusicUiState build() => const MusicUiState(loginOpen: true, loginPlatform: 'netease');
}

/// 打开登录弹窗并选中指定平台。
class _OpenLoginUiFor extends MusicUiNotifier {
  _OpenLoginUiFor(this.platform);

  final String platform;

  @override
  MusicUiState build() => MusicUiState(loginOpen: true, loginPlatform: platform);
}

Widget host(Widget child) => MaterialApp(
  theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  // orderTests 使用共享 stub。
  orderTests();
  testWidgets('弹窗打开即自动拉起登录窗口（无需再点按钮）', (tester) async {
    final launcher = _CountingLauncher();
    final container = ProviderContainer(
      overrides: [
        musicPlatformInfosProvider.overrideWith((_) => [neteaseSourceFromRepo().info]),
        jsMusicSourceRegistryProvider.overrideWith(() => StubRegistry([neteaseSourceFromRepo()])),
        musicUiProvider.overrideWith(_OpenLoginUi.new),
        webviewLoginLauncherProvider.overrideWithValue(launcher),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: host(const LoginModal())));
    // postFrameCallback 在下一帧执行。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 破坏点：只在按钮 onTap 里开窗 → 这里 opens 为 0。
    expect(launcher.opens, 1);
    expect(launcher.lastConfig?.platformId, 'netease');
  });

  testWidgets('平台 logo 用真实品牌字形，只列已导入源的平台', (tester) async {
    final launcher = _CountingLauncher();
    final container = ProviderContainer(
      overrides: [
        musicUiProvider.overrideWith(_OpenLoginUi.new),
        webviewLoginLauncherProvider.overrideWithValue(launcher),
        // 🔴 登录弹窗只列**已导入源**的平台（源体系口径）；注入一个源 → 只有一个 pick。
        musicPlatformInfosProvider.overrideWith((_) => [neteaseSourceFromRepo().info]),
        jsMusicSourceRegistryProvider.overrideWith(() => StubRegistry([neteaseSourceFromRepo()])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: host(const LoginModal())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 破坏点 1：把品牌徽章换成 Lucide 通用图标 → 找不到平台徽章。
    // 破坏点 2：平台行仍列全部内置平台（未导入源也显示）→ 数量是 4。
    expect(find.byType(MusicPlatformBadge), findsNWidgets(1));
  });

  testWidgets('新平台靠源声明登录：不判「不支持」，可进入等待并保存登录态', (tester) async {
    final source = _declaredLoginSource();
    final launcher = _CaptureLauncher();
    final engine = StubMusicSourceEngine(loginResult: const MusicLoginInfo(loggedIn: true, nick: 'B站用户'));
    final container = ProviderContainer(
      overrides: [
        musicUiProvider.overrideWith(() => _OpenLoginUiFor('bilibili')),
        musicPlatformInfosProvider.overrideWith((_) => [source.info]),
        jsMusicSourceRegistryProvider.overrideWith(() => StubRegistry([source])),
        webviewLoginLauncherProvider.overrideWithValue(launcher),
        musicSourceEngineProvider.overrideWithValue(engine),
        musicAuthProvider.overrideWith(_FakeAuth.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: host(const LoginModal())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 破坏点：supports 不带源声明 → 新平台被判「该平台暂不支持窗口登录」，
    // begin 置 failed，后续 submitCookies 因 phase != awaiting 永远 no-op（登录态存不下来）。
    expect(container.read(musicLoginProvider).phase, MusicLoginPhase.awaiting);
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginModal)));
    expect(find.text(l10n.musicLoginWebviewUnsupported), findsNothing);
    expect(launcher.config?.url, startsWith('https://www.bilibili.com'));

    final ok = await launcher.onCookies!([
      const RawWebviewCookie(name: 'SESSDATA', value: 's', domain: 'bilibili.com'),
    ]);
    expect(ok, isTrue);
    expect(container.read(musicAuthProvider).cookieOf('bilibili'), contains('SESSDATA=s'));
    // 吸收成功 toast 的定时器。
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('无已导入源：登录弹窗整体变为导入引导', (tester) async {
    final container = ProviderContainer(overrides: [musicUiProvider.overrideWith(_OpenLoginUi.new)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: host(const LoginModal())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 破坏点：无源时不显示引导、还渲染平台行 → 用户对着空平台点登录。
    expect(find.byType(MusicPlatformBadge), findsNothing);
    expect(find.byType(MusicNoSourcePrompt), findsOneWidget);
    // 吸收 begin failed → toast 的定时器。
    await tester.pump(const Duration(seconds: 4));
  });
}

/// 平台顺序（用户口径：侧栏 / 登录弹窗顺序 = 数据源里已启用源的顺序）。
JsMusicSource _sourceOf(String id, String name, String platform) {
  final (manifest, issues) = manifestFromScript(
    "class S extends MusicSourceBase {\n  name = '$name';\n  platform = '$platform';\n"
        "  key = '$id';\n  version = '1.0.0';\n  baseUrl = 'https://x.example.com';\n"
        "  async searchSongs(args) { return { songs: [] }; }\n}",
    '$id.js',
  );
  assert(issues.isEmpty, '$issues');
  return JsMusicSource(manifest: manifest!, capabilities: {'searchSongs'});
}

void orderTests() {
  test('musicPlatformInfosProvider 保序：顺序 = 源注册表顺序', () {
    final container = ProviderContainer(
      overrides: [
        jsMusicSourceRegistryProvider.overrideWith(
          () => StubRegistry([
            _sourceOf('kugou', '酷狗', 'kugou'),
            _sourceOf('netease', '网易云', 'netease'),
            _sourceOf('bilibili', '哔哩哔哩', 'bilibili'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final ids = container.read(musicPlatformInfosProvider).map((i) => i.id).toList();
    // 破坏点：装配层按枚举 / 字母序排序 → 侧栏与数据源页顺序不一致。
    expect(ids, ['kugou', 'netease', 'bilibili']);
  });
}

/// 仅靠 JS 源声明登录配置的新平台（无内置兜底）。
JsMusicSource _declaredLoginSource() {
  final (manifest, issues) = manifestFromScript(
    "class S extends MusicSourceBase {\n  name = '哔哩哔哩';\n  platform = 'bilibili';\n  key = 'bilibili';\n"
        "  version = '1.0.0';\n  baseUrl = 'https://www.bilibili.com';\n"
        "  loginUrl = 'https://www.bilibili.com/';\n"
        "  loginCookieDomains = 'bilibili.com';\n"
        "  loginCookieNames = 'SESSDATA';\n"
        "  async searchSongs(args) { return { songs: [] }; }\n"
        "  async loginInfo(args) { return { loggedIn: true, nick: '' }; }\n}",
    'bilibili.js',
  );
  assert(issues.isEmpty, '$issues');
  return JsMusicSource(manifest: manifest!, capabilities: {'searchSongs', 'loginInfo'});
}

/// 内存登录态（不碰系统钥匙串）。
class _FakeAuth extends MusicAuthNotifier {
  @override
  MusicAuthState build() => const MusicAuthState(cookies: {}, loading: false);

  @override
  Future<void> save(String p, String cookie) async {
    state = state.copyWith(cookies: {...state.cookies, p: cookie});
  }
}
