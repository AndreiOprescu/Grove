import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/app.dart';
import 'package:grove/ui/shell/root_view.dart';

void main() {
  testWidgets('app opens and shows the shell', (tester) async {
    await tester.pumpWidget(const GroveApp());
    expect(find.byType(RootView), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    // take the app down so its moving background stops
    await tester.pumpWidget(const SizedBox());
  });
}
