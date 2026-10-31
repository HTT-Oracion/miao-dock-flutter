import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'package:miao_dock_flutter/features/manga/ui/notready/backend_picker.dart';

/// D-034：后端探测的判据（只在 Windows / Linux 生效）。
void main() {
  test('有 NVIDIA 运行时 → 推荐 CUDA 并说明理由', () async {
    final probe = await probeBackend(runnable: (exe, args) async => exe == 'nvidia-smi');
    if (Platform.isWindows || Platform.isLinux) {
      // 破坏点：探测到 N 卡却推荐 CPU → 用户白丢几倍速度，本条失败。
      expect(probe.recommended, LlamaBackend.cuda12);
    } else {
      // macOS 不适用后端概念：仍返回一个可用值即可。
      expect(probe.recommended, isNotNull);
    }
  });

  test('没有 NVIDIA → 不推荐 CUDA', () async {
    final probe = await probeBackend(runnable: (exe, args) async => false);
    // 破坏点：探测不到也推荐 CUDA → 无卡机器上必装失败，本条失败。
    expect(probe.recommended, isNot(LlamaBackend.cuda12));
  });

  test('候选集不含 DirectML，且 CUDA 固定 12.4', () {
    final ids = LlamaBackend.values.map((b) => b.id);
    // 破坏点：加回 directml / cuda-13.4 → 用户选了下载不到，本条失败。
    expect(ids, isNot(contains('directml')));
    expect(ids, isNot(contains('cuda-13.4')));
    expect(ids, contains('cuda-12.4'));
  });
}
