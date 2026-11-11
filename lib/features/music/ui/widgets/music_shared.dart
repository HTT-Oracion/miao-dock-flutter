import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/toast.dart';
import '../../controller/music_player.dart';
import '../../domain/music_models.dart';

/// 音乐域共用小组件：种子封面 / 播放器通知桥 / 播放模式与音质映射。
///
/// 这些件被桌面与移动两端复用（AGENTS §3：跨屏件放 `ui/widgets/`）。

/// 设计稿 `core.js hashStr()` 的精确 Dart 版：JS 的 `Math.imul` 走 32 位有符号溢出，
/// 不能用 `& 0x7FFFFFFF` 简化（会改变后续迭代的输入）。
int musicSeedHash(String s) {
  int toSigned32(int x) {
    final v = x & 0xFFFFFFFF;
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  var h = toSigned32(2166136261);
  for (final c in s.codeUnits) {
    h = toSigned32(h ^ c);
    h = toSigned32(h * 16777619);
  }
  return h.abs();
}

/// 封面渐变（设计稿 `core.js coverBg()`）：两条径向 + 一条扫掠 + 底色，四层叠加。
///
/// 颜色属于内容（封面），不随主题变化；[SeedCover] 与推荐卡大图共用本件。
class SeedGradient extends StatelessWidget {
  const SeedGradient({super.key, required this.seed, this.hue, this.borderRadius, this.child});

  final String seed;

  /// 直接给定色相（演示数据用，保证与设计稿同色）；null = 由 seed 推导。
  final int? hue;
  final BorderRadius? borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final h = hue ?? musicSeedHash(seed) % 360;
    final h2 = (h + 38) % 360;
    final h3 = (h + 300) % 360;
    final pos = 30 + musicSeedHash('$seed·b') % 40;

    Color hsl(double hue, double sat, double light, [double alpha = 1]) =>
        HSLColor.fromAHSL(alpha, hue, sat, light).toColor();
    final top = hsl(h.toDouble(), 0.48, 0.36);
    final bottom = hsl(h2.toDouble(), 0.44, 0.24);
    final base = hsl(h.toDouble(), 0.26, 0.17);
    final deep = hsl(h2.toDouble(), 0.24, 0.09);
    final sweep = hsl(h3.toDouble(), 0.60, 0.60, 0.10);

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [base, deep]),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.72, -0.92),
                radius: 1.35,
                colors: [top, top.withValues(alpha: 0)],
                stops: const [0, 0.58],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.8, 0.92),
                radius: 1.2,
                colors: [bottom, bottom.withValues(alpha: 0)],
                stops: const [0, 0.62],
              ),
            ),
          ),
          // 设计稿第三层是 conic-gradient(alpha .10)：纯装饰。
          // Flutter 的 SweepGradient 在起始角有硬接缝（截图上就是一条斜切痕），
          // 因此用极淡的径向光斑等价表达，视觉一致且无接缝。
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(pos / 50 - 1, -0.32),
                radius: 0.9,
                colors: [sweep, sweep.withValues(alpha: 0)],
                stops: const [0, 0.42],
              ),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

/// 演示封面：定尺寸 + 圆角 + 可选图标（推荐卡 / 歌曲行 / 播放器复用）。
class SeedCover extends StatelessWidget {
  const SeedCover({
    super.key,
    required this.seed,
    this.size = 40,
    this.radius,
    this.icon,
    this.child,
    this.imageUrl,
    this.hue,
  });

  final String seed;
  final double size;
  final double? radius;
  final IconData? icon;
  final Widget? child;

  /// 真实封面（线上音源）。null / 空 = 用 seed 渐变；加载失败也回落到渐变，
  /// 不留白块（第三方图床偶尔 403，不能让它把整行撑成空白）。
  final String? imageUrl;

  /// 直接给定色相；null = 由 [seed] 推导。
  final int? hue;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius ?? AppMetrics.radiusCard);
    final url = imageUrl;
    return SizedBox(
      width: size,
      height: size,
      child: SeedGradient(
        seed: seed,
        hue: hue,
        borderRadius: r,
        child: url == null || url.isEmpty
            ? (icon == null && child == null
                  ? null
                  : Center(
                      child: child ?? Icon(icon, size: size * 0.36, color: Colors.white.withValues(alpha: 0.85)),
                    ))
            : ClipRRect(
                borderRadius: r,
                child: Image.network(
                  url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
      ),
    );
  }
}

/// 播放器通知桥：把 controller 层的语义事件映射成 ARB 轻提示（挂在模块根）。
class MusicNoticeBridge extends ConsumerWidget {
  const MusicNoticeBridge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.listen(playerNoticeProvider, (prev, next) {
      if (next == null || (prev != null && next.seq <= prev.seq)) return;
      switch (next.kind) {
        case PlayerNoticeKind.heartbeatExit:
          showAppToast(context, l10n.musicHeartbeatExit, tone: ToastTone.warn);
        case PlayerNoticeKind.queueEmptyRemoveForbidden:
          showAppToast(context, l10n.musicQueueRemoveForbidden, tone: ToastTone.warn);
      }
    });
    return child;
  }
}

/// 播放模式 → ARB 文案（按钮 title 与弹层共用）。
String playModeLabel(AppLocalizations l10n, PlayMode mode) => switch (mode) {
  PlayMode.list => l10n.musicModeList,
  PlayMode.one => l10n.musicModeOne,
  PlayMode.shuffle => l10n.musicModeShuffle,
  PlayMode.order => l10n.musicModeOrder,
  PlayMode.heartbeat => l10n.musicModeHeartbeat,
};

/// 播放模式 → 一句话说明（样式弹层 / 音质弹层同款规格）。
String playModeDesc(AppLocalizations l10n, PlayMode mode) => switch (mode) {
  PlayMode.list => l10n.musicModeListDesc,
  PlayMode.one => l10n.musicModeOneDesc,
  PlayMode.shuffle => l10n.musicModeShuffleDesc,
  PlayMode.order => l10n.musicModeOrderDesc,
  PlayMode.heartbeat => l10n.musicModeHeartbeatDesc,
};

/// 播放模式图标（lucide，对齐设计稿 modes[].icon）。
IconData playModeIcon(PlayMode mode) => switch (mode) {
  PlayMode.list => LucideIcons.repeat,
  PlayMode.one => LucideIcons.repeat1,
  PlayMode.shuffle => LucideIcons.shuffle,
  PlayMode.order => LucideIcons.listEnd,
  PlayMode.heartbeat => LucideIcons.heart,
};

/// 音质档 → ARB 名称。
String qualityLabel(AppLocalizations l10n, QualityTier q) => switch (q) {
  QualityTier.standard => l10n.musicQualityStd,
  QualityTier.high => l10n.musicQualityHigh,
  QualityTier.lossless => l10n.musicQualityLossless,
  QualityTier.hires => l10n.musicQualityHires,
  QualityTier.master => l10n.musicQualityMaster,
};

/// 音质档副行（码率 / 会员标注）。
String qualitySub(AppLocalizations l10n, QualityTier q) => switch (q) {
  QualityTier.standard => l10n.musicQualityKbps(128),
  QualityTier.high => l10n.musicQualityKbps(320),
  QualityTier.lossless => l10n.musicQualityFlac(1411),
  QualityTier.hires => l10n.musicQualityKbps(1999),
  QualityTier.master => l10n.musicQualityMasterSub,
};

/// 音质档会员要求（null=免费档不显示标注）。
String? qualityLimit(AppLocalizations l10n, QualityTier q) => switch (q.svipRequired) {
  null => q == QualityTier.standard || q == QualityTier.high ? l10n.musicQualityFree : null,
  false => l10n.musicQualityVip,
  true => l10n.musicQualitySvip,
};

/// 平台显示名（侧栏音源组 / 账号菜单 / 行来源共用）。
String platformLabel(AppLocalizations l10n, MusicPlatform p) =>
    p == MusicPlatform.local ? l10n.musicSrcLocal : platformBrands[p]!.label;
