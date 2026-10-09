import Testing
import Foundation
import GroveCore
@testable import Grove

struct TaskFormatTests {
    let today: DayKey = "2026-10-02"

    @Test func nearDaysHaveNames() {
        #expect(TaskFormat.dayLabel(today, today: today) == "Today")
        #expect(TaskFormat.dayLabel("2026-10-03", today: today) == "Tomorrow")
        #expect(TaskFormat.dayLabel("2026-10-01", today: today) == "Yesterday")
    }

    @Test func otherDaysShowWeekdayDayAndMonth() {
        let text = TaskFormat.dayLabel("2026-10-09", today: today)
        #expect(text.contains("9"))
        #expect(!["Today", "Tomorrow", "Yesterday"].contains(text))
    }

    @Test func dateLabelNeverUsesRelativeNames() {
        #expect(TaskFormat.dateLabel("2026-10-01") != "Yesterday")
        #expect(TaskFormat.dateLabel("2026-10-01").contains("1"))
    }

    @Test func weekLabelNamesItsMonday() {
        let text = TaskFormat.weekLabel("2026-10-05")
        #expect(text.hasPrefix("Week of "))
        #expect(text.contains("5") && !text.contains("Mon"))
    }

    @Test func planLabelSaysWhereATaskLives() {
        #expect(TaskFormat.planLabel(TaskItem(title: "a", bucket: .day, planDate: "2026-10-03"), today: today) == "Tomorrow")
        #expect(TaskFormat.planLabel(TaskItem(title: "b", bucket: .week, planWeek: "2026-10-05"), today: today)
                == TaskFormat.weekLabel("2026-10-05"))
        #expect(TaskFormat.planLabel(TaskItem(title: "c", bucket: .someday), today: today) == "Someday")
        #expect(TaskFormat.planLabel(TaskItem(title: "d"), today: today) == nil)
    }

    @Test func dueDayInThePastIsLate() {
        let d = TaskFormat.due("2026-10-01", today: today, nowMinute: 600)
        #expect(d.late && d.text == "due Yesterday")
    }

    @Test func dueTimeTodayIsLateOnlyAfterItPassed() {
        #expect(TaskFormat.due("2026-10-02T09:00", today: today, nowMinute: 600).late)
        let early = TaskFormat.due("2026-10-02T09:00", today: today, nowMinute: 500)
        #expect(!early.late && early.text == "due Today 09:00")
    }

    @Test func dueInTheFutureIsNotLate() {
        #expect(!TaskFormat.due("2026-10-05", today: today, nowMinute: 1200).late)
    }

    @Test func everyChipKindHasASymbol() {
        for kind in [QuickAddChip.Kind.date, .time, .duration, .repeats, .due, .list, .tag, .priority] {
            #expect(!TaskFormat.symbol(kind).isEmpty)
        }
    }
}
