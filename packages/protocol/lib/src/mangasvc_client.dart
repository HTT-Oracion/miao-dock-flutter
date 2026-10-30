import 'dto/manga_task.dart';

/// mangasvc 客户端契约（App 依赖此接口，不依赖实现；见 AGENTS §3）。
abstract class MangasvcClient {
  /// 队列全量任务（串行队列，按提交顺序）。
  Future<List<MangaTask>> listTasks();

  /// 投放：一组图片文件路径 + 漫画名。
  Future<SubmitResult> submit({required String comicName, required List<String> imagePaths});

  /// 删除任务记录（只清记录，不动漫画库里的文件）；全量 = 传 null。
  Future<void> deleteTasks(Set<String>? taskIds);

  /// 取消任务（保留已落盘的译文）。
  Future<void> cancelTask(String taskId);
}
