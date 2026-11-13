import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_login_controller.dart';
import '../../controller/music_session.dart';
import '../../domain/music_models.dart';
import '../widgets/music_shared.dart';
import '../widgets/platform_logo.dart';

/// 登录弹窗（N04/M10）：真实二维码状态 + 倒计时 + 刷新。
class LoginModal extends ConsumerStatefulWidget {
  const LoginModal({super.key});

  @override
  ConsumerState<LoginModal> createState() => _LoginModalState();
}

enum _QrPhase { waiting, scanned }

class _LoginModalState extends ConsumerState<LoginModal> {
  /// 弹窗内选中的平台（仅弹窗局部态；确定后才写入 session）。
  late MusicPlatform _platform = ref.read(musicUiProvider).loginPlatform;

  _QrPhase _phase = _QrPhase.waiting;
  int _cd = 272;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 首帧之后再启动登录流程：initState 里同步改 provider 会踩 Riverpod 的
    // 「modify during build」断言，二维码就永远停在加载中。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startTicker();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 网易云扫码交给真实登录控制器；其余平台不伪造扫码成功。
  bool get _online => _platform == MusicPlatform.netease;

  void _startTicker() {
    _ticker?.cancel();
    _phase = _QrPhase.waiting;
    _cd = 272;
    if (_online) {
      ref.read(musicLoginProvider.notifier).start(_platform);
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _cd = math.max(_cd - 1, 0));
    });
  }

  void _selectPlatform(MusicPlatform platform) {
    if (_platform == platform) {
      _startTicker();
      return;
    }
    setState(() => _platform = platform);
    // 切换平台：先把上一个平台的扫码状态清掉，再启动新的。
    ref.read(musicLoginProvider.notifier).reset();
    _startTicker();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final qrState = ref.watch(musicLoginProvider);

    // 扫码成功 → 关弹窗 + 成功提示；失败 / 过期 → 留在弹窗 + 失败提示。
    // 只对「状态刚刚变化」响应一次，避免每次 rebuild 重复弹 toast。
    ref.listen(musicLoginProvider.select((s) => s.phase), (prev, next) {
      if (prev == next) return;
      if (next == MusicQrPhase.succeeded) {
        ref.read(musicUiProvider.notifier).closeLogin();
        showAppToast(context, l10n.musicLoginSuccessToast, tone: ToastTone.good);
        return;
      }
      if (next == MusicQrPhase.failed || next == MusicQrPhase.expired) {
        showAppToast(
          context,
          l10n.musicLoginFailToast(_failureReason(l10n, ref.read(musicLoginProvider).message)),
          tone: ToastTone.bad,
        );
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
              width: 400,
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
                  // 平台行：4 平台 logo + 名称，点选切换（弹窗局部态）。
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
                  const SizedBox(height: 14),
                  ..._qrBody(context, palette, l10n),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 倒计时归零后不再显示「0s 后自动刷新」——我们不自动刷新，
                      // 停在重试态等用户点（自动换码会让正在扫的码突然失效）。
                      if (!qrState.needsRetry)
                        Text(
                          l10n.musicLoginCountdown(_online ? qrState.secondsLeft : _cd),
                          style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                        ),
                      if (!qrState.needsRetry) const SizedBox(width: 8),
                      GestureDetector(
                        key: const ValueKey('music-login-refresh'),
                        onTap: _retry,
                        child: Tooltip(
                          message: l10n.musicLoginRefreshAria,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.refreshCw, size: 12, color: palette.accInk),
                              const SizedBox(width: 4),
                              Text(
                                l10n.musicLoginRefreshAria,
                                style: TextStyle(
                                  fontSize: AppFont.px10_5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.accInk,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 诊断标签 → 用户可读原因（不直接展示服务端 message）。
  String _failureReason(AppLocalizations l10n, String message) => switch (message) {
    'risk_control' => l10n.musicLoginRiskControl,
    _ => l10n.musicLoginQrFailed,
  };

  /// 二维码显示态：把 controller 的细粒度 phase 收敛成 UI 需要的 4 种。
  ///
  /// · waiting：正常等扫（画二维码）
  /// · scanned：已扫码待确认（照常画二维码，手机端才是确认入口）
  /// · retry  ：过期 / 失败 —— 二维码压暗 + 重试按钮，**不自动换码**
  /// · loading：正在取 key（画占位）
  _QrView _qrView(MusicQrState? qr) {
    if (!_online) {
      // 非网易云：没有真实扫码能力，按原演示态显示。
      return _QrView.waiting;
    }
    return switch (qr?.phase) {
      MusicQrPhase.loading || MusicQrPhase.idle => _QrView.loading,
      MusicQrPhase.expired || MusicQrPhase.failed => _QrView.retry,
      MusicQrPhase.scanned => _QrView.scanned,
      _ => _QrView.waiting,
    };
  }

  String _statusText(AppPalette palette, AppLocalizations l10n, MusicQrState? qr, _QrView view) {
    if (!_online) {
      return switch (_phase) {
        _QrPhase.waiting => l10n.musicLoginQrWaiting,
        _QrPhase.scanned => l10n.musicLoginQrScanned,
      };
    }
    return switch (view) {
      _QrView.loading => l10n.onlineLoading,
      _QrView.retry when qr?.phase == MusicQrPhase.expired => l10n.musicLoginQrExpired,
      _QrView.retry => _failureReason(l10n, qr?.message ?? ''),
      _QrView.scanned => l10n.musicLoginQrScanned,
      _QrView.waiting => l10n.musicLoginQrWaiting,
    };
  }

  List<Widget> _qrBody(BuildContext context, AppPalette palette, AppLocalizations l10n) {
    final brand = platformBrands[_platform];
    final qr = _online ? ref.watch(musicLoginProvider) : null;
    final gatewayUrl = qr?.gatewayUrl;
    final view = _qrView(qr);
    final showQr = view == _QrView.waiting || view == _QrView.scanned;
    final statusText = _statusText(palette, l10n, qr, view);
    return [
      Center(
        child: SizedBox(
          width: 158,
          height: 158,
          child: Stack(
            children: [
              Positioned.fill(
                child: !showQr || gatewayUrl == null
                    ? SeedCover(
                        seed: brand?.label ?? 'qr',
                        size: 158,
                        radius: AppMetrics.radiusCard,
                        child: view == _QrView.loading
                            ? Icon(LucideIcons.loader, size: 34, color: palette.coverInk)
                            : Icon(LucideIcons.qrCode, size: 56, color: palette.coverInk),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.coverInk,
                          borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: QrImageView(
                            key: const ValueKey('music-login-qr'),
                            data: gatewayUrl,
                            version: QrVersions.auto,
                            eyeStyle: QrEyeStyle(color: palette.vinylBase),
                            dataModuleStyle: QrDataModuleStyle(color: palette.vinylBase),
                          ),
                        ),
                      ),
              ),
              // 四角框（设计稿 qr 边角）。
              const _Corners(),
              // 只有「重试」态压暗并盖一层可点的重试按钮；等待 / 已扫码时二维码保持清晰。
              if (view == _QrView.retry)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('music-login-qr-retry'),
                    onTap: _retry,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.shadow.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.rotateCw, size: 24, color: palette.coverInk),
                            const SizedBox(height: 6),
                            Text(
                              l10n.musicLoginRetry,
                              style: TextStyle(
                                fontSize: AppFont.px11,
                                fontWeight: FontWeight.w600,
                                color: palette.coverInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: Text(
          l10n.musicLoginScanWith(brand?.label ?? ''),
          style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w600, color: palette.ink),
        ),
      ),
      const SizedBox(height: 4),
      Center(
        child: Text(
          statusText,
          key: const ValueKey('music-login-status'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppFont.px11,
            color: view == _QrView.retry ? palette.bad : (view == _QrView.waiting ? palette.mut : palette.accInk),
          ),
        ),
      ),
    ];
  }

  /// 手动重试：丢掉旧 key、重新取码。**只有用户点才换码**。
  void _retry() {
    ref.read(musicLoginProvider.notifier).reset();
    _startTicker();
  }
}

/// 二维码的 UI 显示态（与 controller 的 phase 解耦，避免 UI 到处判 phase）。
enum _QrView { loading, waiting, scanned, retry }

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

/// 二维码四角框。
class _Corners extends StatelessWidget {
  const _Corners();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final w = BorderSide(color: palette.ink, width: 2);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 6,
            top: 6,
            child: SizedBox(
              width: 16,
              height: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: w, top: w),
                ),
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: SizedBox(
              width: 16,
              height: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(right: w, top: w),
                ),
              ),
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: SizedBox(
              width: 16,
              height: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: w, bottom: w),
                ),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: SizedBox(
              width: 16,
              height: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(right: w, bottom: w),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
