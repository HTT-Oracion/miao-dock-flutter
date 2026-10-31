import 'dart:convert';
import 'dart:io';

/// 中文硬编码棘轮检查（D-006）。
///
/// 规则：`lib/`（`lib/l10n/` 除外）里每个文件的中文字符串字面量数量
/// **不得超过** `tool/l10n_baseline.json` 里的基线值。
///
/// 为什么用棘轮而不是直接禁止：现存 115 处待迁移文案，一次性禁止会让检查永远红。
/// 棘轮保证「只准降不准升」——新增代码必须走 ARB，存量逐步清零。
///
/// 退出码：0 通过；1 有文件超出基线或新增了带中文的文件。
void main() {
  final baselineFile = File('tool/l10n_baseline.json');
  if (!baselineFile.existsSync()) {
    stderr.writeln('✖ 缺少 tool/l10n_baseline.json');
    exit(1);
  }
  final raw = jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>;
  final baseline = <String, int>{
    for (final e in raw.entries)
      if (!e.key.startsWith('_') && e.value is int) e.key: e.value as int,
  };

  final cn = RegExp(r'[\u4e00-\u9fff]');
  final strLit = RegExp(r"'([^'\\]|\\.)*'");
  final actual = <String, int>{};

  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (path.contains('/l10n/')) continue; // ARB 与生成物除外
    final src = entity.readAsStringSync();
    final n = strLit.allMatches(src).where((m) => cn.hasMatch(m.group(0)!)).length;
    if (n > 0) actual[path] = n;
  }

  final violations = <String>[];
  for (final entry in actual.entries) {
    final allowed = baseline[entry.key];
    if (allowed == null) {
      violations.add('${entry.key}: 新增文件含 ${entry.value} 处中文（基线未登记，须全部走 ARB）');
    } else if (entry.value > allowed) {
      violations.add('${entry.key}: ${entry.value} 处中文 > 基线 $allowed');
    }
  }

  // UI 层零容忍：Widget / 屏里一个中文都不许有（D-006 明文）。
  final uiOffenders = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (path.contains('/l10n/')) continue;
    final isUi = path.contains('/ui/') || path.contains('/shared/widgets/') || path.contains('/app/shell/');
    if (!isUi) continue;
    final n = strLit.allMatches(entity.readAsStringSync()).where((m) => cn.hasMatch(m.group(0)!)).length;
    if (n > 0) uiOffenders.add('$path: $n 处');
  }
  if (uiOffenders.isNotEmpty) {
    violations.addAll(uiOffenders.map((o) => 'UI 层硬编码中文（必须走 ARB）：$o'));
  }

  if (violations.isEmpty) {
    final total = actual.values.fold<int>(0, (a, b) => a + b);
    stdout.writeln('✔ l10n 棘轮通过：${actual.length} 个文件，共 $total 处待迁移中文（基线内渐进清零）');
    exit(0);
  }
  stderr.writeln('✖ l10n 棘轮未通过（新增文案必须走 lib/l10n/app_zh.arb）：');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  exit(1);
}
