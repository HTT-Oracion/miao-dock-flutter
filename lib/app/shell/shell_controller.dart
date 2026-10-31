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
  // 启动引导（D-012）：住在右侧主体区、侧栏照常，所以它是**一个可点的视图**而不是整屏。
  SidebarViewItem(id: 'notready'),
];

/// 音乐模块视图（design.html 侧栏「音乐」分组）。
const List<SidebarViewItem> musicViews = [
  SidebarViewItem(id: 'discover'),
  SidebarViewItem(id: 'playlist'),
  SidebarViewItem(id: 'local'),
  SidebarViewItem(id: 'history'),
];
