import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/responsive.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_login_controller.dart';
import '../../controller/music_session.dart';
import '../../data/webview/webview_login_config.dart';
import '../../domain/music_models.dart';
import '../widgets/platform_logo.dart';
import '../login/mobile_webview_login_page.dart';
import '../login/webview_login_provider.dart';

/// 登录弹窗（N05）。
///
/// 登录方式统一为「打开平台官方登录页」：
/// · 桌面端 → 独立子窗口（见 [DesktopWebviewLoginLauncher]）；
/// · 移动端 → 全屏推入 WebView 页（见 [MobileWebviewLoginPage]）。
///
/// 为什么不再自己生成二维码：官方页面在真实浏览器内核里完成登录，服务端看到的是
/// 正常浏览器环境；自己拼二维码必须伪造 deviceId / appver / 指纹头，反而触发风控。
class LoginModal extends ConsumerStatefulWidget {
  const LoginModal({super.key});

  @override
  ConsumerState<LoginModal> createState() => _LoginModalState();
}

class _LoginModalState extends ConsumerState<LoginModal> {
  /// 弹窗内选中的平台（仅弹窗局部态；确定后才写入 session）。
  late MusicPlatform _platform = ref.read(musicUiProvider).loginPlatform;

  bool _launching = false;

  /// 本次登录的序号：切平台时自增，旧窗口返回后不再改写状态。
  int _loginSeq = 0;

  @override
  void initState() {
    super.initState();
    // 弹窗出现即拉起官方登录窗口（不再让用户多点一次按钮）。
    // 用 postFrameCallback：initState 期间改 provider / 推路由都会踩框架断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startLogin());
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final login = ref.watch(musicLoginProvider);

    // 登录成功：关弹窗 + 轻提示。
    ref.listen(musicLoginProvider.select((s) => s.phase), (prev, next) {
      if (prev == next) return;
      if (next == MusicLoginPhase.succeeded) {
        ref.read(musicUiProvider.notifier).closeLogin();
        showAppToast(context, l10n.musicLoginSuccessToast, tone: ToastTone.good);
        return;
      }
      if (next == MusicLoginPhase.failed) {
        showAppToast(context, l10n.musicLoginFailToast(_failureReason(l10n, login.message)), tone: ToastTone.bad);
      }
    });

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(musicUiProvider.notifier).closeLogin(),
      child: Center(
        child: GestureDetector(
          onTap: () {}, // 阻断冒泡（点弹窗本体不关闭）。
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: context.isMobile ? 340 : 400,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.panel,
                border: Border.all(color: palette.line2),
                borderRadius: BorderRadius.circular(AppMetrics.radiusModal),
                boxShadow: [
                  BoxShadow(color: palette.shadow.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 12)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(title: l10n.musicLoginTitle, onClose: () => ref.read(musicUiProvider.notifier).closeLogin()),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final p in MusicPlatform.values.where((p) => p != MusicPlatform.local)) ...[
                        Expanded(
                          child: _PlatformPick(platform: p, selected: p == _platform, onTap: () => _selectPlatform(p)),
                        ),
                        if (p != MusicPlatform.migu) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  ..._body(context, palette, l10n, login),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, AppPalette palette, AppLocalizations l10n, MusicLoginState login) {
    final brand = platformBrands[_platform];
    final supported = MusicLoginController.supports(_platform);

    if (!supported) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              l10n.musicLoginWebviewUnsupported,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
            ),
          ),
        ),
      ];
    }

    // 窗口开着时不再显示 loading 转圈：那是「等用户在另一个窗口操作」，
    // 不是「应用在加载」。只有真正保存凭据（login.busy）才转圈。
    final saving = login.busy;
    final waiting = _launching && !saving;
    return [
      Center(
        child: SizedBox(width: 158, height: 158, child: SeedCoverPlaceholder(brand: brand?.label ?? '')),
      ),
      const SizedBox(height: 14),
      Center(
        child: Text(
          waiting ? l10n.musicLoginWindowOpen : l10n.musicLoginOpenOfficial(brand?.label ?? ''),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFont.px12, color: palette.ink2, height: 1.5),
        ),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(
          l10n.musicLoginWebviewHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut, height: 1.5),
        ),
      ),
      const SizedBox(height: 16),
      AppButton(
        label: saving ? l10n.onlineLoading : l10n.musicLoginOpenWindow,
        variant: AppButtonVariant.primary,
        height: 36,
        clickable: !saving && !waiting,
        loading: saving,
        onTap: _startLogin,
      ),
      if (login.phase == MusicLoginPhase.failed) ...[
        const SizedBox(height: 8),
        Center(
          child: Text(
            _failureReason(l10n, login.message),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppFont.px11, color: palette.bad),
          ),
        ),
      ],
    ];
  }

  /// 打开官方登录页（桌面子窗口 / 移动全屏页），并驱动 Cookie 轮询。
  Future<void> _startLogin() async {
    if (_launching) return;
    final seq = ++_loginSeq;
    setState(() => _launching = true);
    ref.read(musicLoginProvider.notifier).begin(_platform);
    final config = webviewLoginConfigs[_platform];
    if (config == null) {
      setState(() => _launching = false);
      return;
    }
    final controller = ref.read(musicLoginProvider.notifier);
    try {
      if (context.isMobile) {
        // 移动端：推入全屏 WebView 页，页面内轮询 Cookie。
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => MobileWebviewLoginPage(config: config, onCookies: controller.submitCookies),
          ),
        );
        if (ok != true && seq == _loginSeq) controller.cancel();
      } else {
        // 桌面端：独立子窗口，由 launcher 内部轮询 Cookie。
        final ok = await ref.read(webviewLoginLauncherProvider).open(config, controller.submitCookies);
        if (!ok && seq == _loginSeq) controller.cancel();
      }
    } on Object {
      if (seq == _loginSeq) controller.cancel();
    } finally {
      // 只有最新一次还在等待时才复位 loading，避免旧窗口关闭把新窗口的进度清掉。
      if (mounted && seq == _loginSeq) setState(() => _launching = false);
    }
  }

  void _selectPlatform(MusicPlatform platform) {
    if (_platform == platform) return;
    setState(() => _platform = platform);
    // 让上一次登录流程失效（旧窗口稍后返回也不会改状态）。
    _loginSeq++;
    _launching = false;
    ref.read(musicLoginProvider.notifier).reset();
    // 切平台后同样自动开窗（用户选了平台就等于表达了「现在登录」）。
    unawaited(_startLogin());
  }

  String _failureReason(AppLocalizations l10n, String message) => switch (message) {
    'unsupported' => l10n.musicLoginWebviewUnsupported,
    'credential_store_failed' => l10n.musicLoginQrFailed,
    _ => l10n.musicLoginQrFailed,
  };
}

/// 登录前示意图（官方页面登录，不再有二维码）。
class SeedCoverPlaceholder extends StatelessWidget {
  const SeedCoverPlaceholder({super.key, required this.brand});

  final String brand;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.globe, size: 42, color: palette.mut),
            const SizedBox(height: 8),
            Text(
              brand,
              style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(fontSize: AppFont.px15, fontWeight: FontWeight.w800, color: palette.ink),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onClose,
          child: SizedBox(width: 22, height: 22, child: Icon(LucideIcons.x, size: 15, color: palette.ink2)),
        ),
      ],
    );
  }
}

/// 平台选择格（四平台 logo + 名称）。
///
/// 🔴 logo 必须用 [PlatformLogo]（各平台真实品牌字形），
/// 不要用通用 Lucide 图标代替 —— 那会让用户分不清平台。
class _PlatformPick extends StatelessWidget {
  const _PlatformPick({required this.platform, required this.selected, required this.onTap});

  final MusicPlatform platform;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final brand = platformBrands[platform];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? palette.accSoft : palette.card,
          border: Border.all(color: selected ? palette.acc.withValues(alpha: 0.5) : Colors.transparent),
          borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PlatformLogo(platform: platform, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                brand?.label ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFont.px11_5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? palette.accInk : palette.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
