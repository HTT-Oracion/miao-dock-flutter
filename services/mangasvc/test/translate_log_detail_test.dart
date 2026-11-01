import 'dart:io';
import 'dart:typed_data';

import 'package:mangasvc/src/queue/task_queue.dart';
import 'package:test/test.dart';

/// D-128：翻译日志必须能定位问题。
///
/// 原来只有「任务创建 / 重试 / 开始翻译」，**失败原因完全不进日志**，
/// 用户看到「部分失败」却查不到错在哪。
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('log-detail-'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<List<String>> run({required bool fail, bool emitStage = false}) async {
    final files = <String>[];
    for (var i = 1; i <= 2; i++) {
      final f = File('${root.path}/src/${i.toString().padLeft(3, '0')}.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([i]);
      files.add(f.path);
    }
    final queue = TaskQueue(
      rootDir: '${root.path}/lib',
      stateDir: '${root.path}/state',
      engineMode: 'real',
      translateImage: (bytes, onStage) async {
        if (emitStage) onStage('detect 完成');
        if (fail) throw StateError('引擎端口 5180 拒绝连接');
        return Uint8List.fromList(bytes);
      },
    );
    await queue.createTask(comicName: '某书', imagePaths: files);
    for (var i = 0; i < 200; i++) {
      if (queue.translateLogTail(200).any((l) => l.contains('任务结束'))) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return queue.translateLogTail(200);
  }

  test('失败页必须写明原因', () async {
    final log = (await run(fail: true)).join('\n');
    // 破坏点：catch 里只记 failedReasons 不记日志 → 这行断言失败。
    expect(log, contains('失败'));
    expect(log, contains('引擎端口 5180 拒绝连接'));
  });

  test('任务结束要有成功/失败汇总', () async {
    final log = (await run(fail: false)).join('\n');
    expect(log, contains('任务结束'));
    expect(log, contains('成功 2'));
    expect(log, contains('done'));
  });

  test('引擎阶段输出要进日志', () async {
    final log = (await run(fail: false, emitStage: true)).join('\n');
    expect(log, contains('detect 完成'));
  });
}
