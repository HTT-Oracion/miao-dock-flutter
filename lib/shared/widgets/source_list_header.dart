import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import 'buttons.dart';
import 'state_box.dart';

/// 数据源面板的「已导入的源」标题行：标题 + 计数胶囊 + 右侧动作（导出）。
///
/// 漫画源与音乐源**共用本组件**，间距（top 16 / bottom 10）与字号（12.5 / w700）
/// 由这里统一决定，改样式只需改这一处。
class SourceListHeader extends StatelessWidget {
  const SourceListHeader({super.key, required this.title, required this.count, this.onExport, this.exportLabel});

  final String title;
  final int count;
  final VoidCallback? onExport;
  final String? exportLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: AppFont.px12_5, fontWeight: FontWeight.w700, color: palette.ink),
          ),
          const SizedBox(width: 10),
          OnlineTag('$count'),
          if (onExport != null && exportLabel != null) ...[
            const Spacer(),
            AppButton(
              label: exportLabel!,
              icon: LucideIcons.externalLink,
              onTap: onExport,
              variant: AppButtonVariant.link,
              fontSize: AppFont.px11,
              horizontalPadding: 0,
            ),
          ],
        ],
      ),
    );
  }
}

/// 数据源面板底部的合规提示条（蓝底 + 淡描边 + 圆角 10）。
///
/// 漫画源与音乐源共用；文案由调用方传入。
class SourceDisclaimerBar extends StatelessWidget {
  const SourceDisclaimerBar({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.acc.withValues(alpha: 0.08),
        border: Border.all(color: palette.acc.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppFont.px11_5, height: 1.6, color: palette.ink2),
      ),
    );
  }
}

/// 已装源卡片的外壳（`card` 底 + `line2` 描边 + 圆角 10 + 移动/桌面两档内距）。
///
/// 漫画源与音乐源共用：卡片外观只在这里定义一次。
class SourceCardShell extends StatelessWidget {
  const SourceCardShell({super.key, required this.mobile, required this.child});

  final bool mobile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 14, vertical: mobile ? 10 : 12),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.line2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

/// 已装源列表项的统一底部间距（卡片之间 9）。
class SourceListItemPadding extends StatelessWidget {
  const SourceListItemPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 9), child: child);
}
