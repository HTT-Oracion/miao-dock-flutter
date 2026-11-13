import '../../domain/music_models.dart';
import 'kugou_api.dart';
import 'music_qr_login.dart';
import 'netease_api.dart';

/// 网易云二维码登录适配器（EAPI 加密通道）。
class NeteaseQrLoginAdapter implements QrLoginAdapter {
  NeteaseQrLoginAdapter({NeteaseApi? api}) : _api = api ?? NeteaseApi();

  final NeteaseApi _api;

  @override
  MusicPlatform get platform => MusicPlatform.netease;

  @override
  Future<QrLoginTicket> requestTicket() async {
    final key = await _api.qrKey();
    return QrLoginTicket(ticket: key, content: 'https://music.163.com/login?codekey=$key');
  }

  @override
  Future<QrLoginPoll> poll(String ticket) async {
    final r = await _api.qrCheck(ticket);
    final state = switch (r.code) {
      801 => QrPollState.waiting,
      802 => QrPollState.scanned,
      803 => QrPollState.success,
      800 => QrPollState.expired,
      _ => QrPollState.rejected,
    };
    return QrLoginPoll(state: state, cookie: r.cookie, nick: r.nick);
  }

  /// 收尾：丢掉该 key 的 Cookie 罐（重试 / 关闭弹窗时调用）。
  void dropCookies(String? key) => _api.dropQrCookies(key);
}

/// 酷狗二维码登录适配器（`login-user.kugou.com`，Web 签名）。
class KugouQrLoginAdapter implements QrLoginAdapter {
  KugouQrLoginAdapter({KugouApi? api}) : _api = api ?? KugouApi();

  final KugouApi _api;

  @override
  MusicPlatform get platform => MusicPlatform.kugou;

  @override
  Future<QrLoginTicket> requestTicket() async {
    final r = await _api.qrKey();
    return QrLoginTicket(
      ticket: r.key,
      // 酷狗直接返回整张二维码图；没有图时回落到 h5 登录页链接。
      content: 'https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode=${r.key}',
      imageBase64: r.imageBase64,
    );
  }

  @override
  Future<QrLoginPoll> poll(String ticket) async {
    final r = await _api.qrCheck(ticket);
    // 酷狗状态码：0 过期 / 1 等待 / 2 待确认 / 4 成功。
    final state = switch (r.status) {
      0 => QrPollState.expired,
      1 => QrPollState.waiting,
      2 => QrPollState.scanned,
      4 => QrPollState.success,
      _ => QrPollState.rejected,
    };
    return QrLoginPoll(state: state, cookie: r.cookie);
  }
}

/// 按平台取适配器；该平台不支持二维码登录时返回 null。
QrLoginAdapter? qrLoginAdapterFor(MusicPlatform platform, {String cookie = ''}) => switch (platform) {
  MusicPlatform.netease => NeteaseQrLoginAdapter(api: NeteaseApi(cookie: cookie)),
  MusicPlatform.kugou => KugouQrLoginAdapter(api: KugouApi(cookie: cookie)),
  // QQ / 咪咕：参考实现没有二维码登录（只有 cookie 回读 / 手机号-短信-账密）。
  MusicPlatform.qq || MusicPlatform.migu || MusicPlatform.local => null,
};
