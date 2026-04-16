import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meetmid_flutter/app.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MeetMidApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('MeetMid'), findsOneWidget);
  });
}
