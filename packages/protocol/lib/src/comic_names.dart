/// 漫画名规范化与目录名安全校验（D-079）。
///
/// 逐条对照 `miao-dock/src-tauri/src/mangasvc/names.rs`（`normalize_comic_name` 9 步）
/// 与 `store/pure.rs`（`is_safe_dir_name`）。
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// 漫画名最大 Unicode 字符数（`MAX_NAME_CHARS = 64`）。
const int maxNameChars = 64;

/// 系统保留名（Windows 设备名，不区分大小写、忽略扩展名）。
const Set<String> _reserved = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM0',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT0',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

/// JS 空白（`is_js_space`）。
bool isJsSpace(String c) {
  final r = c.runes.first;
  return (r >= 0x0009 && r <= 0x000d) ||
      r == 0x0020 ||
      r == 0x00a0 ||
      r == 0x1680 ||
      (r >= 0x2000 && r <= 0x200a) ||
      r == 0x2028 ||
      r == 0x2029 ||
      r == 0x202f ||
      r == 0x205f ||
      r == 0x3000 ||
      r == 0xfeff;
}

/// 规范化结果。
class ComicNameResult {
  const ComicNameResult.ok(this.name) : code = null, message = null;

  const ComicNameResult.fail(this.code, this.message) : name = null;

  final String? name;
  final String? code;
  final String? message;

  bool get isOk => name != null;
}

/// `normalize_comic_name`（9 步，错误码与文案同旧项目）。
ComicNameResult normalizeComicName(String input) {
  // 步 0：拒绝 U+0000
  if (input.contains('\u0000')) {
    return const ComicNameResult.fail('INVALID_COMIC_NAME', '漫画名包含非法控制字符 U+0000');
  }

  // 步 1：NFKC
  var s = unorm.nfkc(input);
  // 步 2：剥控制字符 [\u0000-\u001f\u007f]
  s = _strip(s, (c) {
    final r = c.runes.first;
    return (r >= 0x0000 && r <= 0x001f) || r == 0x007f;
  });
  // 步 3：剥路径分隔符与父目录语义 [/\\:]
  s = _strip(s, (c) => c == '/' || c == '\\' || c == ':');
  // 步 4：剥 Windows 非法字符 [<>"|?*]
  s = _strip(s, (c) => '<>"|?*'.contains(c));

  // 步 5：折叠连续空白为单个半角空格
  final collapsed = StringBuffer();
  var prevSpace = false;
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (isJsSpace(c)) {
      if (!prevSpace) collapsed.write(' ');
      prevSpace = true;
    } else {
      collapsed.write(c);
      prevSpace = false;
    }
  }
  s = collapsed.toString();

  // 步 6：去首尾空白（`^ +` 与 `[. ]+$`）
  s = s.replaceFirst(RegExp(r'^ +'), '');
  s = s.replaceFirst(RegExp(r'[. ]+$'), '');

  // 步 7：长度检查（Unicode 字符数）
  final charCount = s.runes.length;
  if (charCount > maxNameChars) {
    return ComicNameResult.fail('INVALID_COMIC_NAME', '漫画名超过 $maxNameChars 个字符（当前 $charCount）');
  }

  // 步 8：保留名检查（忽略扩展名，不区分大小写）
  final base = s.split('.').first.toUpperCase();
  if (_reserved.contains(base)) {
    return ComicNameResult.fail('INVALID_COMIC_NAME', '「$s」是系统保留名，不能用作漫画名');
  }

  // 步 9：空名检查
  if (s.isEmpty) {
    return ComicNameResult.fail('COMIC_NAME_REQUIRED', '漫画名规范化后为空');
  }
  return ComicNameResult.ok(s);
}

String _strip(String s, bool Function(String c) drop) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (!drop(c)) b.write(c);
  }
  return b.toString();
}

/// `is_safe_dir_name`：目录名单段安全校验（防路径越界）。
bool isSafeDirName(String name) {
  if (name.isEmpty) return false;
  if (name.contains('\u0000') || name.contains('/') || name.contains('\\')) return false;
  for (final c in name.split(RegExp(r'[/\\]'))) {
    if (c == '.' || c == '..') return false;
  }
  return true;
}
