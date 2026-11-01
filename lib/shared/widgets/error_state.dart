import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:protocol/protocol.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

/// 错误态（design.html §07「失败」行）：
/// **红色横幅 + 原因 + 重试 / 换源**，且**不清空已成功的数据**。
///
/// 两层呈现：
///   · [ErrorBanner] —— 横幅，叠在旧数据上方，用于「有旧数据」时；
///   · [ErrorState]  —— 整块空态，用于「没有旧数据可展示」时。
///
/// 文案按错误**类型**映射 ARB；服务端 `message` 与技术栈细节默认折叠在「查看详情」里。
/// 直接把 `MangaSvcException(apiError, ...)` 甩给用户是设计稿明令禁止的。
enum ErrorKind {
  unreachable,
  unauthorized,
  timeout,
  generic;

  /// 从异常归类 —— 只认传输层给的类型，不从 message 里猜字符串。
  static ErrorKind of(Object? error) {
    if (error is MangaSvcException) {
      return switch (error.kind) {
        MangaSvcErrorKind.unreachable => ErrorKind.unreachable,
        MangaSvcErrorKind.unauthorized => ErrorKind.unauthorized,
        MangaSvcErrorKind.timeout => ErrorKind.timeout,
        _ => ErrorKind.generic,
      };
    }
    return ErrorKind.generic;
  }
}

/// 错误文案（标题 + 说明），按类型取 ARB。
({String title, String hint}) _textOf(AppLocalizations l10n, ErrorKind kind) => switch (kind) {
  ErrorKind.unreachable => (title: l10n.errorServiceUnreachable, hint: l10n.errorServiceUnreachableHint),
  ErrorKind.unauthorized => (title: l10n.errorUnauthorized, hint: l10n.errorUnauthorizedHint),
  ErrorKind.timeout => (title: l10n.errorTimeout, hint: l10n.errorTimeoutHint),
  ErrorKind.generic => (title: l10n.errorGeneric, hint: l10n.errorGenericHint),
};

/// 红色横幅 —— 有旧数据时叠在顶部，**不遮挡旧数据**。
class ErrorBanner extends StatefulWidget {
  const ErrorBanner({super.key, required this.error, required this.onRetry, this.showStaleHint = false});

  final Object? error;
  final VoidCallback onRetry;

  /// 下方是否还展示着上次成功的数据（true 时加一行说明，避免用户误以为是实时数据）。
  final bool showStaleHint;

  @override
  State<ErrorBanner> createState() => _ErrorBannerState();
}

class _ErrorBannerState extends State<ErrorBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final kind = ErrorKind.of(widget.error);
    final text = _textOf(l10n, kind);
    const danger = Color(0xFFD98C84);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.10),
        border: Border.all(color: danger.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(AppMetrics.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.circleAlert, size: 15, color: danger),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.title,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: danger),
                    ),
                    const SizedBox(height: 2),
                    Text(text.hint, style: TextStyle(fontSize: 11, height: 1.5, color: palette.textMuted)),
                    if (widget.showStaleHint) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.errorStaleData,
                        style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: palette.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 重试：反馈先于响应由调用方负责（它自己切 loading）。
              TextButton(
                onPressed: widget.onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: danger,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(l10n.errorRetry, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          // 技术细节默认折叠
          if (widget.error != null) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 11,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded ? l10n.errorHideDetail : l10n.errorShowDetail,
                      style: TextStyle(fontSize: 10, color: palette.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  '${widget.error}',
                  style: TextStyle(fontSize: 10, height: 1.4, color: palette.textMuted, fontFamily: 'monospace'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 整块错误态 —— 没有旧数据可展示时用（与空态分开绘制，不共用）。
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final kind = ErrorKind.of(error);
    final text = _textOf(l10n, kind);
    const danger = Color(0xFFD98C84);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: danger.withValues(alpha: 0.45), width: 1.5),
              ),
              child: const Icon(LucideIcons.cloudOff, size: 26, color: danger),
            ),
            const SizedBox(height: 14),
            Text(
              text.title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              text.hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.6, color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 13),
              label: Text(l10n.errorRetry),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.pageBg,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
