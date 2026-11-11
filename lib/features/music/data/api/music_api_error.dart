/// 音乐平台接口异常（错误码由仓库层转成 [MusicRepositoryException]）。
///
/// 第三方接口经常用 HTTP 200 + 业务 code 报错（网易云 301 未登录 / 酷狗 err_code），
/// 因此解析层也要能抛 [parse] 与 [business]，不能只看状态码。
class MusicApiException implements Exception {
  const MusicApiException(this.kind, this.platform, this.message, {this.status, this.cause});

  MusicApiException.network(this.platform, this.message, {this.cause})
    : kind = MusicApiErrorKind.network,
      status = null;

  MusicApiException.http(this.platform, int status, String url)
    : kind = MusicApiErrorKind.http,
      status = status,
      message = 'HTTP $status @ $url',
      cause = null;

  MusicApiException.parse(this.platform, String url, {this.cause})
    : kind = MusicApiErrorKind.parse,
      status = null,
      message = 'unparseable response · $url';

  MusicApiException.business(this.platform, this.message, {this.status})
    : kind = MusicApiErrorKind.business,
      cause = null;

  final MusicApiErrorKind kind;
  final String platform;
  final String message;
  final int? status;
  final Object? cause;

  @override
  String toString() => 'MusicApiException(${kind.name}, $platform): $message';
}

enum MusicApiErrorKind {
  /// 网络不可达 / 超时。
  network,

  /// 非 2xx。
  http,

  /// 响应不是预期的 JSON 结构。
  parse,

  /// 业务错误（未登录、无版权、需要会员）。
  business,
}
