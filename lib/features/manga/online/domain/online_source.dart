import 'source_manifest.dart';

/// 已导入的漫画源（清单 + 本地状态）。
///
/// `capabilities` 由导入试跑时静态扫描 `source.js` 得到；`consecutiveFailures`
/// 达到 3 时 UI 显示红点并熔断（plan §0.4 / 设计稿多平台切换）。
class OnlineSource {
  const OnlineSource({
    required this.manifest,
    required this.capabilities,
    this.enabled = true,
    this.consecutiveFailures = 0,
    this.lastUsedAt,
    this.importedAt,
    this.glyphOverride,
  });

  final SourceManifest manifest;
  final Set<String> capabilities;
  final bool enabled;
  final int consecutiveFailures;
  final DateTime? lastUsedAt;
  final DateTime? importedAt;

  /// 平台行图标字；demo 源在数据层显式给定（柜 / 拷 / BZ），导入源按源名推导。
  final String? glyphOverride;

  String get id => manifest.id;
  String get name => manifest.name;
  String get version => manifest.version;
  bool get isAbnormal => consecutiveFailures >= 3;
  bool get isAvailable => enabled && !isAbnormal;

  /// 平台行图标字（取源名首字 / 首字母组合）。
  String get glyph {
    final override = glyphOverride;
    if (override != null && override.isNotEmpty) return override;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final runes = trimmed.runes.toList();
    final first = String.fromCharCode(runes.first);
    if (RegExp(r'[A-Za-z]').hasMatch(first)) {
      final latin = RegExp(r'[A-Za-z]').allMatches(trimmed).map((m) => m.group(0)!).join();
      return latin.length >= 2 ? latin.substring(0, 2).toUpperCase() : latin.toUpperCase();
    }
    return runes.length >= 2 ? String.fromCharCodes(runes.take(1)) : first;
  }

  String get host => manifest.hosts.isEmpty ? '' : manifest.hosts.first;

  OnlineSource copyWith({
    SourceManifest? manifest,
    Set<String>? capabilities,
    bool? enabled,
    int? consecutiveFailures,
    DateTime? lastUsedAt,
    DateTime? importedAt,
    String? glyphOverride,
  }) => OnlineSource(
    manifest: manifest ?? this.manifest,
    capabilities: capabilities ?? this.capabilities,
    enabled: enabled ?? this.enabled,
    consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    importedAt: importedAt ?? this.importedAt,
    glyphOverride: glyphOverride ?? this.glyphOverride,
  );

  Map<String, Object?> toJson() => {
    'manifest': manifest.toJson(),
    'capabilities': capabilities.toList()..sort(),
    'enabled': enabled,
    'consecutiveFailures': consecutiveFailures,
    'lastUsedAt': lastUsedAt?.toIso8601String(),
    'importedAt': importedAt?.toIso8601String(),
    if (glyphOverride != null) 'glyph': glyphOverride,
  };

  static OnlineSource? fromJson(Map<String, Object?> json) {
    final rawManifest = json['manifest'];
    if (rawManifest is! Map) return null;
    final manifest = SourceManifest.fromMap(Map<String, Object?>.from(rawManifest));
    final caps = json['capabilities'];
    return OnlineSource(
      manifest: manifest,
      capabilities: caps is List ? caps.whereType<String>().toSet() : const {},
      enabled: json['enabled'] != false,
      consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
      lastUsedAt: DateTime.tryParse('${json['lastUsedAt']}'),
      importedAt: DateTime.tryParse('${json['importedAt']}'),
      glyphOverride: json['glyph'] is String ? '${json['glyph']}' : null,
    );
  }
}
