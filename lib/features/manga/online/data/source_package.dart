import 'dart:typed_data';

import '../domain/source_manifest.dart';

/// 完整源包（清单 + JS + 可选图标）。本地文件导入和远程链接安装共用。
class SourcePackageData {
  const SourcePackageData({required this.manifest, required this.js, this.icon, this.sourceUrl, this.libraryId});

  final SourceManifest manifest;
  final String js;
  final Uint8List? icon;
  final String? sourceUrl;
  final String? libraryId;
}
