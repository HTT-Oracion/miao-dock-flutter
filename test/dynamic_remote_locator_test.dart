import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/core/net/manga_svc_http.dart';
import 'package:miao_dock_flutter/core/net/service_locator.dart';

void main() {
  test('远程配置保存后下一次请求使用新地址与令牌', () async {
    var address = 'http://192.168.1.2:5180';
    var token = 'old';
    final built = <(String, String?)>[];
    final locator = DynamicRemoteServiceLocator(
      readBaseUrl: () => address,
      readToken: () => token,
      factory: (baseUrl, value) {
        built.add((baseUrl, value));
        return MangaSvcHttpClient(baseUrl: baseUrl, token: value);
      },
    );

    final first = await locator.client();
    expect((await locator.client()), same(first));

    address = 'http://192.168.1.3:5181';
    token = 'new';
    final second = await locator.client();

    // 破坏点：启动时缓存 RemoteServiceLocator → 设置页校验成功，但队列仍请求旧地址。
    expect(second, isNot(same(first)));
    expect(built, [('http://192.168.1.2:5180/api/v1', 'old'), ('http://192.168.1.3:5181/api/v1', 'new')]);
  });
}
