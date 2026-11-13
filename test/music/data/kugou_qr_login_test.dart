import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/data/api/kugou_api.dart';
import 'package:miao_dock_flutter/features/music/data/api/music_qr_login.dart';
import 'package:miao_dock_flutter/features/music/data/api/qr_login_adapters.dart';
import 'package:miao_dock_flutter/features/music/domain/music_models.dart';

/// 酷狗二维码登录：状态码映射与适配器装配。
///
/// 破坏点：
/// · 状态码映射错（酷狗是 0/1/2/4，不是网易云的 800/801/802/803）→ 扫码成功后
///   被当成 rejected，永远登不上；
/// · 适配器没注册酷狗 → 平台被判「不支持扫码登录」。
void main() {
  test('酷狗适配器已注册（QQ / 咪咕不支持）', () {
    expect(qrLoginAdapterFor(MusicPlatform.kugou), isA<KugouQrLoginAdapter>());
    expect(qrLoginAdapterFor(MusicPlatform.netease), isA<NeteaseQrLoginAdapter>());
    // 参考实现里 QQ / 咪咕没有二维码登录接口。
    expect(qrLoginAdapterFor(MusicPlatform.qq), isNull);
    expect(qrLoginAdapterFor(MusicPlatform.migu), isNull);
  });

  test('酷狗适配器把状态码 4 映射为成功并透传 cookie', () async {
    final api = _FakeKugou(status: 4, resultCookie: 'userid=1; token=abc; mid=m');
    final adapter = KugouQrLoginAdapter(api: api);

    final poll = await adapter.poll('k');
    // 破坏点：按网易云的 803 判成功 → 酷狗的 4 落进 rejected，永远登不上。
    expect(poll.state, QrPollState.success);
    expect(poll.cookie, contains('token='));
  });

  test('酷狗状态码 0 / 1 / 2 分别映射为过期 / 等待 / 已扫', () async {
    for (final (code, expected) in [(0, QrPollState.expired), (1, QrPollState.waiting), (2, QrPollState.scanned)]) {
      final adapter = KugouQrLoginAdapter(api: _FakeKugou(status: code, resultCookie: null));
      expect((await adapter.poll('k')).state, expected);
    }
  });
}

/// 假酷狗客户端：只替换二维码相关方法。
class _FakeKugou extends KugouApi {
  _FakeKugou({required this.status, this.resultCookie});

  final int status;
  final String? resultCookie;

  @override
  Future<({String key, String? imageBase64})> qrKey() async =>
      (key: 'fake-key', imageBase64: 'data:image/png;base64,AAAA');

  @override
  Future<({int status, String? cookie})> qrCheck(String key) async => (status: status, cookie: resultCookie);
}
