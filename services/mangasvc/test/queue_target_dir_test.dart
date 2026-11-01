import 'dart:io';

import 'package:mangasvc/src/queue/task_queue.dart';
import 'package:test/test.dart';

/// D-088：补页/返工任务的落盘目录必须是**原话目录**，不能按 comicName 另建一层。
void main() {
  late Directory root;
  late Directory chapter;
  late TaskQueue queue;

  setUp(() {
    root = Directory.systemTemp.createTempSync('q-target-test-');
    chapter = Directory('${root.path}/某书/01_第1话')..createSync(recursive: true);
    File('${chapter.path}/001.png').writeAsBytesSync([1]);
    queue = TaskQueue(rootDir: root.path, stateDir: '${root.path}/.miao-state', engineMode: 'mock');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('targetDir 生效：译文写进原话目录，书根不出现散落文件', () async {
    await queue.createTask(comicName: '某书', imagePaths: ['${chapter.path}/001.png'], targetDir: chapter.path);
    // 等任务跑完（mock 引擎很快）。
    for (var i = 0; i < 100; i++) {
      final tasks = (queue.listView())['tasks'] as List;
      if (tasks.isNotEmpty && (tasks.first as Map)['status'] == 'done') break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(File('${chapter.path}/001_translated.png').existsSync(), isTrue);
    // 破坏点：落盘用了 comicName 而非 targetDir → 书根出现 001_translated.png。
    expect(File('${root.path}/某书/001_translated.png').existsSync(), isFalse);
  });
}
