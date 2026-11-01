import 'dart:io';
import 'dart:typed_data';

import 'package:mangasvc/src/queue/task_queue.dart';
import 'package:test/test.dart';

/// D-127：任务终态必须三分支（对齐 miao-dock `end_status_of`）。
///
/// - 无失败 → `done`
/// - 有成功也有失败 → `partial_failed`
/// - **全部失败 → `failed`**（原实现只要 failed>0 就是 partial_failed，
///   因此「每一页都失败」永远显示成「部分失败」）
void main() {
  late Directory root;
  late TaskQueue queue;

  setUp(() {
    root = Directory.systemTemp.createTempSync('q-end-status-');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<String> runWith(int pages, {required bool allFail}) async {
    final files = <String>[];
    for (var i = 1; i <= pages; i++) {
      final f = File('${root.path}/src/${i.toString().padLeft(3, '0')}.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([i]);
      files.add(f.path);
    }
    // engineMode != 'mock' → 走真实分支，由 translateImage 决定成败。
    queue = TaskQueue(
      rootDir: '${root.path}/lib',
      stateDir: '${root.path}/state',
      engineMode: 'real',
      translateImage: (bytes, onStage) async {
        if (allFail) throw StateError('引擎炸了');
        return Uint8List.fromList(bytes);
      },
    );
    await queue.createTask(comicName: '某书', imagePaths: files);
    for (var i = 0; i < 200; i++) {
      final tasks = (queue.listView())['tasks'] as List;
      if (tasks.isNotEmpty) {
        final st = (tasks.first as Map)['status'];
        if (st == 'done' || st == 'partial_failed' || st == 'failed') return '$st';
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return 'timeout';
  }

  test('全部页失败 → failed（不是 partial_failed）', () async {
    // 破坏点：只判 failed>0 → 这里会得到 partial_failed。
    expect(await runWith(2, allFail: true), 'failed');
  });

  test('全部成功 → done', () async {
    expect(await runWith(2, allFail: false), 'done');
  });
}
