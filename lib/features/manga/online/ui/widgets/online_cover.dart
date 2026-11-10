import 'package:flutter/material.dart';

import '../../../../../core/theme/tokens.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../domain/online_models.dart';

/// 封面画布色。
///
/// 设计稿的封面是**内容画布**（语义化渐变 + 书名占位），不是界面层级色：
/// 深浅主题共用同一组颜色，与 `AppPalette.paperCard` 同性质。集中放在这里，
/// 禁止在各调用点写 `Color(0x...)`。
const Map<CoverTone, (Color, Color)> _coverGradients = {
  CoverTone.red: (Color(0xFF7A2E2E), Color(0xFF2A1414)),
  CoverTone.blue: (Color(0xFF3E5A7A), Color(0xFF161F2C)),
  CoverTone.orange: (Color(0xFFB6682C), Color(0xFF3A2410)),
  CoverTone.olive: (Color(0xFF5A5342), Color(0xFF201E18)),
  CoverTone.gold: (Color(0xFF8A7326), Color(0xFF2A2410)),
  CoverTone.purple: (Color(0xFF4B3A72), Color(0xFF1A1428)),
  CoverTone.teal: (Color(0xFF2F6B62), Color(0xFF112622)),
  CoverTone.steel: (Color(0xFF4C6B8A), Color(0xFF18232E)),
};

LinearGradient onlineCoverGradient(CoverTone tone) {
  final colors = _coverGradients[tone] ?? _coverGradients[CoverTone.blue]!;
  return LinearGradient(
    begin: const Alignment(-0.72, -0.9),
    end: const Alignment(0.72, 0.9),
    colors: [colors.$1, colors.$2],
  );
}

/// 封面（书名占位）：3:4 圆角、底部暗角、角标。
class OnlineCover extends StatelessWidget {
  const OnlineCover({
    super.key,
    required this.comic,
    this.width,
    this.height,
    this.radius = 8,
    this.showChapterCount = true,
    this.titleSize = AppFont.px11_5,
    this.padding = 9,
    this.showBadge = true,
  });

  final OnlineComic comic;
  final double? width;
  final double? height;
  final double radius;
  final bool showChapterCount;
  final double titleSize;
  final double padding;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final badge = comic.badge;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: onlineCoverGradient(comic.coverTone),
          border: Border.all(color: palette.line2),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 底部暗角：保证书名在任意封面色上的可读性。
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.55,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [palette.shadow.withValues(alpha: 0), palette.shadow.withValues(alpha: 0.55)],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: palette.paperCard,
                      shadows: [Shadow(color: palette.shadow, blurRadius: 4, offset: const Offset(0, 1))],
                    ),
                  ),
                  if (showChapterCount) ...[
                    const SizedBox(height: 3),
                    Text(
                      AppLocalizations.of(context).onlineChapterCount(comic.chapterCount),
                      style: TextStyle(
                        fontSize: AppFont.px9,
                        height: 1.2,
                        color: palette.paperCard.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (badge != null && showBadge)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: palette.shadow.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(fontSize: AppFont.px9, height: 1.4, color: palette.paperCard),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
