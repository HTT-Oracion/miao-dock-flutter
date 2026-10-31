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
/// 顺序即工作流时序，与原项目 `TRANSLATE_VIEWS` 一致（投放 → 队列 → 漫画库），
/// 不在此处另立枚举：视图 id 必须与路由段同名。
enum MangaView {
  drop('投放'),
  queue('队列'),
  library('漫画库');

  const MangaView(this.label);

  final String label;
}

enum MusicView {
  discover('发现'),
  playlist('我的歌单'),
  local('本地音乐'),
  history('播放历史');

  const MusicView(this.label);

  final String label;
}

/// 侧栏视图项（图标由 UI 层按 id 映射，域层不依赖 Flutter 图标类型）。
@immutable
class SidebarViewItem {
  const SidebarViewItem({required this.id, required this.label});

  /// 路由段名：`/manga/<id>` 或 `/music/<id>`。
  final String id;
  final String label;
}

/// 漫画模块视图（原项目 `TRANSLATE_VIEWS`，逐字）。
const List<SidebarViewItem> mangaViews = [
  SidebarViewItem(id: 'drop', label: '投放'),
  SidebarViewItem(id: 'queue', label: '队列'),
  SidebarViewItem(id: 'library', label: '漫画库'),
];

/// 音乐模块视图（design.html 侧栏「音乐」分组）。
const List<SidebarViewItem> musicViews = [
  SidebarViewItem(id: 'discover', label: '发现'),
  SidebarViewItem(id: 'playlist', label: '我的歌单'),
  SidebarViewItem(id: 'local', label: '本地音乐'),
  SidebarViewItem(id: 'history', label: '播放历史'),
];
