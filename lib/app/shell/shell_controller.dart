import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/shell_prefs.dart';

/// 侧栏宽度折叠状态（design.html §03：展开 208 ⇄ 收起 68）。
///
/// 与原项目的 `sidebarLabels` 是**两件事**，不可合并：
///   · 本 provider 管几何宽度（点击 `panel-left-close / panel-left-open` 切换）；
///   · [sidebarLabelsProvider] 管展开态下要不要渲染文字（设置页开关，用户偏好）。
/// 原项目只有后者、没有宽度折叠；设计稿只有前者、没有标签开关 —— 两者都要。
final navCollapsedProvider = NotifierProvider<NavCollapsedNotifier, bool>(NavCollapsedNotifier.new);

class NavCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  /// 设置页「侧栏展开」开关也走这里 —— 与侧栏按钮同一状态。
  void set(bool value) => state = value;
}

/// 当前模块的视图清单 —— 侧栏视图组的事实源（design.html §03 侧栏结构）。
///
/// 顺序即工作流时序，与原项目 `TRANSLATE_VIEWS` 一致（投放 → 队列 → 漫画库）。
/// **只存 id，不存文案**：文案由 UI 层按 id 查 ARB（AGENTS §3 国际化约束）。
@immutable
class SidebarViewItem {
  const SidebarViewItem({required this.id});

  /// 路由段名：`/manga/<id>` 或 `/music/<id>`。
  final String id;
}

/// 漫画模块视图（原项目 `TRANSLATE_VIEWS` 的顺序）。
const List<SidebarViewItem> mangaViews = [
  SidebarViewItem(id: 'drop'),
  SidebarViewItem(id: 'queue'),
  SidebarViewItem(id: 'library'),
  SidebarViewItem(id: 'online'),
];

/// 音乐模块视图（design.html 侧栏「音乐」分组）。
const List<SidebarViewItem> musicViews = [
  SidebarViewItem(id: 'discover'),
  SidebarViewItem(id: 'playlist'),
  SidebarViewItem(id: 'local'),
  SidebarViewItem(id: 'history'),
];

/// 阅读器路由（漫画模块的子页，不属于任何视图页签）。
const String readerPath = '/manga/reader';

/// 在线阅读器路由（内容区子页；移动端同样整屏）。
const String onlineReaderPath = '/manga/online/reader';

/// 当前是否在阅读器。
///
/// 三处行为都靠它判定：移动端**全屏**（不渲染壳层导航）、隐藏「新建漫画」入口、
/// 以及阅读器在漫画库视图下的高亮归属（见 [resolveViewId]）。
bool isReaderPath(String path) => path.startsWith(readerPath) || path.startsWith(onlineReaderPath);

/// 子页 → 归属视图。阅读器从漫画库进入，归到「漫画库」——
/// 否则切回来时页签跑到「投放」、面包屑也显示投放，看着像路由错乱。
const Map<String, String> _viewAlias = {'reader': 'library', 'notready': 'drop', 'degraded': 'drop'};

/// 路径段 → 视图 id（页签高亮 / 面包屑的事实源）。
///
/// 不在视图清单内的段（如 `reader`）按 [_viewAlias] 归到所属视图；
/// 仍无法归属时回落到该模块首个视图。
String? resolveViewId(String? segment, List<SidebarViewItem> items) {
  if (items.isEmpty) return null;
  final mapped = segment == null ? null : (_viewAlias[segment] ?? segment);
  if (mapped != null && items.any((v) => v.id == mapped)) return mapped;
  return items.first.id;
}
