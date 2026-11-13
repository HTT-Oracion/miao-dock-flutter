import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/features/music/controller/music_providers.dart';

import 'support/stub_registry.dart';

void main() {
  test('debug registry', () {
    final c = ProviderContainer(
      overrides: [
        jsMusicSourceRegistryProvider.overrideWith(() => StubRegistry([neteaseSourceFromRepo()])),
      ],
    );
    final list = c.read(jsMusicSourceRegistryProvider);
    // ignore: avoid_print
    print('COUNT=${list.length}');
    for (final s in list) {
      // ignore: avoid_print
      print(
        'id=${s.id} platformId=${s.platformId} available=${s.isAvailable} '
        'loginNull=${s.manifest.login == null} caps=${s.capabilities}',
      );
    }
  });
}
