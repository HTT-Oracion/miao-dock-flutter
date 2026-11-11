import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_login_controller.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/login_modal.dart';
import 'package:miao_dock_flutter/l10n/app_localizations.dart';

/// 扫码登录弹窗：**打开即挂载、不能在 build/initState 期间改 provider**
/// （那条断言会让二维码永远停在「加载中 / 无法扫码」）。
///
/// 这里不联网：`musicLoginProvider` 用替身覆盖，只验证 UI 侧的时序与二维码数据来源。
class _FakeLogin extends MusicLoginController {
  _FakeLogin(this.phase, {this.url});

  final MusicQrPhase phase;
  final String? url;
  int starts = 0;

  @override
  MusicQrState build() => MusicQrState(phase: phase, gatewayUrl: url, secondsLeft: 200);

  @override
  Future<void> start(MusicPlatform platform) async {
    starts += 1;
  }
}

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData.dark().copyWith(extensions: const [AppPalette.dark]),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('弹窗打开：首帧不因改 provider 抛异常，且在挂载后启动扫码', (tester) async {
    final fake = _FakeLogin(MusicQrPhase.waiting, url: 'https://music.163.com/login?codekey=abc');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicLoginProvider.overrideWith(() => fake), musicUiProvider.overrideWith(_OpenLoginUi.new)],
        child: host(const LoginModal()),
      ),
    );
    await tester.pump(); // 首帧：若 initState 同步 start，这里会抛 build 期改 provider
    await tester.pump(const Duration(milliseconds: 50));

    // 破坏点：把 start 放回 initState 同步调用 → 首帧断言失败（takeException 非 null）。
    expect(tester.takeException(), isNull);
    expect(fake.starts, greaterThanOrEqualTo(1));
  });

  testWidgets('二维码用 gatewayUrl 渲染（不是占位图）', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicLoginProvider.overrideWith(
            () => _FakeLogin(MusicQrPhase.waiting, url: 'https://music.163.com/login?codekey=abc'),
          ),
          musicUiProvider.overrideWith(_OpenLoginUi.new),
        ],
        child: host(const LoginModal()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 破坏点：只画占位图标不给 QrImageView → 找不到这个 key。
    expect(find.byKey(const ValueKey('music-login-qr')), findsOneWidget);
    // 不再有「二维码图形未渲染」的说明文字（那会让用户以为扫不了）。
    expect(find.textContaining('尚未渲染'), findsNothing);
  });
}

class _OpenLoginUi extends MusicUiNotifier {
  @override
  MusicUiState build() => const MusicUiState(loginOpen: true, loginPlatform: MusicPlatform.netease);
}
