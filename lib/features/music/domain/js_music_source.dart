import 'music_models.dart';
import 'music_source_manifest.dart';

/// 已导入的 JS 音乐源（清单 + 运行时状态）。
///
/// [capabilities] 由导入试跑静态扫描 `sourceFile` 得到；上层据此隐藏入口，
/// 不给「点了没反应」的按钮。连续失败达到 3 次熔断（与漫画源同口径）。
class JsMusicSource {
  const JsMusicSource({
    required this.manifest,
    required this.capabilities,
    this.enabled = true,
    this.consecutiveFailures = 0,
    this.lastUsedAt,
  });

  final MusicSourceManifest manifest;
  final Set<String> capabilities;
  final bool enabled;
  final int consecutiveFailures;
  final DateTime? lastUsedAt;

  String get id => manifest.id;
  String get name => manifest.name;
  MusicPlatform get platform => manifest.resolvedPlatform!;
  bool get isAvailable => enabled && consecutiveFailures < 3;

  JsMusicSource withFailure() => JsMusicSource(
    manifest: manifest,
    capabilities: capabilities,
    enabled: enabled,
    consecutiveFailures: consecutiveFailures + 1,
    lastUsedAt: lastUsedAt,
  );

  JsMusicSource withSuccess() => JsMusicSource(
    manifest: manifest,
    capabilities: capabilities,
    enabled: enabled,
    consecutiveFailures: 0,
    lastUsedAt: DateTime.now(),
  );
}
