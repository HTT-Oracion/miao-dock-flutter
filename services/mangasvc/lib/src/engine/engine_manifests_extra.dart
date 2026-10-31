//  **补充清单**（D-027）—— 原项目 manifest 没有、但本项目需要的条目。
//
//  ## 为什么单独一个文件
//  `engine_manifests.dart` 是从原项目清单**生成**的，手改会被下次生成覆盖。
//  这里放「我们新增的」，语义清楚、可审计。
//
//  ## 数据来源与时效
//  llama.cpp `b11417` 与 python-build-standalone `20261003` 的 GitHub release API，
//  抓取日期 **2026-11-01**；`sha256` 取自 API 的 `digest` 字段（真实值，非臆造）。
//  升级版本时应重跑抓取并整批替换。
//
//  ## 为什么没有 DirectML
//  llama.cpp 官方 release 不存在该构建。给一个下不了的后端，用户只会得到「下载失败」。

import 'engine_manifest_entry.dart';

const String _llamaBase = 'https://github.com/ggml-org/llama.cpp/releases/download/b11417';
const String _pbsBase = 'https://github.com/astral-sh/python-build-standalone/releases/download/20261003';

/// 推理后端（llama-server）—— 按平台与后端分化。
///
/// `extractTo` 统一为 `bin/llama`（不保留版本层）：
/// 换后端时路径不变，上层启动参数无需跟着改。
const List<EngineManifestEntry> kExtraRuntimeManifest = [
  // ── macOS x64（Intel）：原项目只给了 arm64，Intel Mac 此前无 llm 可用 ──
  EngineManifestEntry(
    id: 'llama_cpp_macos_x64',
    set: 'runtime',
    platform: 'darwin-x64',
    url: '$_llamaBase/llama-b11417-bin-macos-x64.tar.gz',
    dest: '.download-cache/llama-b11417-macos-x64.tar.gz',
    sha256: '728116975fcc55a9da306bb507b26ba60b3a5e802cef451b500c5df42c06bb4f',
    sizeBytes: 11481791,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),

  // ── Windows x64：CPU / Vulkan（原项目只有 CUDA）──
  EngineManifestEntry(
    id: 'llama_cpp_win_cpu_x64',
    set: 'runtime',
    platform: 'win32-x64',
    url: '$_llamaBase/llama-b11417-bin-win-cpu-x64.zip',
    dest: '.download-cache/llama-b11417-win-cpu-x64.zip',
    sha256: '3b2519bcfd83f2d8d3082e545470b93ab18bb32742daaff60eea55216540d537',
    sizeBytes: 19390916,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),
  EngineManifestEntry(
    id: 'llama_cpp_win_vulkan_x64',
    set: 'runtime',
    platform: 'win32-x64',
    url: '$_llamaBase/llama-b11417-bin-win-vulkan-x64.zip',
    dest: '.download-cache/llama-b11417-win-vulkan-x64.zip',
    sha256: 'e125522da4d45e7c2d731215ffde610122c9102b0720a229460e9fcc95bac6b8',
    sizeBytes: 33313856,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),

  // ── Windows arm64 ──
  EngineManifestEntry(
    id: 'llama_cpp_win_cpu_arm64',
    set: 'runtime',
    platform: 'win32-arm64',
    url: '$_llamaBase/llama-b11417-bin-win-cpu-arm64.zip',
    dest: '.download-cache/llama-b11417-win-cpu-arm64.zip',
    sha256: 'c54b1c5c4d9289bdd7404c4cd27d7089adf1b5e943079942b3bcd8ed112de49b',
    sizeBytes: 12221449,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),
  EngineManifestEntry(
    id: 'llama_cpp_win_vulkan_arm64',
    set: 'runtime',
    platform: 'win32-arm64',
    url: '$_llamaBase/llama-b11417-bin-win-vulkan-arm64.zip',
    dest: '.download-cache/llama-b11417-win-vulkan-arm64.zip',
    sha256: '6e92f9594689ed81aa3f4d4ca8cd64d5496e8b33eefdcbec39679cbc4a07c6cf',
    sizeBytes: 25866457,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),

  // ── Linux（本期不做功能，清单先补齐；D-027 定案）──
  EngineManifestEntry(
    id: 'llama_cpp_linux_x64',
    set: 'runtime',
    platform: 'linux-x64',
    url: '$_llamaBase/llama-b11417-bin-ubuntu-x64.tar.gz',
    dest: '.download-cache/llama-b11417-ubuntu-x64.tar.gz',
    sha256: 'f2808f7f34382652f3db0606e1261c3e09f8f731df6a6dfefa2089c5955940ae',
    sizeBytes: 17679205,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),
  EngineManifestEntry(
    id: 'llama_cpp_linux_vulkan_x64',
    set: 'runtime',
    platform: 'linux-x64',
    url: '$_llamaBase/llama-b11417-bin-ubuntu-vulkan-x64.tar.gz',
    dest: '.download-cache/llama-b11417-ubuntu-vulkan-x64.tar.gz',
    sha256: 'b63925a1a4b3a17476808290c9772fb81daad59929f12942ac0f9822a41ebd05',
    sizeBytes: 31621448,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),
  EngineManifestEntry(
    id: 'llama_cpp_linux_arm64',
    set: 'runtime',
    platform: 'linux-arm64',
    url: '$_llamaBase/llama-b11417-bin-ubuntu-arm64.tar.gz',
    dest: '.download-cache/llama-b11417-ubuntu-arm64.tar.gz',
    sha256: 'e08253af86d32735139f6385a1f8976a27fffa4d1cee9c706f065860581fada9',
    sizeBytes: 13673942,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),
  EngineManifestEntry(
    id: 'llama_cpp_linux_vulkan_arm64',
    set: 'runtime',
    platform: 'linux-arm64',
    url: '$_llamaBase/llama-b11417-bin-ubuntu-vulkan-arm64.tar.gz',
    dest: '.download-cache/llama-b11417-ubuntu-vulkan-arm64.tar.gz',
    sha256: '3ad757ae38e7c7be2adff21cbdbd3262b2566d347f92c749cab467905cc30108',
    sizeBytes: 24834883,
    extractTo: 'bin/llama',
    extractStrip: 1,
    stage: 1,
  ),

  // ── Linux Python（原项目只给了 win / darwin）──
  EngineManifestEntry(
    id: 'python_runtime_linux_x64',
    set: 'python',
    platform: 'linux-x64',
    url: '$_pbsBase/cpython-3.11.17%2B20261003-x86_64-unknown-linux-gnu-install_only.tar.gz',
    dest: '.download-cache/cpython-3.11.17-x86_64-unknown-linux-gnu.tar.gz',
    sha256: 'c624af93ad62a596806bbd2404e1fb80744a407ca7279854445ede16d93858b8',
    sizeBytes: 48919491,
    extractTo: 'python',
    extractStrip: 1,
    stage: 1,
  ),
  EngineManifestEntry(
    id: 'python_runtime_linux_arm64',
    set: 'python',
    platform: 'linux-arm64',
    url: '$_pbsBase/cpython-3.11.17%2B20261003-aarch64-unknown-linux-gnu-install_only.tar.gz',
    dest: '.download-cache/cpython-3.11.17-aarch64-unknown-linux-gnu.tar.gz',
    sha256: '2238f0556d3a9777d42261b1e4d7b9834d56f111d3dd879a0647c27c824cc31d',
    sizeBytes: 48957743,
    extractTo: 'python',
    extractStrip: 1,
    stage: 1,
  ),
];
