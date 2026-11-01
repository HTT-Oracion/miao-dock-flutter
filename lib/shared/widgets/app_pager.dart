import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'buttons.dart';

/// 通用分页器（设计稿 H Note 04/10，antd Table 风格）：
/// 左「共 N 条任务」，右「N 条 / 页」选择器（向上展开、当前项打勾）+ 方形页码 + 左右箭头。
/// 页大小切换由调用方处理重算与回页（见各屏 controller）。
class AppPager extends StatefulWidget {
  const AppPager({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
    this.pageSizes = const [10, 20, 50],
    this.totalLabel,
  });

  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;
  final List<int> pageSizes;

  /// 总数单位（如「条任务」）；null = 用 ARB 默认文案。
  final String? totalLabel;

  @override
  State<AppPager> createState() => _AppPagerState();
}

class _AppPagerState extends State<AppPager> {
  bool _sizeOpen = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pages = (widget.total / widget.pageSize).ceil();
    return SizedBox(
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              Text(
                AppLocalizations.of(context)
                    .pagerTotal(widget.total, widget.totalLabel ?? AppLocalizations.of(context).pagerTotalTasks),
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
              const Spacer(),
              _SizeSelector(
                open: _sizeOpen,
                current: widget.pageSize,
                sizes: widget.pageSizes,
                onToggle: () => setState(() => _sizeOpen = !_sizeOpen),
                onPick: (size) {
                  widget.onPageSize(size);
                  setState(() => _sizeOpen = false);
                },
              ),
              const SizedBox(width: 10),
              _PageButton(
                icon: LucideIcons.chevronLeft,
                onTap: widget.page > 1 ? () => widget.onPage(widget.page - 1) : null,
              ),
              for (var p = 1; p <= pages; p++)
                _PageButton(label: '$p', active: p == widget.page, onTap: () => widget.onPage(p)),
              _PageButton(
                icon: LucideIcons.chevronRight,
                onTap: widget.page < pages ? () => widget.onPage(widget.page + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SizeSelector extends StatelessWidget {
  const _SizeSelector({
    required this.open,
    required this.current,
    required this.sizes,
    required this.onToggle,
    required this.onPick,
  });

  final bool open;
  final int current;
  final List<int> sizes;
  final VoidCallback onToggle;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppGhostButton(label: AppLocalizations.of(context).pagerPageSize(current), onTap: onToggle),
        if (open)
          Positioned(
            bottom: 30,
            right: 0,
            child: Material(
              color: palette.card,
              borderRadius: BorderRadius.circular(8),
              elevation: 6,
              shadowColor: Colors.black54,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final size in sizes)
                    InkWell(
                      onTap: () => onPick(size),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              child: size == current
                                  ? const Icon(LucideIcons.x, size: 0, color: Colors.transparent)
                                  : null,
                            ),
                            Text(
                              AppLocalizations.of(context).pagerPageSize(size),
                              style: TextStyle(fontSize: 12, color: palette.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({this.label, this.icon, this.active = false, this.onTap});

  final String? label;
  final IconData? icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 统一走 AppButton：当前页 = primary（hover 提亮 accHover，与主按钮一致），
    // 其余 = ghost（透明底，hover 变 card）。此前裸 InkWell 吃了主题 hoverColor，
    // 当前页 hover 被盖成 card 灰（D-120 同型 bug），与按钮体系不一致。
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: AppButton(
        label: icon == null ? (label ?? '') : '',
        icon: icon,
        onTap: onTap,
        clickable: onTap != null,
        variant: active ? AppButtonVariant.primary : AppButtonVariant.ghost,
        width: 26,
        height: 26,
        fontSize: 12,
        fontWeight: active ? FontWeight.w700 : null,
      ),
    );
  }
}
