import 'dart:io';

import 'package:mangasvc/src/queue/task_queue.dart';
import 'package:test/test.dart';

/// D-129：前置校验失败时，任务**建出来但直接 failed**，不进翻译流水线。
///
/// 场景：选了远程翻译但 token / 地址无效 —— 不该先跑一遍引擎再失败。
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fail-fast-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('failReason 非空 → 直接 failed 且不调用引擎', () async {
    var engineCalls = 0;
    final queue = TaskQueue(
      rootDir: '${root.path}/lib',
      stateDir: '${root.path}/state',
      engineMode: 'real',
      translateImage: (bytes, onStage) async {
        engineCalls++;
        return bytes;
      },
    );
    final f = File('${root.path}/src/001.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);

    final created = await queue.createTask(comicName: '某书', imagePaths: [f.path], failReason: '远程翻译配置不生效，请到设置页进行配置');

    final task = queue.getTask(created['taskId'] as String)!;
    expect(task.status, TaskStatus.failed);
    // 破坏点：仍然排进队列跑引擎 → 这条断言失败。
    expect(engineCalls, 0);
    // 失败原因要能带出来（用户要知道为什么不跑）。
    expect(task.failedReasons.join(), contains('远程翻译配置不生效'));
  });

  test('重试带 failReason → 直接回 failed 且不调用引擎', () async {
    var engineCalls = 0;
    final queue = TaskQueue(
      rootDir: '${root.path}/lib',
      stateDir: '${root.path}/state',
      engineMode: 'real',
      translateImage: (bytes, onStage) async {
        engineCalls++;
        return bytes;
      },
    );
    final f = File('${root.path}/src/001.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    // 先建一条失败的假想任务（fail-fast）。
    final created = await queue.createTask(comicName: '某书', imagePaths: [f.path], failReason: '远程翻译配置不生效');
    // 破坏点：重试不接 failReason → 会重新排队跑引擎。
    await queue.retryTask(created['taskId'] as String, failReason: '远程翻译配置不生效');
    final task = queue.getTask(created['taskId'] as String)!;
    expect(task.status, TaskStatus.failed);
    expect(engineCalls, 0);
    expect(task.failedReasons.join(), contains('远程翻译配置不生效'));
  });

  test('failReason 为空 → 正常进队列', () async {
    final queue = TaskQueue(rootDir: '${root.path}/lib', stateDir: '${root.path}/state', engineMode: 'mock');
    final f = File('${root.path}/src/001.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    final created = await queue.createTask(comicName: '某书', imagePaths: [f.path]);
    final task = queue.getTask(created['taskId'] as String)!;
    expect(task.status, isNot(TaskStatus.failed));
  });
}
