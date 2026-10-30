/// App 与服务共享的 DTO 与 API 契约唯一出口（barrel）。
///
/// `lib/` 与 `services/*` 都只从这里 import，不得各自另写一套。
library;

export 'src/dto/manga_task.dart';
export 'src/mangasvc_client.dart';
export 'src/fake_mangasvc.dart';
