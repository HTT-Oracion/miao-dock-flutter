import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// 设置行（design.html `.setrow`，一比一）。
///
/// ```css
/// .setrow{display:flex;align-items:center;gap:14px;padding:8px 14px;border-radius:8px;
///         background:var(--panel);border:1px solid var(--line);margin-bottom:6px}
/// .setrow:hover{border-color:var(--line2)}
/// .setrow .c .l1 b{font-size:11px;font-weight:600}
/// .setrow .c .l1 .def{padding:1px 6px;border-radius:4px;background:var(--card);font-size:8px;color:var(--mut)}
/// .setrow .c .why{font-size:8.5px;color:var(--mut);margin-top:2px}
/// ```
class SettingRow extends StatefulWidget {
  const SettingRow({super.key, required this.label, this.why, this.def, this.control, this.dimmed = false});

  final String label;

  /// 说明文案（`.why`）。
  final String? why;

  /// 「默认：xxx」小胶囊（`.def`）。
  final String? def;

  /// 右侧控件。
  final Widget? control;

  /// 未接入的能力置灰（**不改文案、不隐藏**：用户要能看见「有这项、暂不可用」）。
  final bool dimmed;

  @override
  State<SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<SettingRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dim = widget.dimmed;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: palette.panel,
          border: Border.all(color: _hover ? palette.line2 : palette.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: dim ? palette.mut : palette.ink,
                          ),
                        ),
                      ),
                      if (widget.def != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(4)),
                          child: Text(widget.def!, style: TextStyle(fontSize: 8, color: palette.mut)),
                        ),
                      ],
                    ],
                  ),
                  if (widget.why != null) ...[
                    const SizedBox(height: 2),
                    Text(widget.why!, style: TextStyle(fontSize: 8.5, color: palette.mut)),
                  ],
                ],
              ),
            ),
            if (widget.control != null) ...[const SizedBox(width: 14), widget.control!],
          ],
        ),
      ),
    );
  }
}

/// 小节标题（design.html `.subt`）。
class SettingSubTitle extends StatelessWidget {
  const SettingSubTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: palette.mut, letterSpacing: 0.4),
      ),
    );
  }
}
