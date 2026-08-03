import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ifarmer_grain_collector/main.dart';

void main() {
  testWidgets('Home screen shows Paddy and Maize options', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    expect(find.text('Paddy'), findsOneWidget);
    expect(find.text('Maize'), findsOneWidget);
  });
}
