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

    // 线上扫码成功：关弹窗 + 轻提示（状态由 controller 写，UI 只响应一次）。
    ref.listen(musicLoginProvider.select((s) => s.phase), (prev, next) {
      if (next != MusicQrPhase.succeeded || prev == MusicQrPhase.succeeded) return;
      ref.read(musicUiProvider.notifier).closeLogin();
      showAppToast(context, l10n.musicLoginSuccessToast, tone: ToastTone.good);
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
                      Text(
                        l10n.musicLoginCountdown(_online ? qrState.secondsLeft : _cd),
                        style: TextStyle(fontSize: AppFont.px11, color: palette.mut),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(_startTicker),
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

  List<Widget> _qrBody(BuildContext context, AppPalette palette, AppLocalizations l10n) {
    final brand = platformBrands[_platform];
    final qr = _online ? ref.watch(musicLoginProvider) : null;
    final gatewayUrl = qr?.gatewayUrl;
    final phase = qr == null
        ? _phase
        : switch (qr.phase) {
            MusicQrPhase.scanned => _QrPhase.scanned,
            _ => _QrPhase.waiting,
          };
    final statusText = switch (qr?.phase) {
      MusicQrPhase.loading => l10n.onlineLoading,
      MusicQrPhase.expired => l10n.musicLoginQrExpired,
      MusicQrPhase.failed => l10n.musicLoginQrExpired,
      _ => switch (phase) {
        _QrPhase.waiting => l10n.musicLoginQrWaiting,
        _QrPhase.scanned => _cd <= 0 ? l10n.musicLoginQrExpired : l10n.musicLoginQrScanned,
      },
    };
    return [
      Center(
        child: SizedBox(
          width: 158,
          height: 158,
          child: Stack(
            children: [
              Positioned.fill(
                child: gatewayUrl == null
                    ? SeedCover(
                        seed: brand?.label ?? 'qr',
                        size: 158,
                        radius: AppMetrics.radiusCard,
                        child: Icon(LucideIcons.qrCode, size: 56, color: palette.coverInk),
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
              if ((qr?.secondsLeft ?? _cd) <= 0)
                Positioned.fill(child: ColoredBox(color: palette.shadow.withValues(alpha: 0.45))),
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
          style: TextStyle(fontSize: AppFont.px11, color: phase == _QrPhase.waiting ? palette.mut : palette.accInk),
        ),
      ),
    ];
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
