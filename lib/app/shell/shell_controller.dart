import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 侧栏收起状态（设计稿 G 的展开 / 收起两态）。
final navCollapsedProvider = NotifierProvider<NavCollapsedNotifier, bool>(NavCollapsedNotifier.new);

class NavCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
