import 'package:flutter/material.dart';

/// 设计令牌（深色，取自 pencil 设计稿 G 帧实测色值；浅色主题随 L 帧落地补充）。
abstract final class AppTokens {
  /// 页面背景（G 帧屏幕底色）
  static const Color pageBg = Color(0xFF0C0F12);

  /// 侧栏 / 标题栏浮层底色
  static const Color navBg = Color(0xFF141920);

  /// 侧栏激活项（琥珀调深底）
  static const Color navActive = Color(0xFF2B2318);

  /// 卡片底色
  static const Color card = Color(0xFF1A2028);

  /// 封面占位
  static const Color cardCover = Color(0xFF3E4956);

  /// 进度条槽底
  static const Color progressTrack = Color(0xFF252C35);

  /// 强调色（主按钮 / 激活态）
  static const Color accent = Color(0xFFE8A44C);

  /// 主文字
  static const Color textPrimary = Color(0xFFE9EEF3);

  /// 次要文字
  static const Color textSecondary = Color(0xFF6B7885);

  /// 分隔线 / hover 底
  static const Color divider = Color(0xFF1D242C);

  /// 成功 / 已完成
  static const Color success = Color(0xFF7FB58A);
}
