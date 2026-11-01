import 'package:flutter/material.dart';

/// 设计令牌 —— 逐条取自 `ver1.0/design.html` 与 `ver1.0/assets/app.css` 的 `:root`。
///
/// 命名对照（设计稿变量 → 本类字段）：
///   `--bg` → [AppPalette.bg]；`--panel` → [AppPalette.panel]；`--card` → [AppPalette.card]；
///   `--hi` → [AppPalette.hi]；`--line` → [AppPalette.line]；`--line2` → [AppPalette.line2]；
///   `--ink` → [AppPalette.ink]；`--ink2` → [AppPalette.ink2]；`--mut` → [AppPalette.mut]；
///   `--acc` → [AppPalette.acc]；`--on-acc` → [AppPalette.onAcc]；`--acc-soft` → [AppPalette.accSoft]。
///
/// 深浅两套共用同一组语义键，切主题只换值不换结构（design.html §01）。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.panel,
    required this.card,
    required this.hi,
    required this.line,
    required this.line2,
    required this.ink,
    required this.ink2,
    required this.mut,
    required this.acc,
    required this.onAcc,
    required this.accSoft,
    required this.good,
    required this.bad,
    required this.warn,
    required this.blue,
    required this.shadow,
    required this.coverEnd,
  });

  /// 画布底。
  final Color bg;

  /// 面板 / 侧栏 / 播放条。
  final Color panel;

  /// 卡片 / 行底 / 悬停底。
  final Color card;

  /// 悬停更亮一档 / 进度槽。
  final Color hi;

  /// 分隔线。
  final Color line;

  /// 边框（比 line 亮一档）。
  final Color line2;

  /// 主文字。
  final Color ink;

  /// 次要文字 / 侧栏未激活。
  final Color ink2;

  /// 说明 / hint。
  final Color mut;

  /// 主题橙（主按钮 / 激活）。
  final Color acc;

  /// 橙底上的字。
  final Color onAcc;

  /// 主题浅底（侧栏激活项）。
  final Color accSoft;

  /// 成功 / 已完成。
  final Color good;

  /// 失败 / 危险。
  final Color bad;

  /// 部分 / 缺页。
  final Color warn;

  /// 翻译中 / 待译。
  final Color blue;

  /// 浮层投影（app.css `--shadow`）。
  final Color shadow;

  /// 封面渐变终点（app.css `.mp-cov`：`linear-gradient(140deg, acc, #6B4423)`）。
  final Color coverEnd;

  /// 深色主题（默认）。
  static const dark = AppPalette(
    bg: Color(0xFF0C0F12),
    panel: Color(0xFF141920),
    card: Color(0xFF1A2028),
    hi: Color(0xFF252C35),
    line: Color(0xFF252C35),
    line2: Color(0xFF313A45),
    ink: Color(0xFFE9EEF3),
    ink2: Color(0xFFA3B0BC),
    mut: Color(0xFF6B7885),
    acc: Color(0xFFE8A44C),
    onAcc: Color(0xFF1A1305),
    accSoft: Color(0xFF2B2318),
    good: Color(0xFF7FB58A),
    bad: Color(0xFFD98C84),
    warn: Color(0xFFD9A441),
    blue: Color(0xFF7BA7CE),
    shadow: Color(0x73000000),
    coverEnd: Color(0xFF6B4423),
  );

  /// 浅色主题。
  static const light = AppPalette(
    bg: Color(0xFFFBFBF9),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFF3F2EF),
    hi: Color(0xFFFFFFFF),
    line: Color(0xFFE7E4DC),
    line2: Color(0xFFD8D0BF),
    ink: Color(0xFF171A1D),
    ink2: Color(0xFF525C66),
    mut: Color(0xFF8B939A),
    acc: Color(0xFFC07C2E),
    onAcc: Color(0xFFFFF8EC),
    accSoft: Color(0xFFF8F0E3),
    good: Color(0xFF4C7A5C),
    bad: Color(0xFFB4564C),
    warn: Color(0xFFB47A20),
    blue: Color(0xFF5B8DB8),
    shadow: Color(0x2E504015),
    coverEnd: Color(0xFF8A5A2E),
  );

  // ── 语义别名（与 AppTokens 同名，便于迁移时 1:1 替换）──────────────
  Color get pageBg => bg;
  Color get textPrimary => ink;
  Color get textSecondary => mut;
  Color get textMuted => ink2;
  Color get navBg => panel;
  Color get navActive => accSoft;
  Color get cardCover => hi;
  Color get progressTrack => hi;
  Color get divider => line;
  Color get accent => acc;
  Color get success => good;

  /// 取当前主题调色板；未挂载扩展时回落深色（设计稿默认档）。
  static AppPalette of(BuildContext context) => Theme.of(context).extension<AppPalette>() ?? dark;

  @override
  AppPalette copyWith({
    Color? bg,
    Color? panel,
    Color? card,
    Color? hi,
    Color? line,
    Color? line2,
    Color? ink,
    Color? ink2,
    Color? mut,
    Color? acc,
    Color? onAcc,
    Color? accSoft,
    Color? good,
    Color? bad,
    Color? warn,
    Color? blue,
    Color? shadow,
    Color? coverEnd,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      card: card ?? this.card,
      hi: hi ?? this.hi,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      mut: mut ?? this.mut,
      acc: acc ?? this.acc,
      onAcc: onAcc ?? this.onAcc,
      accSoft: accSoft ?? this.accSoft,
      good: good ?? this.good,
      bad: bad ?? this.bad,
      warn: warn ?? this.warn,
      blue: blue ?? this.blue,
      shadow: shadow ?? this.shadow,
      coverEnd: coverEnd ?? this.coverEnd,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      card: Color.lerp(card, other.card, t)!,
      hi: Color.lerp(hi, other.hi, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      mut: Color.lerp(mut, other.mut, t)!,
      acc: Color.lerp(acc, other.acc, t)!,
      onAcc: Color.lerp(onAcc, other.onAcc, t)!,
      accSoft: Color.lerp(accSoft, other.accSoft, t)!,
      good: Color.lerp(good, other.good, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      coverEnd: Color.lerp(coverEnd, other.coverEnd, t)!,
    );
  }
}

/// 字号阶梯（design.html §02）—— 只有五档，不新造字号。
abstract final class AppType {
  /// 页标题：15 / 700。
  static const double pageTitle = 15;
  static const FontWeight pageTitleWeight = FontWeight.w700;

  /// 分区标题：12.5 / 700。
  static const double sectionTitle = 12.5;
  static const FontWeight sectionTitleWeight = FontWeight.w700;

  /// 条目标题：11 / 600。
  static const double itemTitle = 11;
  static const FontWeight itemTitleWeight = FontWeight.w600;

  /// 正文 / 说明：9.5 / 400。
  static const double body = 9.5;
  static const FontWeight bodyWeight = FontWeight.w400;
}

/// 布局尺寸（design.html §03）。
abstract final class AppMetrics {
  /// 侧栏展开宽度。
  static const double sidebarWidth = 208;

  /// 侧栏收起宽度。
  static const double sidebarCollapsedWidth = 68;

  /// 工具条高度。
  static const double toolbarHeight = 56;

  /// 品牌行高度（app.css `.sidebar .brand`）。
  static const double brandHeight = 52;

  /// 内容左右边距：所有页一致，禁止双层 padding 叠加。
  static const double contentPadding = 24;

  /// 圆角：按钮 6 / 卡片 10–12 / 弹窗 12 / 抽屉顶 18 / 岛展开 20。
  static const double radiusButton = 6;
  static const double radiusCard = 10;
  static const double radiusCardLg = 12;
  static const double radiusModal = 12;
  static const double radiusSheetTop = 18;
  static const double radiusIslandOpen = 20;
  static const double radiusPill = 999;

  /// 响应式断点：`@media (max-width:768px)`。
  static const double breakpoint = 768;

  /// macOS 原生红绿灯占位带：侧栏品牌行与工具条都从它下方开始，
  /// 避免 logo / 内容压在红绿灯上。
  static const double macTrafficLightBand = 28;
}

/// 动效规范（design.html §06）。
abstract final class AppMotion {
  /// 页面切换：opacity 0→1 + translateY(8→0)，300ms ease。
  static const Duration pageSwitch = Duration(milliseconds: 300);
  static const double pageSwitchOffset = 8;

  /// 侧栏 / 灵动岛形变：320ms cubic-bezier(.22,.61,.36,1)。
  static const Duration morph = Duration(milliseconds: 320);
  static const Curve morphCurve = Cubic(0.22, 0.61, 0.36, 1);

  /// hover / 背景过渡：app.css 的 `.18s`。
  static const Duration hover = Duration(milliseconds: 180);
}

/// 静态色值别名 —— 兼容既有屏内引用。
///
/// 新增代码请用 [AppPalette.of] 取主题感知色；本类只提供深色档常量，
/// 供尚未迁到 ThemeExtension 的业务屏过渡使用。
abstract final class AppTokens {
  /// 页面背景（`--bg`）。
  static const Color pageBg = Color(0xFF0C0F12);

  /// 侧栏 / 标题栏浮层底色（`--panel`）。
  static const Color navBg = Color(0xFF141920);

  /// 侧栏激活项（`--acc-soft`）。
  static const Color navActive = Color(0xFF2B2318);

  /// 卡片底色（`--card`）。
  static const Color card = Color(0xFF1A2028);

  /// 封面占位（app.css `.mp-cov` 渐变终点侧中间值）。
  static const Color cardCover = Color(0xFF3E4956);

  /// 进度条槽底（`--hi`）。
  static const Color progressTrack = Color(0xFF252C35);

  /// 强调色（`--acc`）。
  static const Color accent = Color(0xFFE8A44C);

  /// 主文字（`--ink`）。
  static const Color textPrimary = Color(0xFFE9EEF3);

  /// 说明文字（`--mut`）。
  static const Color textSecondary = Color(0xFF6B7885);

  /// 侧栏未激活文字（`--ink2`）。
  static const Color textMuted = Color(0xFFA3B0BC);

  /// 分隔线 / hover 底（`--line`）。
  static const Color divider = Color(0xFF252C35);

  /// 成功 / 已完成（`--good`）。
  static const Color success = Color(0xFF7FB58A);

  /// 危险/失败（与 [AppPalette.bad] 深色值一致；浅色主题下用 palette 版）。
  static const Color bad = Color(0xFFD98C84);
}
