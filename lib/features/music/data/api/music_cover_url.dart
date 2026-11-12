/// 封面 URL 规范化（四平台共用）。
///
/// 🔴 为什么必须统一处理：Flutter 的 `Image.network` 在 macOS / iOS / Android
/// 默认**拒绝明文 `http://`**（ATS / cleartext 策略），图会静默加载失败、
/// 只留下渐变占位。第三方接口（酷狗、QQ、咪咕）大量返回 `http://`，
/// 不转 `https://` 就等于「这个平台永远没有封面」。
///
/// 另外酷狗给的是模板串（`.../{size}/...`），占位符不替换同样加载不出来。
library;

const _defaultCoverSize = 300;

/// 规范化封面地址：
/// · 去空白；空串 → null（调用方据此回落渐变，而不是加载空 URL）
/// · `//host/...` → `https://host/...`（协议相对）
/// · `http://` → `https://`（避免明文被平台拒）
/// · `{size}` → [size]（酷狗模板串）
String? normalizeCoverUrl(Object? raw, {int size = _defaultCoverSize}) {
  if (raw == null) return null;
  var v = '$raw'.trim();
  if (v.isEmpty) return null;
  if (v.startsWith('//')) return 'https:$v'.replaceAll('{size}', '$size');
  v = v.replaceFirst(RegExp('^http://', caseSensitive: false), 'https://');
  v = v.replaceAll('{size}', '$size');
  // 少量接口给的是相对路径，统一挂到 QQ 图床会错，直接判为不可用。
  if (!v.startsWith('https://') && !v.startsWith('http://')) return null;
  return v;
}
