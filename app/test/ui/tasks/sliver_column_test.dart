import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/tasks/sliver_column.dart';

/// Writes its name in [log] each time it is painted.
class _Mark extends CustomPainter {
  _Mark(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  void paint(Canvas canvas, Size size) => log.add(name);

  @override
  bool shouldRepaint(_Mark old) => true;
}

void main() {
  Widget part(String name, List<String> log, {double height = 40}) =>
      SliverToBoxAdapter(
        child: CustomPaint(
          key: ValueKey(name),
          painter: _Mark(name, log),
          size: Size.fromHeight(height),
        ),
      );

  Future<void> pump(WidgetTester tester, Widget sliver) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(slivers: [sliver]),
    ),
  );

  testWidgets('the parts are painted from the first to the last, as in a '
      'Column', (tester) async {
    final log = <String>[];
    await pump(
      tester,
      SliverColumn(
        slivers: [
          part('heading', log),
          SliverColumn(slivers: [part('row 1', log), part('row 2', log)]),
          part('end', log),
        ],
      ),
    );
    expect(log, ['heading', 'row 1', 'row 2', 'end']);
  });

  testWidgets('the parts stand one under the other, and a part out of view '
      'is not painted', (tester) async {
    final log = <String>[];
    await pump(
      tester,
      SliverColumn(
        slivers: [
          part('a', log, height: 500),
          part('b', log, height: 500),
          part('c', log, height: 500),
        ],
      ),
    );
    // The test window is 600 points high.
    expect(log, ['a', 'b']);
    expect(tester.getRect(find.byKey(const ValueKey('a'))).top, 0);
    expect(tester.getRect(find.byKey(const ValueKey('b'))).top, 500);
  });
}
