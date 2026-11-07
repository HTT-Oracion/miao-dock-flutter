import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/controller/section_controller.dart';

/// 模块切换（桌面侧栏 / 移动底栏共用）—— **保活各模块最后浏览的页面**。
///
/// `index >= 0`：`goBranch` 恢复该分支上一次的 matchList。分支内的 page 与 State
/// 都还在 `IndexedStack` 里（只是 offstage），所以阅读器停在第几页、漫画库选中
/// 哪本书、队列筛选条件都原样保留。
///
/// 🔴 不要改回 `context.go('/manga/drop')`：那是「跳路径」，会把分支栈重写成单页，
/// 阅读器连同页码一起被销毁（用户实测「看漫画切到设置，再点漫画回到投放页」）。
///
/// `index == -1`：设置是全局层、**不参与保活**，每次进入都回干净路由 + 「通用」分区；
/// 点当前已激活的模块则无操作（不把用户从当前页面踢走）。
void switchModule(BuildContext context, WidgetRef ref, StatefulNavigationShell shell, int index) {
  if (index < 0) {
    goSettings(context, ref);
    return;
  }
  if (index == shell.currentIndex) return;
  shell.goBranch(index);
}

/// 进设置页：分区归零后跳 `/settings`。
///
/// 深链（`/settings?section=translate`）**不走这里** —— 它们要指定分区。
void goSettings(BuildContext context, WidgetRef ref) {
  ref.read(settingsSectionProvider.notifier).reset();
  context.go('/settings');
}
