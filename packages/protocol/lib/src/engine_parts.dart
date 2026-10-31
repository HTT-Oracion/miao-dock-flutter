/// 引擎目录的**部件模型**（D-027）。
///
/// ## 为什么按「部件」而不是「整包」
/// 现实里的导入场景很杂：有人搬来整套；有人只有运行时、想省下 4 GB 模型；
/// 有人只想补 nllb。整包式（缺一个文件就拒绝导入）会把这些场景全部废掉。
/// 部件化之后**一种机制覆盖全部**：允许导入，把缺失可视化，逐件补齐。
///
/// ## 与目录布局的关系
/// ```text
/// <engine>/                     ← 一个可搬移 / 可导入的根
///   python/  src/  bin/llama/   ← 运行时三件
///   models/                     ← MIT 的 model_dir（结构遵从上游）
///   llm/                        ← llama-server 加载的权重
/// ```
/// 本文件只放**纯数据与路径映射**，不碰文件系统 —— 服务与 App 各自做 IO，
/// 但「部件有哪些、相对路径是什么、清单前缀怎么改写」只在这里定义一次。
library;

/// 引擎目录的一个部件。
enum EnginePart {
  /// 自带 Python 解释器 + 已装的 pip 依赖。
  python('python', '自带解释器', required: true),

  /// 引擎源码。
  source('src', '引擎源码', required: true),

  /// pip 依赖（装在 `python/` 的 site-packages 里）。
  ///
  /// 与 [python] 分开是因为**它们的可修复性不同**：解释器缺了只能重下，
  /// 依赖缺了可以就地重建（`pip install -r src/requirements.txt`）。
  deps('deps', '运行依赖', required: true),

  /// llama-server 及其后端 DLL。
  llama('llama', '推理后端', required: true),

  /// 视觉栈模型（检测 / 抹字 / OCR / 字体）。
  modelsVisual('models-visual', '视觉模型', required: true),

  /// 翻译 LLM 权重（Sakura），由 llama-server 加载。
  llm('llm', '翻译模型', required: true),

  /// manga-ocr 权重（`kha-white/manga-ocr-base`），`ocr: mocr` 必需（D-042）。
  ///
  /// 它不是本引擎自带的权重，而是 `manga_ocr` 包在**运行时**从 HuggingFace 拉的。
  /// 放进清单是为了：① 下载可见（不静默联网）② 离线可用。
  modelsMocr('models-mocr', 'OCR 模型', required: true),

  /// 离线英译中模型（nllb），**按需**：不装也能用日译中。
  modelsNllb('models-nllb', '离线英译中', required: false);

  const EnginePart(this.id, this.label, {required this.required});

  /// 稳定 id（进 `.engine.json` 与接口字段，改名等于破坏兼容）。
  final String id;

  /// 界面展示名（中文；ARB 落地前先由调用方映射）。
  final String label;

  /// 缺失时是否阻断「能翻译」。
  final bool required;

  /// 该部件在引擎目录内的相对路径（用 `/` 分隔，调用方负责换成平台分隔符）。
  String get relativePath => switch (this) {
    EnginePart.python => 'python',
    EnginePart.source => 'src',
    EnginePart.deps => 'python',
    EnginePart.llama => 'bin/llama',
    EnginePart.modelsVisual => 'src/models',
    EnginePart.llm => 'llm',
    EnginePart.modelsMocr => '.hf',
    EnginePart.modelsNllb => 'src/models/translators/nllb',
  };

  static EnginePart? byId(String id) {
    for (final p in EnginePart.values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// 把 manifest 的 `dest` 前缀改写成本项目的引擎目录布局（D-027）。
///
/// ## 为什么不改 manifest
/// manifest 是原项目的实测产物（含真实 sha256 与体积），改了会失去可比性，
/// 也让「对上游」变得困难。改写放在下载器这一层。
///
/// ## 改写规则
/// | manifest dest | 落到 | 为什么 |
/// |---|---|---|
/// | `python-3.11/…` | `python/…` | 去掉版本号，版本记在 `.engine.json` |
/// | `src/…` | `src/…` | 一致 |
/// | `bin/llama/llama-b11417/…` | `bin/llama/…` | 去掉版本层，换后端时路径不变 |
/// | `models-store/…` | `models/…` | MIT 的 `model_dir` |
/// | `models/sakura/…` | `llm/…` | Sakura 归 llama-server，不归 MIT |
String mapManifestDest(String dest) {
  final d = dest.replaceAll('\\', '/');

  if (d.startsWith('python-')) {
    // python-3.11.17/… → python/…
    final i = d.indexOf('/');
    return i < 0 ? 'python' : 'python/${d.substring(i + 1)}';
  }
  if (d.startsWith('models-store/')) {
    // 🔴 必须落到 `src/models`：引擎的模型根是 `BASE_PATH/models`，
    // 而 BASE_PATH 就是 `src/`（`utils/generic.py` + `utils/inference.py`）。
    // 命令行**无法**指定模型目录（`--model-dir` 没被子命令继承，见 D-030）。
    return 'src/models/${d.substring('models-store/'.length)}';
  }
  if (d.startsWith('models/sakura/')) {
    return 'llm/${d.substring('models/sakura/'.length)}';
  }
  // HF 缓存：dest 已经是最终相对路径，原样保留。
  if (d.startsWith('.hf/')) return d;
  if (d.startsWith('bin/llama/')) {
    // bin/llama/llama-b11417/llama-server → bin/llama/llama-server
    final rest = d.substring('bin/llama/'.length);
    final i = rest.indexOf('/');
    return i < 0 ? 'bin/llama' : 'bin/llama/${rest.substring(i + 1)}';
  }
  return d;
}

/// manifest 的 `set` → 部件（比用 `dest` 推断更可靠：归档条目的 dest 是缓存路径）。
EnginePart? partOfSet(String set) => switch (set) {
  'python' => EnginePart.python,
  'source' => EnginePart.source,
  'runtime' => EnginePart.llama,
  'visual' => EnginePart.modelsVisual,
  'llm' => EnginePart.llm,
  'mocr' => EnginePart.modelsMocr,
  'translation' => EnginePart.modelsNllb,
  _ => null,
};

/// 把 manifest 的 `extractTo`（解包目标）改写成本项目布局。
///
/// 与 [mapManifestDest] 同口径，但作用于「解到哪个目录」：
/// - `python-3.11` → `python`（去掉版本层）
/// - `bin/llama/llama-b11417` → `bin/llama`（换后端路径不变）
String mapManifestExtractTo(String extractTo) {
  final d = extractTo.replaceAll('\\', '/');
  if (d.startsWith('python-')) return 'python';
  if (d.startsWith('bin/llama/')) return 'bin/llama';
  if (d.startsWith('models-store/')) return 'src/models/${d.substring('models-store/'.length)}';
  if (d.startsWith('models/sakura')) return 'llm';
  return d;
}

/// 判断一个 manifest `dest` 属于哪个部件（用于把下载进度归到部件上）。
EnginePart? partOfManifestDest(String dest) {
  final d = mapManifestDest(dest);
  if (d.startsWith('python/')) {
    // site-packages 里的东西是依赖，不是解释器本体。
    return d.contains('site-packages') ? EnginePart.deps : EnginePart.python;
  }
  // 模型在 `src/models` 下，必须先判模型再判源码，否则都会被算成 source。
  if (d.startsWith('src/models/translators/nllb')) return EnginePart.modelsNllb;
  if (d.startsWith('src/models')) return EnginePart.modelsVisual;
  if (d.startsWith('src/')) return EnginePart.source;
  // HF 缓存布局（`<engine>/.hf/hub/models--…`）：先判，避免与其它前缀混淆。
  if (d.startsWith('.hf/')) return EnginePart.modelsMocr;
  if (d.startsWith('bin/llama')) return EnginePart.llama;
  if (d.startsWith('llm')) return EnginePart.llm;
  return null;
}

/// 超长路径前缀（Windows `MAX_PATH` 规避）。
///
/// 纯字符串函数：不做绝对化、不碰文件系统，便于两端共用与测试。
/// 传入的应是**绝对路径**（本项目所有落点都是绝对的）。
String longPathOf(String path, {required bool isWindows}) {
  if (!isWindows) return path;
  if (path.startsWith(r'\\?\')) return path;
  if (path.length < 240) return path;
  if (path.startsWith(r'\\')) return r'\\?\UNC\' + path.substring(2);
  return r'\\?\' + path;
}

/// llama.cpp 在 Windows / Linux 上可选的后端（D-027 定案：macOS 无此概念）。
///
/// 🔴 **不含 DirectML**：llama.cpp 官方 release 没有该构建，给出一个下不了的后端
/// 只会让用户得到「下载失败」。
enum LlamaBackend {
  /// 自动：按探测结果挑。
  auto('auto', '自动（推荐）', 0),

  /// CPU：任何机器可用，体积最小。
  cpu('cpu', 'CPU', 18),

  /// Vulkan：通用 GPU（NVIDIA / AMD / Intel 核显通吃）。
  vulkan('vulkan', 'Vulkan', 32),

  /// CUDA：NVIDIA 专用，最快，但要额外下 cudart。
  cuda12('cuda-12.4', 'CUDA 12.4', 626);

  const LlamaBackend(this.id, this.label, this.approxMb);

  final String id;
  final String label;

  /// 粗略下载体积（MB），用于在选项上提前告知差异。
  final int approxMb;

  static LlamaBackend? byId(String id) {
    for (final b in LlamaBackend.values) {
      if (b.id == id) return b;
    }
    return null;
  }
}

/// 后端探测结果（由各平台实现填充）。
///
/// 🔴 保留 [reserved] 通道：AMD（ROCm）/ Intel（SYCL / OpenVINO）先不暴露，
/// 但探测接口要能承载，后续加后端不必改协议。
class BackendProbe {
  const BackendProbe({required this.recommended, required this.reason, this.vendor, this.reserved = const {}});

  /// 推荐后端（[LlamaBackend.auto] 时用它）。
  final LlamaBackend recommended;

  /// 推荐理由（给界面显示，如「探测到 NVIDIA RTX 4060」）。
  final String reason;

  /// 显卡厂商：`nvidia` / `amd` / `intel` / null。
  final String? vendor;

  /// 预留：探测到但不对外暴露的后端 id（如 `rocm` / `sycl`）。
  final Map<String, String> reserved;
}
