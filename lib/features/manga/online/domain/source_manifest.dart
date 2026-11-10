import 'dart:convert';

/// 源运行时格式。
enum SourceRuntime {
  /// 本项目的异步能力契约（`class X extends SourceBase`）。
  contract,

  /// 上游 `ComicSource` 单文件格式（`class X extends ComicSource`），
  /// 通过 JS 兼容适配器映射到本项目的 DTO。
  comicSource,
}

/// 在线漫画源清单（plan §5.2 `source.json`）。
///
/// 只做**结构与安全边界**的校验，不执行 JS：入口类、能力函数由导入时的
/// 静态检查给出警告，真正的 QuickJS 运行时在后续阶段接入 `SourceEngine`。
class SourceManifest {
  const SourceManifest({
    required this.specVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.lang,
    required this.baseUrl,
    required this.entryClass,
    required this.sourceFile,
    required this.hosts,
    this.icon,
    this.description = '',
    this.timeoutMs = 15000,
    this.headers = const {},
    this.rateLimitIntervalMs = 400,
    this.rateLimitConcurrency = 2,
    this.runtime = SourceRuntime.contract,
  });

  final int specVersion;
  final String id;
  final String name;
  final String version;
  final String lang;
  final String baseUrl;
  final String entryClass;
  final String sourceFile;
  final List<String> hosts;
  final String? icon;
  final String description;
  final int timeoutMs;
  final Map<String, String> headers;
  final int rateLimitIntervalMs;
  final int rateLimitConcurrency;

  /// 脚本格式；远程单 JS 源会自动合成清单并标记 [SourceRuntime.comicSource]。
  final SourceRuntime runtime;

  static const int supportedSpecVersion = 2;

  /// 源 id 命名规则（plan §5.2）：`^[a-z0-9][a-z0-9._-]{2,63}$`。
  static final RegExp idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$');

  /// 域名白名单：支持 `*.example.com` 通配子域。
  static final RegExp hostPattern = RegExp(r'^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');

  static final RegExp _versionPattern = RegExp(r'^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$');

  /// 从 `source.json` 文本解析。结构错误抛 [FormatException]（message 是字段名，
  /// 由 UI 映射为 ARB，不上屏英文细节）。
  factory SourceManifest.fromJsonString(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('json');
    }
    if (decoded is! Map) throw const FormatException('json');
    return SourceManifest.fromMap(Map<String, Object?>.from(decoded));
  }

  factory SourceManifest.fromMap(Map<String, Object?> map) {
    int intField(String key, int fallback) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return fallback;
    }

    String stringField(String key) => map[key] is String ? (map[key]! as String).trim() : '';

    final rawHosts = map['hosts'];
    final hosts = rawHosts is List
        ? rawHosts.whereType<String>().map((e) => e.trim().toLowerCase()).toList()
        : <String>[];

    final rawHeaders = map['request'];
    final headers = <String, String>{};
    var timeoutMs = 15000;
    if (rawHeaders is Map) {
      final requestHeaders = rawHeaders['headers'];
      if (requestHeaders is Map) {
        for (final entry in requestHeaders.entries) {
          if (entry.key is String && entry.value is String) headers['${entry.key}'] = '${entry.value}';
        }
      }
      final t = rawHeaders['timeoutMs'];
      if (t is num) timeoutMs = t.toInt();
    }

    var intervalMs = 400;
    var concurrency = 2;
    final rate = map['rateLimit'];
    if (rate is Map) {
      if (rate['intervalMs'] is num) intervalMs = (rate['intervalMs']! as num).toInt();
      if (rate['concurrency'] is num) concurrency = (rate['concurrency']! as num).toInt();
    }

    return SourceManifest(
      specVersion: intField('specVersion', 0),
      id: stringField('id'),
      name: stringField('name'),
      version: stringField('version'),
      lang: stringField('lang').isEmpty ? 'unknown' : stringField('lang'),
      baseUrl: stringField('baseUrl'),
      entryClass: stringField('entryClass'),
      sourceFile: stringField('sourceFile').isEmpty ? 'source.js' : stringField('sourceFile'),
      hosts: hosts,
      icon: stringField('icon').isEmpty ? null : stringField('icon'),
      description: stringField('description'),
      timeoutMs: timeoutMs.clamp(1000, 60000),
      headers: headers,
      rateLimitIntervalMs: intervalMs.clamp(100, 60000),
      rateLimitConcurrency: concurrency.clamp(1, 4),
      runtime: '${map['runtime'] ?? ''}' == 'comicSource' ? SourceRuntime.comicSource : SourceRuntime.contract,
    );
  }

  /// 字段级错误（返回字段名，不返回中文/英文说明）。
  ///
  /// 顺序与 plan §5.2 一致：specVersion → id → name/version/baseUrl → entryClass
  /// → sourceFile/icon 路径 → hosts。
  List<String> validate() {
    final errors = <String>[];
    if (specVersion != supportedSpecVersion) errors.add('specVersion');
    if (name.isEmpty) errors.add('name');
    if (!idPattern.hasMatch(id)) errors.add('id');
    if (!_versionPattern.hasMatch(version)) errors.add('version');
    final base = Uri.tryParse(baseUrl);
    if (base == null || !(base.isScheme('http') || base.isScheme('https')) || base.host.isEmpty) {
      errors.add('baseUrl');
    }
    if (entryClass.isEmpty) errors.add('entryClass');
    for (final path in [sourceFile, ?icon]) {
      if (path.startsWith('/') || path.contains('..') || path.contains('\\')) {
        errors.add('path');
        break;
      }
    }
    if (hosts.isEmpty) {
      errors.add('hosts');
    } else if (hosts.any((host) => !hostPattern.hasMatch(host))) {
      errors.add('hosts');
    }
    return errors;
  }

  Map<String, Object?> toJson() => {
    'specVersion': specVersion,
    'id': id,
    'name': name,
    'version': version,
    'lang': lang,
    'baseUrl': baseUrl,
    'entryClass': entryClass,
    'sourceFile': sourceFile,
    if (icon != null) 'icon': icon,
    'description': description,
    'hosts': hosts,
    'request': {'timeoutMs': timeoutMs, if (headers.isNotEmpty) 'headers': headers},
    'rateLimit': {'intervalMs': rateLimitIntervalMs, 'concurrency': rateLimitConcurrency},
    if (runtime != SourceRuntime.contract) 'runtime': runtime.name,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  SourceManifest copyWith({String? name, String? version, String? lang, List<String>? hosts}) => SourceManifest(
    specVersion: specVersion,
    id: id,
    name: name ?? this.name,
    version: version ?? this.version,
    lang: lang ?? this.lang,
    baseUrl: baseUrl,
    entryClass: entryClass,
    sourceFile: sourceFile,
    hosts: hosts ?? this.hosts,
    icon: icon,
    description: description,
    timeoutMs: timeoutMs,
    headers: headers,
    rateLimitIntervalMs: rateLimitIntervalMs,
    rateLimitConcurrency: rateLimitConcurrency,
    runtime: runtime,
  );
}
