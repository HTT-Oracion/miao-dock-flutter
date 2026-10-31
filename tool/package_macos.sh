#!/bin/bash
# P0-D4：把 mangasvc 编成自包含可执行文件，并放进 .app 的 Contents/MacOS/。
#
# 用法：
#   tool/package_macos.sh              # 只编译到 build/mangasvc
#   tool/package_macos.sh <目标目录>    # 编译后复制到目标目录（Xcode 构建阶段用）
#
# 为什么脚本要自己找 dart：Xcode 构建阶段的 PATH 里没有 Flutter SDK，
# 只有 FLUTTER_ROOT 可用。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-}"
OUT="$ROOT/build/mangasvc"
SRC="$ROOT/services/mangasvc/bin/mangasvc.dart"

# ── 找 dart ────────────────────────────────────────────────────────────
DART=""
if [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" ]; then
  DART="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
elif command -v dart >/dev/null 2>&1; then
  DART="$(command -v dart)"
fi
if [ -z "$DART" ]; then
  echo "error: 找不到 dart（需要 FLUTTER_ROOT 或 PATH 中的 dart）" >&2
  exit 1
fi

# ── 增量：源码没变就不重编 ────────────────────────────────────────────
needs_build=1
if [ -x "$OUT" ]; then
  stale="$(find "$ROOT/services/mangasvc" "$ROOT/packages/protocol" "$ROOT/services/mangasvc/pubspec.yaml" \
           -newer "$OUT" \( -name '*.dart' -o -name 'pubspec.yaml' \) -print -quit 2>/dev/null || true)"
  if [ -z "$stale" ]; then
    needs_build=0
  fi
fi

if [ "$needs_build" -eq 1 ]; then
  mkdir -p "$ROOT/build"
  echo "▸ 编译 mangasvc → $OUT"
  "$DART" compile exe "$SRC" -o "$OUT" --verbosity=error
  chmod +x "$OUT"
else
  echo "▸ mangasvc 已是最新，跳过编译"
fi

# ── 复制到 .app ────────────────────────────────────────────────────────
if [ -n "$DEST" ]; then
  # 目标不存在就直接失败：静默跳过会让打包出一个跑不起来的 App。
  if [ ! -d "$DEST" ]; then
    echo "error: 目标目录不存在：$DEST" >&2
    exit 1
  fi
  cp -f "$OUT" "$DEST/mangasvc"
  chmod +x "$DEST/mangasvc"
  echo "▸ 已放入 $DEST/mangasvc"
fi
