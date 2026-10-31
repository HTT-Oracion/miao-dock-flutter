/// App 与服务共享的 DTO 与 API 契约唯一出口（barrel）。
///
/// `lib/` 与 `services/*` 都只从这里 import，不得各自另写一套。
library;

export 'src/dto/api_error.dart';
export 'src/engine_config.dart';
export 'src/engine_parts.dart';
export 'src/dto/engine.dart';
export 'src/dto/library.dart';
export 'src/dto/task_row.dart';
export 'src/dto/task_status.dart';
export 'src/fake_manga_svc.dart';

export 'src/manga_svc_client.dart';
