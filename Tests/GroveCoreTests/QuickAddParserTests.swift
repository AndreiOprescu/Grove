import Testing
@testable import GroveCore

/// "Today" is Friday 2026-10-02 in every test, so results never depend on the real clock.
struct QuickAddParserTests {
    let parser = QuickAddParser(today: "2026-10-02", lists: ["Home", "Work", "Personal"])

    // MARK: Plan examples

    @Test func callMum() {
        let r = parser.parse("Call mum tomorrow 6pm for 20m #home !2")
        #expect(r.title == "Call mum")
        #expect(r.bucket == .day)
        #expect(r.planDate == "2026-10-03")
        #expect(r.startMinute == 18 * 60)
        #expect(r.durationMin == 20)
        #expect(r.blockEnd == 18 * 60 + 20)
        #expect(r.tags == ["home"])
        #expect(r.priority == 2)
    }

    @Test func readNextWeek() {
        let r = parser.parse("Read ch 5 next week")
        #expect(r.title == "Read ch 5")
        #expect(r.bucket == .week)
        #expect(r.planWeek == "2026-10-05")
        #expect(r.planDate == nil)
    }

    @Test func gymEveryMonday() {
        let r = parser.parse("Gym every mon 7am")
        #expect(r.title == "Gym")
        #expect(r.recurrence == RecurrenceRule(freq: .weekly, interval: 1, weekdays: [1]))
        #expect(r.planDate == "2026-10-05")
        #expect(r.startMinute == 7 * 60)
        #expect(r.blockEnd == 7 * 60 + 30)
    }

    @Test func payRentDue() {
        let r = parser.parse("Pay rent due 5 oct")
        #expect(r.title == "Pay rent")
        #expect(r.due == "2026-10-05")
        #expect(r.bucket == .inbox)
        #expect(r.planDate == nil)
    }

    // MARK: Plain text

    @Test func plainTitle() {
        let r = parser.parse("Buy milk")
        #expect(r.title == "Buy milk")
        #expect(r.bucket == .inbox)
        #expect(r.chips.isEmpty)
    }

    @Test func spacesAreTidied() {
        #expect(parser.parse("  Buy   milk  tomorrow ").title == "Buy milk")
    }

    @Test func wordsThatOnlyLookLikeTokensStay() {
        #expect(parser.parse("Sundae party").title == "Sundae party")
        #expect(parser.parse("Monitor setup").title == "Monitor setup")
        #expect(parser.parse("Learn C# basics").tags.isEmpty)
        #expect(parser.parse("Wow!").title == "Wow!")
        #expect(parser.parse("Fix bug !9").priority == 0)
    }

    @Test func nothingLeftKeepsWhatYouTyped() {
        let r = parser.parse("tomorrow")
        #expect(r.title == "tomorrow")
        #expect(r.planDate == nil)
        #expect(r.bucket == .inbox)
    }

    @Test func caseDoesNotMatter() {
        #expect(parser.parse("Call Sam TOMORROW").planDate == "2026-10-03")
    }

    // MARK: Dates

    @Test func todayWords() {
        #expect(parser.parse("Email Sam today").planDate == "2026-10-02")
        #expect(parser.parse("Email Sam tod").planDate == "2026-10-02")
        #expect(parser.parse("Email Sam tmr").planDate == "2026-10-03")
    }

    @Test func weekdayIsNextOccurrenceOrTodayIfSame() {
        #expect(parser.parse("Gym fri").planDate == "2026-10-02")
        #expect(parser.parse("Gym sat").planDate == "2026-10-03")
        #expect(parser.parse("Gym mon").planDate == "2026-10-05")
        #expect(parser.parse("Gym wednesday").planDate == "2026-10-07")
        #expect(parser.parse("Gym thurs").planDate == "2026-10-08")
    }

    @Test func weekBuckets() {
        let next = parser.parse("Plan next week")
        #expect(next.bucket == .week && next.planWeek == "2026-10-05" && next.title == "Plan")
        let this = parser.parse("Review this week")
        #expect(this.bucket == .week && this.planWeek == "2026-09-28")
    }

    @Test func someday() {
        let r = parser.parse("Learn piano someday")
        #expect(r.bucket == .someday)
        #expect(r.title == "Learn piano")
    }

    @Test func calendarDates() {
        #expect(parser.parse("Dentist 3 oct").planDate == "2026-10-03")
        #expect(parser.parse("Dentist oct 3").planDate == "2026-10-03")
        #expect(parser.parse("Dentist 3/10").planDate == "2026-10-03")
        #expect(parser.parse("Dentist 3 October").planDate == "2026-10-03")
        #expect(parser.parse("Dentist 3 oct").title == "Dentist")
    }

    @Test func pastDateRollsToNextYear() {
        #expect(parser.parse("Renew 1 oct").planDate == "2027-10-01")
    }

    @Test func impossibleDateStaysInTitle() {
        let r = parser.parse("Party 31 feb")
        #expect(r.planDate == nil)
        #expect(r.title == "Party 31 feb")
    }

    @Test func inSomeDays() {
        #expect(parser.parse("Call in 3 days").planDate == "2026-10-05")
        #expect(parser.parse("Call in 2 weeks").planDate == "2026-10-16")
        #expect(parser.parse("Call in 3 days").title == "Call")
    }

    // MARK: Times and lengths

    @Test func clockTimes() {
        #expect(parser.parse("Standup 9:30am").startMinute == 570)
        #expect(parser.parse("Lunch at 12").startMinute == 720)
        #expect(parser.parse("Call 18:00").startMinute == 1080)
        #expect(parser.parse("Call 6:30pm").startMinute == 1110)
        #expect(parser.parse("Wake 12am").startMinute == 0)
        #expect(parser.parse("Eat 12pm").startMinute == 720)
    }

    @Test func timeAloneMeansToday() {
        let r = parser.parse("Standup 9am")
        #expect(r.planDate == "2026-10-02")
        #expect(r.bucket == .day)
        #expect(r.title == "Standup")
    }

    @Test func lengths() {
        #expect(parser.parse("Write for 45m").durationMin == 45)
        #expect(parser.parse("Write for 1h").durationMin == 60)
        #expect(parser.parse("Write for 1h30").durationMin == 90)
        #expect(parser.parse("Write 90m").durationMin == 90)
        #expect(parser.parse("Write 1h30m").durationMin == 90)
        #expect(parser.parse("Write for 2 hours").durationMin == 120)
        #expect(parser.parse("Write for 45m").title == "Write")
    }

    @Test func lengthAloneMakesNoBlock() {
        let r = parser.parse("Write 45m")
        #expect(r.startMinute == nil)
        #expect(r.bucket == .inbox)
    }

    @Test func blockEndStopsAtMidnight() {
        let r = parser.parse("Late 11:50pm for 30m")
        #expect(r.startMinute == 23 * 60 + 50)
        #expect(r.blockEnd == 1440)
    }

    @Test func timeOnAWeekTaskStaysInTheTitle() {
        let r = parser.parse("Read next week 6pm")
        #expect(r.startMinute == nil)
        #expect(r.title == "Read 6pm")
    }

    // MARK: Tags, priority, lists

    @Test func tagsAndPriority() {
        let r = parser.parse("Plan #work #Q4 !3")
        #expect(r.tags == ["work", "q4"])
        #expect(r.priority == 3)
        #expect(r.title == "Plan")
    }

    @Test func listMatching() {
        #expect(parser.parse("Mow lawn /home").listName == "Home")
        #expect(parser.parse("Mow lawn /wo").listName == "Work")
        #expect(parser.parse("Mow lawn /home").title == "Mow lawn")
        let none = parser.parse("Pay /xyz")
        #expect(none.listName == nil)
        #expect(none.title == "Pay /xyz")
    }

    // MARK: Repeats

    @Test func everyDay() {
        let r = parser.parse("Water plants every day")
        #expect(r.recurrence == RecurrenceRule(freq: .daily))
        #expect(r.planDate == "2026-10-02")
        #expect(r.title == "Water plants")
    }

    @Test func everyWeekday() {
        let r = parser.parse("Standup every weekday 9am")
        #expect(r.recurrence == RecurrenceRule(freq: .weekly, interval: 1, weekdays: [1, 2, 3, 4, 5]))
        #expect(r.planDate == "2026-10-02")
        #expect(r.startMinute == 540)
        let weekend = QuickAddParser(today: "2026-10-03").parse("Standup every weekday")
        #expect(weekend.planDate == "2026-10-05")
    }

    @Test func otherRepeats() {
        #expect(parser.parse("Review every week").recurrence == RecurrenceRule(freq: .weekly))
        #expect(parser.parse("Pay every 2 weeks").recurrence == RecurrenceRule(freq: .weekly, interval: 2))
        #expect(parser.parse("Rent every month").recurrence == RecurrenceRule(freq: .monthly))
        #expect(parser.parse("Dust every 3 days").recurrence == RecurrenceRule(freq: .daily, interval: 3))
        #expect(parser.parse("Rent every year").recurrence == RecurrenceRule(freq: .yearly))
    }

    // MARK: Deadlines

    @Test func dueIsNotThePlanDate() {
        let r = parser.parse("Report due fri")
        #expect(r.due == "2026-10-02")
        #expect(r.planDate == nil)
        #expect(r.title == "Report")
    }

    @Test func dueWithATime() {
        let r = parser.parse("Report due tomorrow 5pm")
        #expect(r.due == "2026-10-03T17:00")
        #expect(r.startMinute == nil)
    }

    // MARK: Everything together, and the preview chips

    @Test func everything() {
        let r = parser.parse("Finish report fri 2pm for 2h #work !1 /Work")
        #expect(r.title == "Finish report")
        #expect(r.planDate == "2026-10-02")
        #expect(r.startMinute == 840)
        #expect(r.durationMin == 120)
        #expect(r.tags == ["work"])
        #expect(r.priority == 1)
        #expect(r.listName == "Work")
    }

    @Test func chipsShowWhatWasParsed() {
        let r = parser.parse("Call mum tomorrow 6pm for 20m #home !2 /Home")
        #expect(r.chips.map(\.kind) == [.date, .time, .duration, .list, .tag, .priority])
        #expect(r.chips.first?.text == "Sat 3 Oct")
        #expect(r.chips[1].text == "18:00")
        #expect(r.chips[2].text == "20m")
    }
}
