import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
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
    this.totalLabel = '条任务',
  });

  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;
  final List<int> pageSizes;
  final String totalLabel;

  @override
  State<AppPager> createState() => _AppPagerState();
}

class _AppPagerState extends State<AppPager> {
  bool _sizeOpen = false;

  @override
  Widget build(BuildContext context) {
    final pages = (widget.total / widget.pageSize).ceil();
    return SizedBox(
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              Text(
                '共 ${widget.total} ${widget.totalLabel}',
                style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppGhostButton(label: '$current 条 / 页', onTap: onToggle),
        if (open)
          Positioned(
            bottom: 30,
            right: 0,
            child: Material(
              color: AppTokens.card,
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
                            Text('$size 条 / 页', style: const TextStyle(fontSize: 12, color: AppTokens.textPrimary)),
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
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: active ? AppTokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: 13, color: enabled ? AppTokens.textPrimary : AppTokens.progressTrack)
                : Text(
                    label ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active ? AppTokens.pageBg : AppTokens.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
