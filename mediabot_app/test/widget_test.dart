import 'package:flutter_test/flutter_test.dart';
import 'package:mediabot/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MediaBotApp());
    expect(find.text('MediaBot'), findsOneWidget);
  });
}
