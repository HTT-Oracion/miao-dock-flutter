/// App 与服务共享的 DTO 与 API 契约唯一出口（barrel）。
///
/// DTO（`src/dto/`）、客户端接口、HTTP 实现、Fake 替身随首个服务接口落地；
/// 目录规划见 README。`lib/` 与 `services/*` 都只从这里 import，不得各自另写一套。
library;
