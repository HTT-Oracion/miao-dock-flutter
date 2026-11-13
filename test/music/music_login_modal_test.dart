import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/theme/tokens.dart';
import 'package:miao_dock_flutter/features/music/controller/music_session.dart';
import 'package:miao_dock_flutter/features/music/data/webview/webview_cookie.dart';
import 'package:miao_dock_flutter/features/music/data/webview/webview_login_config.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';
import 'package:miao_dock_flutter/features/music/ui/desktop/login_modal.dart';
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
  testWidgets('弹窗打开即自动拉起登录窗口（无需再点按钮）', (tester) async {
    final launcher = _CountingLauncher();
    final container = ProviderContainer(
      overrides: [
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
    expect(launcher.lastConfig?.platform, MusicPlatform.netease);
  });

  testWidgets('平台 logo 用真实品牌字形，不被通用图标替换', (tester) async {
    final launcher = _CountingLauncher();
    final container = ProviderContainer(
      overrides: [
        musicUiProvider.overrideWith(_OpenLoginUi.new),
        webviewLoginLauncherProvider.overrideWithValue(launcher),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: host(const LoginModal())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 破坏点：把 PlatformLogo 换成 Lucide 通用图标 → 这里找不到 4 个品牌 logo。
    expect(find.byType(PlatformLogo), findsNWidgets(4));
  });
}
