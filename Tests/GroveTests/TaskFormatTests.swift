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
