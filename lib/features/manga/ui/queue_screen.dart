import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_pager.dart';
import '../controller/queue_controller.dart';
import 'queue_empty.dart';
import 'queue_mobile.dart';
import 'queue_skeleton.dart';
import 'queue_sum_bar.dart';
import 'queue_table.dart';
import '../domain/manga_task.dart';

/// 队列屏（设计稿 H 帧）：默认 / 空 / 加载 / 异常四态。
/// 数据未到 → 骨架；错误 → 横幅 + 上次成功数据仍在（H Note 07）；无数据 → 空态。
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 720;
        final Widget body;
        if (queue.isLoading && queue.value == null) {
          body = const QueueSkeleton();
        } else if (queue.hasError) {
          body = _ErrorBody(
            message: '${queue.error}',
            lastGood: ref.read(queueProvider.notifier).lastGood,
            mobile: mobile,
          );
        } else {
          final tasks = queue.value ?? const <MangaTask>[];
          body = tasks.isEmpty
              ? const QueueEmpty()
              : (mobile ? QueueCardList(tasks: tasks) : _QueueContent(tasks: tasks));
        }
        return Padding(padding: const EdgeInsets.fromLTRB(22, 18, 22, 0), child: body);
      },
    );
  }
}

/// 错误态（H Note 07）：错误横幅 + 上次成功的数据仍在。
class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.lastGood, required this.mobile});

  final String message;
  final List<MangaTask> lastGood;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final content = lastGood.isEmpty
        ? const QueueEmpty()
        : (mobile ? QueueCardList(tasks: lastGood) : _QueueContent(tasks: lastGood));
    return Column(
      children: [
        _ErrorBanner(message: message),
        const SizedBox(height: 10),
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
    final pager = ref.watch(pagerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QueueSumBar(tasks: tasks),
        const SizedBox(height: 10),
        Expanded(child: QueueTable(tasks: tasks)),
        const SizedBox(height: 10),
        AppPager(
          total: tasks.length,
          page: pager.page,
          pageSize: pager.pageSize,
          onPage: ref.read(pagerProvider.notifier).goTo,
          onPageSize: ref.read(pagerProvider.notifier).setPageSize,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFD98C84).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.circleAlert, size: 15, color: Color(0xFFD98C84)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).queueLoadFailed(message),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFD98C84)),
            ),
          ),
        ],
      ),
    );
  }
}
