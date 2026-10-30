import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:miao_dock_flutter/app/app.dart';

void main() {
  testWidgets('App 能启动并挂载 MaterialApp', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MiaoDockApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
