// Ports of the Swift tests for the small rules of the planner:
// PlannerRulesTests (sticky notes), the PlannerLayoutRules tests of
// TaskDescriptionTests, the rows and labels of PlannerSubtaskTests,
// InlineTitleRulesTests and the Workload tests of TaskLookTests.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/inline_title_field.dart';
import 'package:grove/ui/planner/planner_geometry.dart';
import 'package:grove/ui/planner/sticky_rules.dart';
import 'package:grove/ui/planner/workload.dart';

void main() {
  group('PlannerGeometry', () {
    test('minutes and points', () {
      const geo = PlannerGeometry(hourHeight: 64);
      expect(geo.totalHeight, 64 * 24);
      expect(geo.y(90), 96);
      expect(geo.minute(96), 90);
      expect(geo.minute(97), 91);
      // 22 points at 64 points an hour is 21 minutes, rounded up.
      expect(geo.minDrawnMinutes, 21);
      expect(geo.tightMinutes, 30);
    });

    test('zoom stays in its range', () {
      expect(PlannerGeometry.clampHour(10), 36);
      expect(PlannerGeometry.clampHour(500), 160);
      expect(PlannerGeometry.clampHour(80), 80);
    });

    test('day columns start on whole points and fill the grid', () {
      // 7 days in 1016 points: one day is 145.14 points wide.
      const dayWidth = 1016 / 7;
      var sum = 0.0;
      for (var i = 0; i < 7; i++) {
        final left = PlannerGeometry.dayOffset(dayWidth, i);
        final width = PlannerGeometry.dayWidthAt(dayWidth, i);
        expect(left, left.roundToDouble());
        expect(left, sum);
        expect(width, anyOf(145, 146));
        sum += width;
      }
      expect(PlannerGeometry.dayOffset(dayWidth, 0), 0);
      expect(sum, 1016);
    });
  });

  group('StickyRules', () {
    test('a sticky note keeps its colour and its tilt', () {
      expect(StickyRules.stableHash('abc'), 440920331);
      expect(StickyRules.colorIndex('abc'), StickyRules.colorIndex('abc'));
      expect(StickyRules.tilt('abc'), StickyRules.tilt('abc'));
    });

    test('notes use three colours and a small tilt', () {
      final ids = [for (var i = 0; i < 40; i++) 'id-$i'];
      expect({for (final id in ids) StickyRules.colorIndex(id)}, {0, 1, 2});
      for (final id in ids) {
        expect(StickyRules.tilt(id).abs() <= 1.5, isTrue);
      }
    });

    test('the strip is as tall as its notes, up to a limit', () {
      expect(StickyRules.stripHeight(70), 70);
      expect(StickyRules.stripHeight(600), StickyRules.maxHeight);
      expect(StickyRules.stripHeight(0), StickyRules.foldedHeight);
    });

    test('a day shows as many note columns as fit', () {
      expect(StickyRules.columns(60), 1);
      expect(StickyRules.columns(122), 1);
      expect(StickyRules.columns(238), 2);
      expect(StickyRules.columns(1000), 8);
    });
  });

  group('PlannerLayoutRules', () {
    test('a block gives lines to the title and to the summary', () {
      expect(PlannerLayoutRules.blockTextLines(height: 64, hasSummary: true), (
        title: 2,
        summary: 1,
      ));
      expect(PlannerLayoutRules.blockTextLines(height: 64, hasSummary: false), (
        title: 3,
        summary: 0,
      ));
      expect(PlannerLayoutRules.blockTextLines(height: 36, hasSummary: true), (
        title: 1,
        summary: 0,
      ));
      final tall = PlannerLayoutRules.blockTextLines(
        height: 320,
        hasSummary: true,
      );
      expect(tall.title, 2);
      expect(tall.summary > 5, isTrue);
    });

    test('a block with a summary keeps more minutes clear', () {
      int tight(double height, bool summary) => PlannerLayoutRules.tightMinutes(
        hourHeight: 110,
        blockHeight: height,
        hasSummary: summary,
      );
      expect(tight(220, false), 18);
      expect(tight(220, true), 26);
      expect(tight(40, true), 18);
    });

    test('the text clearance follows the text and stops at half a column', () {
      final long = PlannerLayoutRules.textClearance(
        title: 'Plan',
        summary: 'a' * 32,
        columnWidth: 540,
      );
      expect(long > 150 && long <= 270, isTrue);
      expect(
        PlannerLayoutRules.textClearance(
          title: 'Plan',
          summary: 'a' * 32,
          columnWidth: 100,
        ),
        50,
      );
      expect(
        PlannerLayoutRules.textClearance(
              title: 'Plan',
              summary: 'Hi',
              columnWidth: 540,
            ) <
            80,
        isTrue,
      );
    });
  });

  group('rows of a block with subtasks', () {
    BlockRows rows(double height, bool summary, int count) =>
        PlannerLayoutRules.blockRows(
          height: height,
          hasSummary: summary,
          subtaskCount: count,
        );

    test('no subtasks keeps the old lines', () {
      for (final h in [22.0, 36.0, 64.0, 320.0]) {
        for (final summary in [false, true]) {
          final old = PlannerLayoutRules.blockTextLines(
            height: h,
            hasSummary: summary,
          );
          expect(
            rows(h, summary, 0),
            BlockRows(title: old.title, summary: old.summary),
          );
        }
      }
    });

    test('all subtasks show when there is room', () {
      final r = rows(320, false, 3);
      expect(r.subtasks, 3);
      expect(r.moreRow, isFalse);
      expect(r.badge, isFalse);
      expect(r.hidden(3), 0);
    });

    test('a full block shows some subtasks and a more row', () {
      final r = rows(64, false, 5);
      expect(r, const BlockRows(title: 1, subtasks: 1, moreRow: true));
      expect(r.hidden(5), 4);
    });

    test('the summary comes before the subtasks', () {
      expect(
        rows(79, true, 3),
        const BlockRows(title: 1, summary: 1, subtasks: 1, moreRow: true),
      );
    });

    test('exactly enough room shows every subtask and no more row', () {
      expect(rows(64, false, 2), const BlockRows(title: 1, subtasks: 2));
    });

    test('one spare line shows only the count row', () {
      expect(rows(43, false, 3), const BlockRows(title: 1, moreRow: true));
      // One subtask fits in that line, so it shows.
      expect(rows(43, false, 1).subtasks, 1);
    });

    test('no spare line shows a badge in the title row', () {
      expect(rows(36, false, 2), const BlockRows(title: 1, badge: true));
      // A summary that takes the last line also leaves only the badge.
      final s = rows(43, true, 2);
      expect(s.summary, 1);
      expect(s.subtasks, 0);
      expect(s.badge, isTrue);
    });

    test('leftover lines go back to the title and the summary', () {
      final r = rows(320, true, 2);
      expect(r.title, 2);
      expect(r.subtasks, 2);
      expect(r.summary > 1, isTrue);
      expect(r.moreRow, isFalse);
    });

    test('labels for the more row and the badge', () {
      expect(
        SubtaskLabels.more(hidden: 3, shown: 2, done: 1, total: 5),
        '+3 more',
      );
      expect(
        SubtaskLabels.more(hidden: 4, shown: 0, done: 1, total: 4),
        '1/4 subtasks',
      );
      expect(SubtaskLabels.badge(done: 1, total: 4), '1/4');
    });
  });

  group('InlineTitleRules', () {
    test('text left in the field is kept', () {
      expect(InlineTitleRules.onBlur('Call mum'), BlurAction.commit);
      expect(InlineTitleRules.onBlur('  Call mum \n'), BlurAction.commit);
    });

    test('empty or blank text is dropped', () {
      expect(InlineTitleRules.onBlur(''), BlurAction.cancel);
      expect(InlineTitleRules.onBlur('   '), BlurAction.cancel);
      expect(InlineTitleRules.onBlur(' \n\t '), BlurAction.cancel);
    });

    test('a rename with no change is dropped', () {
      expect(
        InlineTitleRules.onBlur('Write report', initial: 'Write report'),
        BlurAction.cancel,
      );
      expect(
        InlineTitleRules.onBlur(' Write report ', initial: 'Write report'),
        BlurAction.cancel,
      );
    });

    test('a rename with a new title is kept', () {
      expect(
        InlineTitleRules.onBlur('Write the report', initial: 'Write report'),
        BlurAction.commit,
      );
    });

    test('clearing an old title is dropped, not saved', () {
      expect(
        InlineTitleRules.onBlur('', initial: 'Write report'),
        BlurAction.cancel,
      );
    });
  });

  group('Workload', () {
    test('the label shows planned time and the limit', () {
      expect(Workload.label(planned: 390, limit: 540), '6h 30m/9h');
      expect(Workload.label(planned: 0, limit: 540), '0m/9h');
      expect(Workload.label(planned: 600, limit: 480), '10h/8h');
    });

    test('the bar fills up to the limit', () {
      expect(Workload.fraction(planned: 0, limit: 540), 0);
      expect(Workload.fraction(planned: 270, limit: 540), 0.5);
      expect(Workload.fraction(planned: 540, limit: 540), 1);
      expect(Workload.fraction(planned: 900, limit: 540), 1);
      expect(Workload.fraction(planned: 60, limit: 0), 1);
    });

    test('over means more than the limit', () {
      expect(Workload.isOver(planned: 540, limit: 540), isFalse);
      expect(Workload.isOver(planned: 541, limit: 540), isTrue);
      expect(Workload.isOver(planned: 0, limit: 540), isFalse);
    });
  });
}
