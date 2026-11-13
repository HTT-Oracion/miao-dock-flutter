import 'package:flutter/material.dart';

import 'music_platform_info.dart';
import 'music_source_manifest.dart';

/// 已导入的 JS 音乐源（清单 + 运行时状态）。
///
/// [capabilities] 由导入试跑静态扫描 `sourceFile` 得到；上层据此隐藏入口，
/// 不给「点了没反应」的按钮。连续失败达到 3 次熔断（与漫画源同口径）。
///
/// 🔴 平台身份是**字符串** [platformId]（= 清单 platform 字段）：内置四平台的
/// id 与枚举名一致（netease / kugou / qq / migu），新平台任意合法标识符。
class JsMusicSource {
  const JsMusicSource({
    required this.manifest,
    required this.capabilities,
    this.enabled = true,
    this.consecutiveFailures = 0,
    this.lastUsedAt,
    this.sourceUrl,
  });

  final MusicSourceManifest manifest;
  final Set<String> capabilities;
  final bool enabled;
  final int consecutiveFailures;
  final DateTime? lastUsedAt;

  /// 导入来源（远程目录条目地址 / 本地文件 file:// URL）；
  /// 启动自动更新据此重新拉取。本地目录导入（拖拽 / 选择文件）为 null —— 不参与自动更新。
  final String? sourceUrl;

  String get id => manifest.id;

  /// 平台 id（内置四平台 = netease / kugou / qq / migu；新平台任意标识符）。
  String get platformId => manifest.platform;

  String get name => manifest.name;
  bool get isAvailable => enabled && consecutiveFailures < 3;

  /// 源的展示描述符：label / logo / 颜色三层兜底（声明 → 内置品牌 → 派生）。
  MusicPlatformInfo get info {
    Color? declared;
    final hex = manifest.colorHex;
    if (hex != null && RegExp(r'^#?[0-9a-fA-F]{6,8}$').hasMatch(hex)) {
      final digits = hex.replaceFirst('#', '');
      declared = Color(int.parse(digits.length == 6 ? 'FF$digits' : digits, radix: 16));
    }
    return MusicPlatformInfo(
      id: platformId,
      label: name,
      logoUrl: manifest.logoUrl,
      color: declared,
      streamReferer: manifest.streamReferer,
    );
  }

  JsMusicSource copyWith({bool? enabled, int? consecutiveFailures, DateTime? lastUsedAt, String? sourceUrl}) =>
      JsMusicSource(
        manifest: manifest,
        capabilities: capabilities,
        enabled: enabled ?? this.enabled,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        sourceUrl: sourceUrl ?? this.sourceUrl,
      );

  JsMusicSource withFailure() => copyWith(consecutiveFailures: consecutiveFailures + 1);

  JsMusicSource withSuccess() => copyWith(consecutiveFailures: 0, lastUsedAt: DateTime.now());
}
