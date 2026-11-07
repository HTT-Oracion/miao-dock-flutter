import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/error_state.dart';
import '../../../shared/widgets/app_pager.dart';
import '../controller/queue_controller.dart';
import 'queue_empty.dart';
import 'queue_mobile.dart';
import 'queue_sum_bar.dart';
import 'queue_table.dart';
import '../domain/manga_task.dart';

/// 桌面队列内容区左右内距：表格卡片、分页器、页脚说明共用同一数值，
/// 保证三者左右边缘齐平；调整对齐时只改这里，不要各处写魔数。
const double _contentInset = 12;

/// 队列屏（设计稿 H 帧）：默认 / 空 / 加载 / 异常四态。
/// 数据未到 → 骨架；错误 → 横幅 + 上次成功数据仍在（H Note 07）；无数据 → 空态。
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 挂上轮询：页面在场时每 1.5s 拉一次，离开自动停。
    ref.watch(queuePollerProvider);
    final queue = ref.watch(queueProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 统一断点（AGENTS §4 第 16 条）：不再用 720 魔数，避免与外壳 768 不一致。
        final mobile = constraints.maxWidth <= AppMetrics.breakpoint;
        final Widget body;
        // 🔴 先判错误：Riverpod 的 `hasError` 与 `isLoading` 可能**同时为真**
        // （重试期间的状态是 AsyncLoading.copyWithPrevious(error)）。先判 loading
        // 会让失败态被骨架屏永久盖住，用户看不到错误与重试按钮。
        if (queue.hasError) {
          body = _ErrorBody(
            error: queue.error,
            lastGood: ref.read(queueProvider.notifier).lastGood,
            mobile: mobile,
            onRetry: () => ref.read(queueProvider.notifier).refresh(),
          );
        } else {
          // 按用户要求**不再使用骨架屏**：加载中直接按「暂无任务」渲染，
          // 数据到了再刷新。骨架屏在这类秒回的本地服务上反而像闪屏。
          final tasks = queue.value ?? const <MangaTask>[];
          body = tasks.isEmpty
              ? const QueueEmpty()
              : (mobile ? QueueCardList(tasks: tasks) : _QueueContent(tasks: tasks));
        }
        // 移动端不能用桌面内距：设计稿 `.pv` 左右只有 10（与卡片内距对齐），
        // 22 会让卡片和底部选择栏都缩进，选择栏更没法定到屏幕边缘（用户实测）。
        // 桌面端重设计稿：qt-head 自带 10/20/6 内距、qt-scroll 左右 12；
        // pager 与页脚说明跟表格卡片共用 12 内距（左右对齐）
        // ⇒ 外层内距归零，避免双层叠加（design.html §08 纪律）。
        final pad = mobile ? const EdgeInsets.fromLTRB(10, 0, 10, 0) : EdgeInsets.zero;
        return Padding(padding: pad, child: body);
      },
    );
  }
}

/// 错误态（design.html §07 失败行）：
/// **有旧数据 → 横幅 + 旧数据并存；无旧数据 → 整块错误态**（与空态分开绘制）。
class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.lastGood, required this.mobile, required this.onRetry});

  final Object? error;
  final List<MangaTask> lastGood;
  final bool mobile;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // 从没成功过：没有旧数据可展示，给整块错误态（不能拿空态冒充失败态）。
    if (lastGood.isEmpty) return ErrorState(error: error, onRetry: onRetry);

    final content = mobile ? QueueCardList(tasks: lastGood) : _QueueContent(tasks: lastGood);
    return Column(
      children: [
        ErrorBanner(error: error, onRetry: onRetry, showStaleHint: true),
        Expanded(child: content),
      ],
    );
  }
}

class _QueueContent extends ConsumerWidget {
  const _QueueContent({required this.tasks});

  final List<MangaTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pager = ref.watch(pagerProvider);
    final filter = ref.watch(queueFilterProvider);
    // 汇总条始终看全量（它统计的是队列整体）；表格与分页只看筛选后的列表。
    final filtered = applyQueueFilter(tasks, filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QueueSumBar(tasks: tasks),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _contentInset),
            child: QueueTable(tasks: filtered),
          ),
        ),
        const SizedBox(height: 10),
        // 分页器与表格卡片共用左右内距，不再贴边（左「共 N 条」/右页码都与列表对齐）。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _contentInset),
          child: AppPager(
            total: filtered.length,
            page: pager.page,
            pageSize: pager.pageSize,
            onPage: ref.read(pagerProvider.notifier).goTo,
            onPageSize: ref.read(pagerProvider.notifier).setPageSize,
          ),
        ),
        // 页脚说明（重设计稿 pager 右侧 caption）：右边缘与分页器一致。
        Padding(
          padding: const EdgeInsets.fromLTRB(_contentInset, 6, _contentInset, 12),
          child: Row(
            children: [
              const Spacer(),
              Text(
                AppLocalizations.of(context).queueCaption,
                style: TextStyle(fontSize: AppFont.px10_5, color: palette.mut),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
