import 'dart:convert';
import 'dart:io';

import 'package:protocol/protocol.dart';

import 'paths.dart';

/// 引擎目录的**校验**（D-027）—— 供「校验」按钮与导入流程使用。
///
/// ## 三级检查，结论不同
/// 1. **结构**：关键目录/文件在不在（快，纯 IO）；
/// 2. **可运行**：解释器能不能起来、关键依赖能不能 import（会起一次子进程）；
/// 3. **元数据**：`.engine.json` 的版本与后端。
///
/// 🔴 第 2 级必须真的 import 一次：只检查 `site-packages` 非空，
/// 会把「装了一半」判成就绪 —— 然后用户在翻译时才撞见 `ImportError`。
///
/// ## 失败要能看懂
/// 每条失败都带**具体路径或异常原文**，直接喂给 `LogBox`；
/// 只说「校验失败」等于没校验。
class EngineInspection {
  const EngineInspection({
    required this.engineDir,
    required this.checks,
    this.version,
    this.llamaBackend,
    this.manifestMissing = false,
  });

  final String engineDir;
  final List<PartCheck> checks;

  /// `.engine.json` 里的引擎版本。
  final String? version;

  /// `.engine.json` 里记录的推理后端。
  final String? llamaBackend;

  /// 缺 `.engine.json`：允许导入，但只能做结构检查。
  final bool manifestMissing;

  bool get ok => checks.where((c) => c.part.required).every((c) => c.ok);

  /// 有问题的必需部件。
  List<PartCheck> get failedRequired => checks.where((c) => c.part.required && !c.ok).toList();

  /// 可供给界面的日志行（一次校验的完整输出，不只是失败项）。
  List<String> get logLines => [
    for (final c in checks) ...[
      '[check] ${c.part.id}: ${c.ok ? 'OK' : 'FAILED'}${c.detail == null ? '' : ' (${c.detail})'}',
      ...c.logs,
    ],
    if (manifestMissing) '[check] manifest: 缺失 .engine.json（只能做结构检查，完整性未校验）',
  ];
}

/// 单个部件的检查结果。
class PartCheck {
  const PartCheck({required this.part, required this.ok, this.detail, this.logs = const []});

  final EnginePart part;
  final bool ok;

  /// 成功时的补充信息（版本号、后端名等）。
  final String? detail;

  /// 失败时的细节行（异常原文、缺失路径）。
  final List<String> logs;
}

/// 校验一个引擎目录。
///
/// [probePython] 为 false 时跳过「起子进程 import」这一步（单元测试用）。
Future<EngineInspection> inspectEngine(
  String engineDir, {
  bool probePython = true,
  Duration pythonTimeout = const Duration(seconds: 25),
}) async {
  final sep = Platform.pathSeparator;
  final checks = <PartCheck>[];

  // ── python ───────────────────────────────────────────────────────────
  final pyPath = enginePythonPath(engineDir);
  final pyFile = File(pyPath);
  // 「解释器可用」与「拿到了版本号」是两件事：跳过探测时前者仍为真。
  var pythonUsable = false;
  if (!pyFile.existsSync()) {
    checks.add(PartCheck(part: EnginePart.python, ok: false, logs: ['  缺失解释器：$pyPath']));
  } else if (probePython) {
    try {
      final r = await Process.run(pyPath, ['-V']).timeout(pythonTimeout);
      final out = '${r.stdout}${r.stderr}'.trim();
      if (r.exitCode == 0) {
        pythonUsable = true;
        checks.add(PartCheck(part: EnginePart.python, ok: true, detail: out));
      } else {
        checks.add(PartCheck(part: EnginePart.python, ok: false, logs: ['  解释器存在但无法运行（退出码 ${r.exitCode}）：$out']));
      }
    } catch (e) {
      // 跨平台/跨架构的典型表现：二进制格式不对，直接跑不起来。
      checks.add(PartCheck(part: EnginePart.python, ok: false, logs: ['  解释器无法执行（可能是平台或架构不匹配）：$e']));
    }
  } else {
    pythonUsable = true;
    checks.add(PartCheck(part: EnginePart.python, ok: true, detail: pyPath));
  }

  // ── src ──────────────────────────────────────────────────────────────
  final srcDir = engineSrcDir(engineDir);
  final pkgDir = Directory('$srcDir${sep}manga_translator');
  final reqFile = File('$srcDir${sep}requirements.txt');
  if (pkgDir.existsSync()) {
    checks.add(
      PartCheck(part: EnginePart.source, ok: true, detail: reqFile.existsSync() ? '含 requirements.txt' : null),
    );
  } else {
    checks.add(PartCheck(part: EnginePart.source, ok: false, logs: ['  缺少包目录：${pkgDir.path}']));
  }

  // ── deps ─────────────────────────────────────────────────────────────
  if (!pythonUsable) {
    checks.add(PartCheck(part: EnginePart.deps, ok: false, logs: ['  无法检查依赖：解释器不可用']));
  } else if (!probePython) {
    checks.add(const PartCheck(part: EnginePart.deps, ok: true));
  } else {
    // 🔴 真的 import 一次。只查 site-packages 非空会把「装了一半」判成就绪。
    const probe = 'import torch, transformers, cv2';
    try {
      final r = await Process.run(pyPath, ['-c', probe]).timeout(pythonTimeout);
      if (r.exitCode == 0) {
        checks.add(const PartCheck(part: EnginePart.deps, ok: true, detail: 'torch / transformers / cv2 可导入'));
      } else {
        final err = '${r.stderr}'.trim();
        checks.add(
          PartCheck(
            part: EnginePart.deps,
            ok: false,
            logs: ['  `$probe` 失败（退出码 ${r.exitCode}）', for (final line in _tail(err, 6)) '  $line'],
          ),
        );
      }
    } catch (e) {
      checks.add(PartCheck(part: EnginePart.deps, ok: false, logs: ['  依赖探测超时或异常：$e']));
    }
  }

  // ── llama ────────────────────────────────────────────────────────────
  final llamaDir = engineLlamaDir(engineDir);
  final exe = Platform.isWindows ? 'llama-server.exe' : 'llama-server';
  final exeFile = File('$llamaDir$sep$exe');
  if (exeFile.existsSync()) {
    checks.add(PartCheck(part: EnginePart.llama, ok: true, detail: llamaDir));
  } else {
    checks.add(PartCheck(part: EnginePart.llama, ok: false, logs: ['  缺少 llama-server：${exeFile.path}']));
  }

  // ── models-visual ────────────────────────────────────────────────────
  final modelsDir = engineModelsDir(engineDir);
  final missingVisual = <String>[];
  for (final sub in ['detection', 'inpainting', 'ocr', 'fonts']) {
    final d = Directory('$modelsDir$sep$sub');
    if (!d.existsSync() || d.listSync().isEmpty) missingVisual.add(sub);
  }
  checks.add(
    PartCheck(
      part: EnginePart.modelsVisual,
      ok: missingVisual.isEmpty,
      detail: missingVisual.isEmpty ? null : null,
      logs: missingVisual.isEmpty ? const [] : ['  视觉模型缺失子目录：${missingVisual.join(', ')}', '  位置：$modelsDir'],
    ),
  );

  // ── llm（Sakura，由 llama-server 加载）────────────────────────────────
  final llmDirPath = engineLlmDir(engineDir);
  final llmDir = Directory(llmDirPath);
  final ggufs = llmDir.existsSync()
      ? llmDir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.gguf')).toList()
      : <File>[];
  checks.add(
    PartCheck(
      part: EnginePart.llm,
      ok: ggufs.isNotEmpty,
      detail: ggufs.isNotEmpty ? ggufs.first.uri.pathSegments.last : null,
      logs: ggufs.isEmpty ? ['  没有找到 .gguf 权重：$llmDirPath'] : const [],
    ),
  );

  // ── models-nllb（按需）────────────────────────────────────────────────
  final nllbDir = Directory('$modelsDir${sep}translators${sep}nllb');
  final nllbPresent = nllbDir.existsSync() && nllbDir.listSync().isNotEmpty;
  checks.add(PartCheck(part: EnginePart.modelsNllb, ok: nllbPresent, detail: nllbPresent ? '已安装' : '未安装（按需）'));

  // ── 元数据 ───────────────────────────────────────────────────────────
  final manifestFile = File(engineManifestPath(engineDir));
  String? version;
  String? backend;
  var manifestMissing = false;
  if (!manifestFile.existsSync()) {
    manifestMissing = true;
  } else {
    try {
      final m = jsonDecode(manifestFile.readAsStringSync());
      if (m is Map) {
        version = m['engineVersion']?.toString();
        backend = m['llamaBackend']?.toString();
      }
    } catch (_) {
      // 元数据坏了不影响「能不能用」，但要在日志里说清。
      manifestMissing = true;
    }
  }

  return EngineInspection(
    engineDir: engineDir,
    checks: checks,
    version: version,
    llamaBackend: backend,
    manifestMissing: manifestMissing,
  );
}

/// 取末尾 n 行非空输出（异常栈通常关键信息在后面）。
List<String> _tail(String text, int n) {
  final lines = text.split('\n').map((l) => l.trimRight()).where((l) => l.isNotEmpty).toList();
  if (lines.length <= n) return lines;
  return lines.sublist(lines.length - n);
}
