import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/app.dart';

void main() {
  testWidgets('app opens and shows its name', (tester) async {
    await tester.pumpWidget(const GroveApp());
    expect(find.text('Grove'), findsOneWidget);
  });
}
