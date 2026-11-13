import '../../domain/music_models.dart';

/// 二维码登录的**平台无关契约**。
///
/// 为什么要这层：网易云（`unikey` + `client/login`）与酷狗（`/v2/qrcode` +
/// `/v2/get_userinfo_qrcode`）的端点、参数、状态码语义都不一样，但上层控制器
/// 只关心「拿到码 → 轮询 → 成功拿 cookie」这一段。把差异收在适配器里，
/// 控制器与 UI 不必按平台写分支。
abstract interface class QrLoginAdapter {
  MusicPlatform get platform;

  /// 取二维码。
  Future<QrLoginTicket> requestTicket();

  /// 轮询一次扫码状态。
  Future<QrLoginPoll> poll(String ticket);
}

/// 二维码票据。[imageBase64] 非空时可直接显示（酷狗直接给图），
/// 否则用 [content] 自行渲染（网易云给的是登录 URL）。
class QrLoginTicket {
  const QrLoginTicket({required this.ticket, this.content, this.imageBase64});

  /// 轮询用的 key。
  final String ticket;

  /// 二维码内容（URL 等）。
  final String? content;

  /// `data:image/png;base64,...` 形式的图片。
  final String? imageBase64;
}

/// 轮询结果。[cookie] 非 null 表示登录完成，可直接落盘。
class QrLoginPoll {
  const QrLoginPoll({required this.state, this.cookie, this.nick});

  final QrPollState state;
  final String? cookie;
  final String? nick;
}

/// 归一化后的扫码状态。
enum QrPollState {
  /// 等待扫码。
  waiting,

  /// 已扫码，待手机端确认。
  scanned,

  /// 授权成功（此时 [QrLoginPoll.cookie] 应非空）。
  success,

  /// 二维码过期。
  expired,

  /// 被风控或其它业务原因拒绝。
  rejected,
}
