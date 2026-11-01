import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import 'buttons.dart';

/// 通用弹窗外壳（**项目唯一弹窗实现**）。
///
/// 规格（取自 D-097 重排过的编辑弹窗 / runtime / backend 选择弹窗的交集）：
/// - `card` 底 + [AppMetrics.radiusModal]（12）圆角，无描边（浮层靠阴影抬起）；
/// - 内距 20/18/20/18；标题 14 / w700，可选前缀图标（如 backend 选择的 cpu）
///   与右上角关闭钮（大弹窗用，如 runtime 选择）；
/// - 动作区**右对齐**、间距 8，主操作在最后（对照 ver1.0「取消 / 保存」布局）。
///
/// 内容与动作由调用方组装；动作区的按钮**必须用 [AppButton]**
/// （取消 = secondary，主操作 = primary，危险确认 = danger），禁止在弹窗里手写按钮。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.icon,
    this.width,
    this.onClose,
  });

  final String title;

  /// 标题前缀图标（如引擎后端选择的 cpu）；null = 纯文字标题。
  final IconData? icon;

  final Widget child;

  /// 底部动作区（右对齐）；空 = 无动作区（纯展示弹窗）。
  final List<Widget> actions;

  /// 弹窗宽度；null = 由内容决定（内容侧自行 `SizedBox(width:)`）。
  final double? width;

  /// 右上角关闭钮；null = 不显示（小弹窗靠动作区取消）。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: palette.acc), const SizedBox(width: 8)],
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: AppFont.px14, fontWeight: FontWeight.w700, color: palette.textPrimary),
              ),
            ),
            if (onClose != null)
              AppButton(icon: LucideIcons.x, width: 22, height: 22, variant: AppButtonVariant.ghost, onTap: onClose),
          ],
        ),
        const SizedBox(height: 12),
        child,
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: actions),
        ],
      ],
    );

    // 🔴 宽度必须落到内容上：Container 不指定 width 时会**撑满可用宽度**
    // （实测弹窗被拉成 1120 宽，内容只有 300 —— 看起来"弹窗太大"）。
    // 因此 width 为空时用 IntrinsicWidth 让弹窗按内容收缩。
    final content = width == null ? IntrinsicWidth(child: body) : SizedBox(width: width, child: body);

    return Dialog(
      backgroundColor: palette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppMetrics.radiusModal)),
      child: Container(padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), child: content),
    );
  }
}

/// 弹窗统一入口：要调浮层样式（barrier / 内距 / 圆角）只改这里。
Future<T?> showAppDialog<T>({required BuildContext context, required WidgetBuilder builder}) {
  return showDialog<T>(context: context, builder: builder);
}
