import 'package:flutter_test/flutter_test.dart';
import 'package:szydelkowe_wzory/main.dart';

void main() {
  testWidgets('app starts', (t) async {
    await t.pumpWidget(const App());
    await t.pump();
    expect(find.text('Mój wzór'), findsOneWidget);
  });
}
