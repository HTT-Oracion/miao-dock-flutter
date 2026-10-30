import 'package:flutter/material.dart';

/// 桌面歌词窗根组件；置顶、无边框等窗口特性由 core/window 接入（见 AGENTS.md §2）。
class LyricsApp extends StatelessWidget {
  const LyricsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('桌面歌词'))),
    );
  }
}
