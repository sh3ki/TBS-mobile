import 'package:flutter_test/flutter_test.dart';

import 'package:tbs_mobile/main.dart';

void main() {
  testWidgets('App boots and shows TBS splash text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TbsApp());
    expect(find.text('TBS'), findsOneWidget);
  });
}
