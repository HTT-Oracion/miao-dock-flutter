import 'package:flutter/material.dart';

/// 运行时平台描述符：JS 源声明 + 内置品牌兜底 + 派生兜底，三层合一。
///
/// 平台身份是**字符串 id**（源体系口径）：内置四平台的 id 与枚举名一致
/// （netease / kugou / qq / migu），新平台任意合法标识符。
class MusicPlatformInfo {
  const MusicPlatformInfo({required this.id, required this.label, this.logoUrl, this.color, this.builtIn = false});

  /// 平台 id（= JS 源的 key；cookie 键 / 会话状态都以它为键）。
  final String id;

  /// 展示名（JS 的 name，兜底 id）。
  final String label;

  /// 源声明的 logo 地址；null = 用内置品牌或派生兜底。
  final String? logoUrl;

  /// 平台主色（JS `color = '#RRGGBB'` 声明 / 内置品牌色 / id 哈希派生）。
  final Color? color;

  /// 是否为项目内置品牌（决定 logo 渲染走内置字形还是声明/派生）。
  final bool builtIn;

  /// 名称首字符 / 拉丁字母派生的占位字形（漫画 glyph 同算法）。
  String get glyph {
    final name = label.trim();
    final runes = name.runes.toList();
    if (runes.isEmpty) return '?';
    final first = String.fromCharCode(runes.first);
    if (RegExp(r'[A-Za-z]').hasMatch(first)) {
      final latin = RegExp(r'[A-Za-z]').allMatches(name).map((m) => m.group(0)!).join();
      return latin.length >= 2 ? latin.substring(0, 2).toUpperCase() : latin.toUpperCase();
    }
    return first;
  }

  MusicPlatformInfo copyWith({String? label, String? logoUrl, Color? color, bool? builtIn}) => MusicPlatformInfo(
    id: id,
    label: label ?? this.label,
    logoUrl: logoUrl ?? this.logoUrl,
    color: color ?? this.color,
    builtIn: builtIn ?? this.builtIn,
  );
}

/// 稳定派生色：同 id 永远同色（不是每次启动随机）——
/// 从 id 的字符码构造 HSL，保证饱和度 / 亮度落在可读区间。
Color derivedPlatformColor(String id) {
  var hash = 0;
  for (final rune in id.codeUnits) {
    hash = (hash * 31 + rune) & 0x7FFFFFFF;
  }
  final hue = (hash % 360).toDouble();
  final hsl = HSLColor.fromAHSL(1.0, hue, 0.52, 0.58);
  return hsl.toColor();
}
