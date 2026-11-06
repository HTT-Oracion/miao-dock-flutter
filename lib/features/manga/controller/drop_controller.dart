import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 服务端每批 20 张（设计稿 H Note 05/06 的投放规格）。
const int kServerBatchSize = 20;

const _allowedExts = {'png', 'jpg', 'jpeg', 'webp'};

/// 是否为可投放的图片扩展名。
bool isAllowedImage(String path) => _allowedExts.contains(path.split('.').last.toLowerCase());

/// 投放屏状态：漫画名 + 待投放文件（相对路径或浏览器文件名）。
final dropController = NotifierProvider<DropNotifier, DropState>(DropNotifier.new);

class DropState {
  const DropState({this.name = '', this.files = const [], this.receipt});

  final String name;
  final List<String> files;

  /// 提交成功回执（重设计稿回执卡）：有值时投放卡上方渲染回执。
  /// 只存 count / position——落盘路径要等服务端回执，当前契约没有就不猜。
  final ({int count, int position})? receipt;

  DropState copyWith({String? name, List<String>? files, ({int count, int position})? receipt}) =>
      DropState(name: name ?? this.name, files: files ?? this.files, receipt: receipt ?? this.receipt);

  /// 文件按序号所属批次（1 起，每批 20 张）。
  int batchOf(int index) => index ~/ kServerBatchSize + 1;

  int get batchCount => files.isEmpty ? 0 : (files.length / kServerBatchSize).ceil();
}

class DropNotifier extends Notifier<DropState> {
  @override
  DropState build() => const DropState();

  void setName(String name) => state = state.copyWith(name: name);

  /// 追加文件：过滤扩展名、去重、排序（序号连续即分批，H Note 06）。
  void addFiles(Iterable<String> paths) {
    final merged = [
      ...state.files,
      ...paths.where((p) => _allowedExts.contains(p.split('.').last.toLowerCase()) && !state.files.contains(p)),
    ]..sort();
    state = state.copyWith(files: merged);
  }

  void removeAt(int index) {
    final files = [...state.files]..removeAt(index);
    state = state.copyWith(files: files);
  }

  void clear() => state = DropState(name: state.name);

  /// 提交成功后记录回执（清单已清空，名字保留在输入框供继续投下一批）。
  void setReceipt({required int count, required int position}) =>
      state = DropState(name: state.name, receipt: (count: count, position: position));
}

/// 文件路径取展示名（桌面为完整路径，浏览器为文件名）。
String dropDisplayName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.split('/').last;
}
