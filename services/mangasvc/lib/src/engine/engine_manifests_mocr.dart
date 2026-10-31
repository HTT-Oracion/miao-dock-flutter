//  **mocr 清单**（D-042）—— `kha-white/manga-ocr-base` 的 8 个文件。
//
//  ## 为什么要自己下，而不是让引擎在运行时下
//  引擎里的 `MangaOcr()` 无参调用 → `from_pretrained("kha-white/manga-ocr-base")`
//  → 首次使用会**静默联网**。这违反两条既定原则：下载必须可见、离线可用。
//
//  ## 为什么落点是 HF 缓存布局
//  `from_pretrained` 只认 HuggingFace 缓存结构（`hub/models--<org>--<repo>/snapshots/<rev>/…`
//  + `refs/main`），把文件平铺到任意目录它找不到。所以 dest 直接写成缓存路径，
//  并配合启动时的 `HF_HOME=<engine>/.hf` + `HF_HUB_OFFLINE=1`。
//
//  ## 数据来源（2026-11-01 实测）
//  `https://hf-mirror.com/api/models/kha-white/manga-ocr-base?blobs=true`
//  - 主权重 `pytorch_model.bin` 的 sha256 取自 API 的 `lfs.sha256`；
//  - 其余 7 个小文件 HF **不提供**摘要，为下载后本地实算（由 `shasum -a 256` 得出）。

import 'engine_manifest_entry.dart';

const String _hfBase = 'https://hf-mirror.com/kha-white/manga-ocr-base/resolve/main';
const String _hfFallback = 'https://huggingface.co/kha-white/manga-ocr-base/resolve/main';
const String _snapshot = '.hf/hub/models--kha-white--manga-ocr-base/snapshots/aa6573bd10b0d446cbf622e29c3e084914df9741';

const List<EngineManifestEntry> kMocrManifest = [
  EngineManifestEntry(
    id: 'mocr_config',
    set: 'mocr',
    url: '$_hfBase/config.json',
    sources: ['$_hfFallback/config.json'],
    dest: '$_snapshot/config.json',
    sha256: '8c0e395de8fa699daaac21aee33a4ba9bd1309cfbff03147813d2a025f39f349',
    sizeBytes: 77546,
  ),
  EngineManifestEntry(
    id: 'mocr_weights',
    set: 'mocr',
    url: '$_hfBase/pytorch_model.bin',
    sources: ['$_hfFallback/pytorch_model.bin'],
    dest: '$_snapshot/pytorch_model.bin',
    sha256: 'c63e0bb5b3ff798c5991de18a8e0956c7ee6d1563aca6729029815eda6f5c2eb',
    sizeBytes: 444135475,
  ),
  EngineManifestEntry(
    id: 'mocr_preprocessor',
    set: 'mocr',
    url: '$_hfBase/preprocessor_config.json',
    sources: ['$_hfFallback/preprocessor_config.json'],
    dest: '$_snapshot/preprocessor_config.json',
    sha256: 'af4eb4d79cf61b47010fc0bc9352ee967579c417423b4917188d809b7e048948',
    sizeBytes: 228,
  ),
  EngineManifestEntry(
    id: 'mocr_tokenizer_config',
    set: 'mocr',
    url: '$_hfBase/tokenizer_config.json',
    sources: ['$_hfFallback/tokenizer_config.json'],
    dest: '$_snapshot/tokenizer_config.json',
    sha256: 'd775ad1deac162dc56b84e9b8638f95ed8a1f263d0f56f4f40834e26e205e266',
    sizeBytes: 486,
  ),
  EngineManifestEntry(
    id: 'mocr_special_tokens',
    set: 'mocr',
    url: '$_hfBase/special_tokens_map.json',
    sources: ['$_hfFallback/special_tokens_map.json'],
    dest: '$_snapshot/special_tokens_map.json',
    sha256: '303df45a03609e4ead04bc3dc1536d0ab19b5358db685b6f3da123d05ec200e3',
    sizeBytes: 112,
  ),
  EngineManifestEntry(
    id: 'mocr_vocab',
    set: 'mocr',
    url: '$_hfBase/vocab.txt',
    sources: ['$_hfFallback/vocab.txt'],
    dest: '$_snapshot/vocab.txt',
    sha256: '344fbb6b8bf18c57839e924e2c9365434697e0227fac00b88bb4899b78aa594d',
    sizeBytes: 24072,
  ),
  EngineManifestEntry(
    id: 'mocr_gitattributes',
    set: 'mocr',
    url: '$_hfBase/.gitattributes',
    sources: ['$_hfFallback/.gitattributes'],
    dest: '$_snapshot/.gitattributes',
    sha256: 'fa057bb09b78fe6d33af5a01440be5e8c881cd8055de35ee5588ea759cf57bfc',
    sizeBytes: 1175,
  ),
  EngineManifestEntry(
    id: 'mocr_readme',
    set: 'mocr',
    url: '$_hfBase/README.md',
    sources: ['$_hfFallback/README.md'],
    dest: '$_snapshot/README.md',
    sha256: '32f413afcc4295151e77d25202c5c5d81ef621b46f947da1c3bde13256dc0d5f',
    sizeBytes: 705,
  ),
];
