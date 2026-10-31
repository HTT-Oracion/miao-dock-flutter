/// 翻译配置的唯一来源（D-041）。
///
/// 与 `miao-dock/runtimes/manga-translator/sakura-chs.config.json` 对齐，并按用户定案调整：
/// - `ocr` 用 **`mocr`** 而不是 `48px`（用户定案：mocr 首选，不再要 48px 配置）；
/// - `use_mocr_merge` 显式 **false**（实测开启会把整句排成巨型字并截断，排版回归未解决）。
///
/// ## 为什么必须显式写全
/// 引擎默认值是 `sugoi` + `ENG`：不传配置就会**下好 Sakura 却不用它**，而且译文是英文。
/// 这类错误不会报错，只会悄悄给出错误结果 —— 所以每一项都写死，不依赖默认值。
const Map<String, dynamic> defaultTranslateConfig = {
  'translator': {'translator': 'sakura', 'target_lang': 'CHS'},
  'detector': {'detector': 'default'},
  'inpainter': {'inpainter': 'lama_large'},
  'ocr': {
    'ocr': 'mocr',
    // 用户定案：不开。开了译文更完整，但排版会爆。
    'use_mocr_merge': false,
  },
};

/// mocr 权重的 HuggingFace 仓库（`manga_ocr` 包内置的默认值）。
const String mocrRepo = 'kha-white/manga-ocr-base';

/// 该仓库的 commit sha（实测取到，用于 HF 缓存的 snapshots 目录名）。
const String mocrRepoRevision = 'aa6573bd10b0d446cbf622e29c3e084914df9741';
