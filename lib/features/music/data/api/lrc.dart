import '../../domain/music_models.dart';

/// LRC 解析（四平台共用）：`[mm:ss.xx]` 逐句时间轴 + 可选翻译轨。
///
/// 网易云的 `yrc`（逐字）与 QQ 的 `qrc`（逐字）都不在这里处理 —— 设计稿只要求
/// 逐句高亮，逐字属于后续增强；这里把 `[mm:ss.xx]` 行解析干净即可。
SongLyrics parseLrc(String lrc, {String translation = ''}) {
  final main = _parseLines(lrc);
  if (main.isEmpty) return const SongLyrics(lines: []);
  final trans = _parseLines(translation);
  if (trans.isEmpty) return SongLyrics(lines: main);

  // 翻译轨按时间戳对齐（毫秒容差 120ms：两轨偶尔差一帧）。
  final transByTime = {for (final l in trans) l.t: l.text};
  final lines = <LyricLine>[
    for (final l in main) LyricLine(t: l.t, text: l.text, translation: _nearest(transByTime, l.t)),
  ];
  return SongLyrics(lines: lines, hasTranslation: lines.any((l) => l.translation != null));
}

List<LyricLine> _parseLines(String raw) {
  if (raw.trim().isEmpty) return const [];
  final out = <LyricLine>[];
  final tag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  for (final line in raw.split('\n')) {
    final matches = tag.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line.substring(matches.last.end).trim();
    if (text.isEmpty) continue;
    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracRaw = m.group(3) ?? '0';
      // 两位 = 百分秒，三位 = 毫秒（两种写法都存在，不能一律当毫秒）。
      final frac = fracRaw.length == 1
          ? int.parse(fracRaw) * 100
          : (fracRaw.length == 2 ? int.parse(fracRaw) * 10 : int.parse(fracRaw));
      out.add(LyricLine(t: min * 60000 + sec * 1000 + frac, text: text));
    }
  }
  out.sort((a, b) => a.t.compareTo(b.t));
  return out;
}

String? _nearest(Map<int, String> byTime, int t) {
  if (byTime.containsKey(t)) return byTime[t];
  int? best;
  var bestDiff = 120;
  for (final k in byTime.keys) {
    final d = (k - t).abs();
    if (d <= bestDiff) {
      bestDiff = d;
      best = k;
    }
  }
  return best == null ? null : byTime[best];
}

/// 平台码率 → 行内音质角标（无损 / 320K / 标准）。
String? qualityLabelForBitrate(int br, Duration duration, int bytes) {
  if (br >= 900 || (duration.inSeconds > 0 && bytes ~/ duration.inSeconds >= 100_000)) return 'lossless';
  if (br >= 300) return '320K';
  if (br > 0) return '${br}K';
  return null;
}
