# 引擎下载清单（C6e 前置盘点）

> 事实源：`miao-dock/engine/{runtime,models,wheels}.manifest.json`（原项目实测产物，含真实 sha256 与体积）。
> 本文只是**盘点**，未开始实现。基准日 2026-10-31。

## 一、镜像策略：HuggingFace 镜像优先

- **规则**：HF 相关条目**先走镜像**（`hf-mirror.com`），官方 `huggingface.co` 仅作兜底。
- **实测**（本机 2026-10-31）：

  | 域名 | 结果 |
  |---|---|
  | `huggingface.co` | **000（不通）** |
  | `hf-mirror.com` | 200 |
  | `github.com` / `codeload.github.com` | 200，且支持 `Range`（206） |
  | `mirror.nju.edu.cn` | 200（manifest 里 python 运行时用的就是它） |
  | `download.pytorch.org` | 403（pypi 正常，torch 可走 pypi） |

- **现状**：manifest 的 `sources` 字段已存在，但每条**只有镜像一个地址**，没有兜底。
  按本策略应补成 `[镜像, 官方]` 两级，由下载器按序尝试。
- **为什么镜像优先不是「妥协」**：官方站在本机**完全不可达**，不优先就装不上。

## 二、macOS arm64 下载清单（本机目标平台）

### 必装（10 项，4.74 GB）

| set | id | 体积 | 落点 | 解包到 |
|---|---|---|---|---|
| python | `python_runtime_darwin_arm64` | 25.8 MB | `.download-cache/…aarch64-apple-darwin.tar.gz` | `python-3.11` |
| source | `engine_source` | 53.5 MB | `.download-cache/manga-translator-441d07c5.tar.gz` | `src` |
| visual | `detect_default` | 294.1 MB | `models-store/detection/detect-20241225.ckpt` | — |
| visual | `inpainter_lama_large` | 195.1 MB | `models-store/inpainting/lama_large_512px.ckpt` | — |
| visual | `ocr_48px` | 194.8 MB | `models-store/ocr/ocr_ar_48px.ckpt` | — |
| visual | `ocr_alphabet_v7` | 0.2 MB | `models-store/ocr/alphabet-all-v7.txt` | — |
| visual | `font_zen_maru_gothic` | 3.7 MB | `models-store/fonts/ZenMaruGothic-Regular.ttf` | — |
| visual | `font_lxgw_wenkai_gb` | 24.6 MB | `models-store/fonts/LXGWWenKaiGB-Medium.ttf` | — |
| llm | `llm_galtransl_7b_v37_iq4xs` | **4053.4 MB** | `models/sakura/Sakura-Galtransl-7B-v3.7-IQ4_XS.gguf` | — |
| runtime | `llama_cpp_macos_arm64` | 11.4 MB | `bin/llama-b11417-macos-arm64.tar.gz` | `bin/llama/llama-b11417` |

**体积分布**：LLM 占 3.96 GB（83%），视觉栈 0.70 GB，源码+Python 0.08 GB。

### 可选：离线英译中（`nllb` 8 项，2.31 GB）

`nllb_600m_*`（`pytorch_model` 单项 2346.5 MB）。
**只有需要「英译中且完全离线」时才装**；日译中走 Sakura，不依赖它。
装上后总量 → **7.05 GB**。

## 三、pip 依赖（**不在上面任何清单里**）

引擎跑起来还差一层：`src/requirements.txt` 的第三方包，由 pip 在装配阶段安装。

```
torch  torchvision  numpy==1.26.4  opencv-python  scikit-image  shapely
pyclipper  einops  kornia  ImageHash  transformers  sentencepiece
freetype-py  aiohttp  requests  cryptography  huggingface_hub
networkx  torch-summary  tqdm  deepl  groq  py3langid==0.2.2
editdistance  backports.cached-property
```

- **重的是 `torch` / `torchvision`**：macOS arm64 为 MPS 构建（数百 MB 量级）；
  **Windows CUDA 版则数 GB**。精确值以 pip 解析为准，不在这里猜。
- **`pydensecrf` 是单独通道**（`wheels.manifest.json`）：
  - 目前**只有 `win32-x64` 预编译 wheel**；
  - **macOS 没有 wheel** → 回退源码编译 → **需要本机装 Xcode 命令行工具**。
    这是 macOS「零配置」目前唯一的硬缺口。

## 四、平台覆盖缺口（重要）

| 平台 | 缺口 |
|---|---|
| `darwin-x64`（Intel Mac） | **没有 llama 二进制条目**（只有 `macos-arm64`）→ LLM 不可用 |
| `win32-arm64` | **没有 llama 二进制条目** → LLM 不可用 |
| `win32-x64`（无 NVIDIA 卡） | **没有 CPU / DirectML 版 llama** → 只有 CUDA 版，无卡机器不可用 |
| Linux | **manifest 完全没有 Linux 条目**（python / llama / 平台键都没有） |

> 换句话说：**当前 manifest 只完整支持 Apple Silicon 与 Windows+NVIDIA 两种机器**。
> 这与 AGENTS §2「桌面端含 Linux」的表述有落差，需要单独立项。

## 五、Windows 与 macOS 的差异

### 1. 体积差一个数量级

| 项 | macOS arm64 | Windows x64 |
|---|---|---|
| Python 运行时 | 25.8 MB | **46.0 MB** |
| llama 运行时 | **11.4 MB**（自带全部依赖） | **252.2 MB + cudart 373.3 MB**（两份，必须都解到同一目录） |
| 必装合计（不含 pip / nllb） | **4.74 GB** | **5.36 GB** |
| 加 nllb | 7.05 GB | 7.67 GB |
| 加 pip（torch CUDA 数 GB） | 数百 MB 量级 | **约 +2.5 GB** |

- Windows 的 CUDA 运行时**拆成两个包**（`llama-…-cuda-12.4-x64.zip` 与 `cudart-…zip`），
  少解一个就会出现「llama-server 启动即报缺 DLL」。macOS 无此问题。

### 2. 归档格式不同

| | macOS | Windows |
|---|---|---|
| Python / 源码 | `.tar.gz` | `.tar.gz`（相同） |
| llama 运行时 | `.tar.gz` | **`.zip`**（CUDA 两个包都是 zip） |

我们的 `runtime_setup` 走**系统 tar**：Windows 10 1803+ 的 `bsdtar` 能解 zip，
但**必须实测**——GNU tar 不能，一旦目标机是旧环境或替换过的 tar 会静默失败。

### 3. 可执行位与符号链接

- macOS：python 解释器必须保留 `0755`；venv 里可能有 symlink。
  已验证：真实 `cpython-3.11.10 install_only` 解出后 `python3` 权限 `755`、能跑。
- Windows：**没有可执行位概念**，`python.exe` 靠扩展名识别。
  我们 `runtime_setup` 里对权限的处理在 Windows 上是无害空转。

### 4. 解释器路径与 venv 布局

| | macOS | Windows |
|---|---|---|
| venv 内解释器 | `venv/bin/python` | `venv/Scripts/python.exe` |
| 引擎入口 | `bin/python` | `python.exe` |

`paths.dart` 的 `enginePythonPath()` 已按 `Platform.isWindows` 分叉，覆盖到了。

### 5. 进程终止语义

- `ServiceSupervisor.stop()` 用 `SIGTERM` → 宽限期 → `SIGKILL`。
- **Windows 没有真正的 POSIX 信号**：Dart 的 `ProcessSignal.sigterm` 在 Windows 上
  实际是直接终止（不走「优雅退出」）。宽限期逻辑在 Windows 上**基本不生效**。
- llama-server 在 Windows 上被强杀后可能留下显存未释放的窗口；需实测。

### 6. 长路径

- Windows `MAX_PATH` = 260。
- 现有落点里最长的一条是 nllb 的 blob：
  `<数据根>/manga/state/models-state/translators/nllb/models--facebook--nllb-200-distilled-600M/blobs/<64位sha>` ≈ **150+ 字符**，
  叠加 `%LOCALAPPDATA%` 前缀后**逼近上限**。macOS 无此限制。
- 需要：Windows 上启用长路径支持，或把 blob 目录名缩短。

### 7. 代码签名与沙盒

| | macOS | Windows |
|---|---|---|
| 沙盒 | 已关闭（D-022，否则拉不起子进程） | 无对应概念 |
| 签名 | 额外二进制需在签名前放入包内（D-024） | 无此步骤 |
| 分发阻碍 | 无（不上架 MAS） | SmartScreen 首次运行告警 |

## 六、与现有设计的落点冲突（需要定案）

manifest 的 `dest` 用的是原项目布局，与 D-015/D-016 定下的新布局**不完全一致**：

| manifest dest 前缀 | 原项目含义 | 本项目当前设计 | 冲突 |
|---|---|---|---|
| `python-3.11/`、`src/`、`bin/llama/` | 运行时根下 | `<appData>/MiaoDock/manga/runtimes/` | 一致 ✅ |
| `models-store/` | 运行时根下 | `<state>/models-state/`（D-016 刻意偏离） | **需映射** ⚠️ |
| `models/sakura/` | 运行时根下 | 未定 | **需定案** ⚠️ |

**问题**：manifest 自己就有**两个模型根**（`models-store/` 与 `models/`）。
D-016 把模型挪到 `state/models-state` 时只考虑了 `models-store`。

**建议**（待确认）：把两个前缀统一映射到 `<state>/models-state/` 下
（`models-store/x` → `models-state/x`，`models/sakura/x` → `models-state/sakura/x`），
并在下载器里做**前缀改写表**，而不是改 manifest（manifest 是原项目产物，改动会失去可比性）。

## 七、验证素材

`test-manga/`（已加 `.gitignore`，不入库）：2 张 **800×1142 JPEG**，512 KB。

- 尺寸贴近真实漫画页，足够跑「检测 → OCR → 翻译 → 抹字 → 排版」全链路；
- 只有 2 张，够冒烟不够做批量/显存压测。

## 八、待你定案的问题

1. **模型落点**：`models-store/` 与 `models/sakura/` 是否都归到 `<state>/models-state/`（见 §六）？
2. **nllb 是否默认装**：日译中不需要它，但它决定总量是 4.74 GB 还是 7.05 GB。
3. **Linux 平台**：manifest 缺失整块，是本期不做，还是先补条目？
4. **Windows 无 N 卡机器**：要不要引入 CPU / DirectML 版 llama（需新增清单条目与体积评估）？
5. **pip 依赖是否走镜像**：`torch` 走 pypi 官方源还是国内镜像，直接影响安装成功率。
