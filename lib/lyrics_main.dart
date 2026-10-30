import 'app/bootstrap.dart';
import 'features/lyrics/ui/lyrics_app.dart';

/// 桌面歌词独立窗入口（第二 Flutter 入口，见 AGENTS.md §2）。
Future<void> main() => bootstrap(const LyricsApp());
