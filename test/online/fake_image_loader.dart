import 'dart:io';
import 'dart:typed_data';

import 'package:miao_dock_flutter/features/manga/online/data/online_image_loader.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_error.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_models.dart';

class FakeImageLoader extends OnlineImageLoader {
  FakeImageLoader({this.failPage = 13});

  final int? failPage;
  final Set<String> _failed = {};

  static final Uint8List bytes = File('test/fixtures/online/page.png').readAsBytesSync();

  @override
  Future<Uint8List> load(
    ImageLoadingConfig config, {
    required String sourceId,
    List<String> allowedHosts = const [],
  }) async {
    final url = config.url ?? '';
    if (failPage != null && url.endsWith('/$failPage.jpg') && _failed.add(url)) {
      throw const OnlineException(OnlineErrorCode.blocked, '403 referer');
    }
    return bytes;
  }
}
