import 'dart:io';

import 'package:test/test.dart';

import 'package:mangasvc/src/server/http.dart';
import 'package:mangasvc/src/store/plans.dart';

/// B7/B8 断言：续做/返工计划与话号规则。
void main() {
  late Directory tmp;
  late Directory chapter;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('miao_plans_');
    chapter = Directory('${tmp.path}/01_第1话')..createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void png(String name) => File('${chapter.path}/$name').writeAsBytesSync([1, 2, 3]);

  group('续做计划（只列缺译文的页）', () {
    test('只有原图的页进 pendings', () {
      png('001.png');
      png('002.png');
      png('003_translated.png');

      final plan = buildResumePlan('01_第1话', chapter);
      // 破坏点：把已译页也算进 pendings → 会重复翻译，本条失败。
      expect(plan['imageCount'], 2);
      expect(plan['translatedCount'], 1);
      expect(plan['pendingCount'], 2);
      final pendings = (plan['pendings'] as List).cast<Map<String, dynamic>>();
      expect(pendings.map((p) => p['seq']), [1, 2]);
    });

    test('全部已译时 pendingCount 为 0', () {
      png('001.png');
      png('001_translated.png');
      final plan = buildResumePlan('x', chapter);
      // 破坏点：把「有原图」当成「待补」→ 本条失败。
      expect(plan['pendingCount'], 0);
      expect(plan['imageCount'], 1);
    });
  });

  group('返工计划（含全部有原图的页 + 覆盖数）', () {
    test('candidates 含已译页并标 hadTranslation', () {
      png('001.png');
      png('001_translated.png');
      png('002.png');

      final plan = buildRetranslatePlan('x', chapter);
      // 破坏点：漏掉已译页 → 用户无法「重译已译那几页」，本条失败。
      expect(plan['retranslateCount'], 2);
      expect(plan['overwriteCount'], 1);
      final cands = (plan['candidates'] as List).cast<Map<String, dynamic>>();
      expect(cands.firstWhere((c) => c['seq'] == 1)['hadTranslation'], isTrue);
      expect(cands.firstWhere((c) => c['seq'] == 2)['hadTranslation'], isFalse);
    });
  });

  group('话号规则（与原项目同口径）', () {
    test('接受整数与一位小数', () {
      expect(parseChapterNo('1'), 1);
      expect(parseChapterNo('999'), 999);
      expect(parseChapterNo('1.5'), 1.5);
    });

    test('拒绝 0 / 超界 / 两位小数（不静默降级）', () {
      // 破坏点：非法话号被当成 1 → 会写错目录，本条失败。
      expect(() => parseChapterNo('0'), throwsA(isA<ServiceError>()));
      expect(() => parseChapterNo('1000'), throwsA(isA<ServiceError>()));
      expect(() => parseChapterNo('1.25'), throwsA(isA<ServiceError>()));
      expect(() => parseChapterNo('abc'), throwsA(isA<ServiceError>()));
    });

    test('目录名补两位（保证字典序 = 数字序）', () {
      // 破坏点：不补零 → 10 排在 9 前面，本条失败。
      expect(chapterDirName(1), '01_第1话');
      expect(chapterDirName(9), '09_第9话');
      expect(chapterDirName(10), '10_第10话');
      expect(chapterDirName(1.5), '1.5_第1.5话');
    });
  });
}
