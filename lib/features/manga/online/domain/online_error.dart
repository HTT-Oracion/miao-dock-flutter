/// 源错误码（plan §5.5，11 个）。
///
/// UI **只**按错误码映射 ARB，不上屏 JS 抛出的原文；`message` 仅用于详情日志。
enum OnlineErrorCode {
  http,
  network,
  timeout,
  blocked,
  parse,
  notFound,
  auth,
  rateLimited,
  hostNotAllowed,
  specUnsupported,
  crashed;

  String get wireName => switch (this) {
    OnlineErrorCode.http => 'HTTP_ERROR',
    OnlineErrorCode.network => 'NETWORK',
    OnlineErrorCode.timeout => 'TIMEOUT',
    OnlineErrorCode.blocked => 'BLOCKED',
    OnlineErrorCode.parse => 'PARSE_FAILED',
    OnlineErrorCode.notFound => 'NOT_FOUND',
    OnlineErrorCode.auth => 'AUTH_REQUIRED',
    OnlineErrorCode.rateLimited => 'RATE_LIMITED',
    OnlineErrorCode.hostNotAllowed => 'HOST_NOT_ALLOWED',
    OnlineErrorCode.specUnsupported => 'SPEC_UNSUPPORTED',
    OnlineErrorCode.crashed => 'SOURCE_CRASHED',
  };
}

/// 在线漫画异常。`message` 只写入日志，不上 UI。
class OnlineException implements Exception {
  const OnlineException(this.code, [this.message = '', this.status]);

  final OnlineErrorCode code;
  final String message;
  final int? status;

  @override
  String toString() =>
      'OnlineException(${code.wireName}${status == null ? '' : ' $status'}${message.isEmpty ? '' : ': $message'})';
}

/// 分类 / 搜索 / 分页请求失败时保留旧数据用的轻量状态。
class OnlinePageStatus {
  const OnlinePageStatus({this.loading = false, this.error, this.hasMore = false});

  final bool loading;
  final Object? error;
  final bool hasMore;
}
