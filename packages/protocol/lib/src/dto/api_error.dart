/// 服务错误信封 —— 对应原项目响应体的 `{ "error": { code, message, details } }`。
///
/// 界面上**不直接展示 `message`**（见 AGENTS §3 国际化约束）：按 [code] 映射到 ARB 词条，
/// `message` 只作为诊断信息落日志或「详情」展开。
class ApiError {
  const ApiError({required this.code, required this.message, this.details});

  /// 机器可读错误码，如 `INVALID_IMAGE` / `INVALID_SETTING` / `NOT_FOUND`。
  final String code;

  /// 服务端原话（中文），仅供诊断。
  final String message;

  /// 结构化细节（字段随端点而异）。
  final Map<String, dynamic>? details;
}

/// 传输层异常：把 HTTP / 网络 / 契约解析失败收敛成一种类型，避免各层各判一套。
class MangaSvcException implements Exception {
  const MangaSvcException({required this.kind, required this.message, this.statusCode, this.apiError});

  final MangaSvcErrorKind kind;
  final String message;
  final int? statusCode;
  final ApiError? apiError;

  /// 服务端错误码（无则为 null）。
  String? get code => apiError?.code;

  @override
  String toString() => 'MangaSvcException(${kind.name}, status=$statusCode, code=${apiError?.code}): $message';
}

/// 失败原因分类 —— 决定 UI 给哪种呈现（失败态 / 未就绪 / 重试 / 配对）。
enum MangaSvcErrorKind {
  /// 连不上（服务未启动 / 端口探测全失败）。
  unreachable,

  /// 鉴权失败（令牌无效或缺失）。
  unauthorized,

  /// 服务端返回了错误信封。
  apiError,

  /// 响应不是合法 JSON，或字段不符合契约。
  protocol,

  /// 超时。
  timeout,

  /// 其他。
  unknown,
}
