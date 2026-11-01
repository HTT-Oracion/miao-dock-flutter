import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

/// 日志组件（D-013）—— **hover / focus 时右上角浮出「复制 / 导出 .txt」**。
///
/// ## 为什么封装成组件
/// 日志在「启动引导 / 服务异常 / 设置页」三处都要用。各写一套必然漂移
/// （原项目就出现过复制在一处、导出在另一处）。
///
/// ## 为什么 hover 浮出而不是常驻工具条
/// 日志是排障时才看的东西，常驻按钮会抢走内容区注意力；
/// 而 hover 浮出在小尺寸日志块里也不会挤压正文。
///
/// ## 两个动作都必须有可见回执
/// 复制 / 导出在桌面端都能「静默成功」，用户点完没有任何变化就会怀疑按钮坏了。
class LogBox extends StatefulWidget {
  const LogBox({super.key, required this.lines, this.title, this.maxHeight = 160, this.onExport});

  /// 日志行（按时间顺序，新→旧由调用方决定）。
  final List<String> lines;

  /// 标题；null = 用 ARB 的「运行日志」。
  final String? title;

  final double maxHeight;

  /// 导出回调。
  ///
  /// 桌面端由调用方接文件保存对话框（用户能选位置、能取消）；
  /// null 时退化为「只复制到剪贴板 + 吐司提示」，**不静默假装导出**。
  final void Function(String text, String suggestedName)? onExport;

  @override
  State<LogBox> createState() => _LogBoxState();
}

class _LogBoxState extends State<LogBox> {
  bool _hover = false;

  /// 复制成功的短暂反馈（图标变绿 1.2s）。
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppPalette.of(context);
    final lines = widget.lines;

    if (lines.isEmpty) {
      // 空态单独绘制：服务没起来时确实没有输出，这不是错误，也不该留一块空黑框。
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
          color: palette.card,
        ),
        child: Text(l10n.logBoxEmpty, style: TextStyle(fontSize: 9.5, color: palette.mut)),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        decoration: BoxDecoration(
          border: Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
          color: palette.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 76, 0),
                  child: Row(
                    children: [
                      Text(widget.title ?? l10n.logBoxTitle, style: TextStyle(fontSize: 9.5, color: palette.mut)),
                      const Spacer(),
                      Text(l10n.logBoxLines(lines.length), style: TextStyle(fontSize: 9.5, color: palette.mut)),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: SelectableText.rich(
                      TextSpan(
                        children: [
                          for (final line in lines)
                            TextSpan(
                              text: '$line\n',
                              style: TextStyle(
                                fontSize: 9.5,
                                height: 1.7,
                                fontFamily: 'monospace',
                                // 错误行只染色不删行
                                color: _isErrorLine(line) ? palette.bad : palette.ink2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // 右上角浮出工具（hover 或焦点时可见）
            Positioned(
              top: 6,
              right: 6,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: _hover ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_hover,
                  child: Row(
                    children: [
                      _ToolButton(
                        icon: _copied ? LucideIcons.check : LucideIcons.copy,
                        tooltip: l10n.logBoxCopy,
                        ok: _copied,
                        onTap: () => _copy(lines, l10n),
                      ),
                      const SizedBox(width: 4),
                      _ToolButton(
                        icon: LucideIcons.download,
                        tooltip: l10n.logBoxExport,
                        onTap: () => _export(lines, l10n),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(List<String> lines, AppLocalizations l10n) async {
    final text = lines.join('\n');
    var ok = false;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      ok = true;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      setState(() => _copied = true);
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _copied = false);
      });
      _toast(l10n.logBoxCopied, l10n.logBoxCopiedDetail(lines.length));
    } else {
      _toast(l10n.logBoxCopyFailed, '');
    }
  }

  void _export(List<String> lines, AppLocalizations l10n) {
    final text = lines.join('\n');
    final now = DateTime.now();
    final name = 'miaodock-log-${now.year}-${_two(now.month)}-${_two(now.day)}.txt';
    final handler = widget.onExport;
    if (handler == null) {
      // 没有导出通道时只复制，并明确告知 —— 不假装导出成功。
      _copy(lines, l10n);
      return;
    }
    try {
      handler(text, name);
      _toast(l10n.logBoxExported, name);
    } catch (_) {
      _toast(l10n.logBoxExportFailed, '');
    }
  }

  void _toast(String title, String detail) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(detail.isEmpty ? title : '$title · $detail'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// 错误行判据 —— 只匹配明显的失败关键词，避免把普通行误染色。
  static bool _isErrorLine(String line) =>
      RegExp(r'error|fail|exited|refused|denied|\u5f02\u5e38|\u5931\u8d25', caseSensitive: false).hasMatch(line);
}

/// 圆形小工具按钮（24×24）。
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.tooltip, required this.onTap, this.ok = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: palette.hi,
        borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: ok ? palette.good : palette.line2),
              borderRadius: BorderRadius.circular(AppMetrics.radiusButton),
            ),
            child: Icon(icon, size: 12, color: ok ? palette.good : palette.ink2),
          ),
        ),
      ),
    );
  }
}
