import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

/// D-041：发给引擎的默认配置必须与项目定案一致。
///
/// 这些值一旦退回引擎默认（sugoi / ENG / 48px），**不会报错**，
/// 只会悄悄给出英文译文、且下好的 Sakura 用不上 —— 所以逐项钉死。
void main() {
  test('OCR 用 mocr，且不开 use_mocr_merge', () {
    final ocr = defaultTranslateConfig['ocr'] as Map<String, dynamic>;
    // 破坏点：退回 48px → 用户的定案被推翻，本条失败。
    expect(ocr['ocr'], 'mocr');
    // 破坏点：开启合并 → 排版会爆（巨型字 + 截断），本条失败。
    expect(ocr['use_mocr_merge'], isFalse);
  });

  test('翻译器是 sakura、目标语言 CHS（不是引擎默认的 sugoi/ENG）', () {
    final t = defaultTranslateConfig['translator'] as Map<String, dynamic>;
    // 破坏点：漏传 → 引擎默认 sugoi + ENG，译文变英文，本条失败。
    expect(t['translator'], 'sakura');
    expect(t['target_lang'], 'CHS');
  });

  test('检测器与擦除与 miao-dock 一致', () {
    expect((defaultTranslateConfig['detector'] as Map)['detector'], 'default');
    expect((defaultTranslateConfig['inpainter'] as Map)['inpainter'], 'lama_large');
  });
}
