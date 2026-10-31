/// 一条外部资产清单项（来自原项目 `models.manifest.json` / `runtime.manifest.json`）。
///
/// ## 为什么把它建模成 Dart 常量而不是运行时读 JSON
/// 服务最终以 `dart compile exe` 分发，**没有资源目录**；从工作目录找 JSON
/// 在打包后必然失败。清单体积很小（十几条），编进二进制最省事也最不会丢。
/// 生成脚本见 `tool/gen_engine_manifests.dart`。
class EngineManifestEntry {
  const EngineManifestEntry({
    required this.id,
    required this.set,
    required this.url,
    required this.dest,
    this.platform,
    this.sources = const [],
    this.sha256,
    this.sizeBytes,
    this.extractTo,
    this.extractStrip,
    this.stage,
  });

  final String id;

  /// 分组：`python` / `source` / `visual` / `llm` / `runtime` / `translation`。
  final String set;

  /// 平台键（`darwin-arm64` / `win32-x64` …）；null = 全平台通用。
  final String? platform;

  final String url;

  /// 备用源（镜像优先时按顺序尝试）。
  final List<String> sources;

  /// 原项目布局下的落点（需经 `mapManifestDest` 改写）。
  final String dest;

  final String? sha256;
  final int? sizeBytes;

  /// 解包目标（相对引擎目录）；null = 不适用。
  final String? extractTo;

  /// 解包时剥掉的顶层目录层数。
  final int? extractStrip;

  /// 下载阶段（1 = 运行时，2 = 大模型）；用于分档下载。
  final int? stage;

  /// 是否适用于当前平台。
  bool appliesTo(String platformKey) => platform == null || platform == platformKey;

  /// 下载体积（MB），未标注返回 0。
  double get sizeMb => (sizeBytes ?? 0) / 1048576;
}
