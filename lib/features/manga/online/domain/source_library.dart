// 源仓库模型的**唯一实现**已上移到 shared：漫画源与音乐源共用同一套
// 仓库语义（URL → index.json → 若可安装的源）。这里只做 re-export，
// 保持既有 import 路径不变。
export '../../../../shared/domain/source_library.dart';
