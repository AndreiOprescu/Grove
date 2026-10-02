import Testing
import Foundation
@testable import GroveCore

/// The `@date time` token in a note line (PLAN §5.5 item 2).
struct AtDateParserTests {
    let today = DayKey("2026-10-02")   // a Friday

    private func find(_ line: String) -> AtDate? { AtDateParser.find(in: line, today: today) }
    private func text(_ line: String, _ hit: AtDate?) -> String? { hit.map { (line as NSString).substring(with: $0.range) } }

    @Test func aWeekdayAndATime() {
        let line = "Lunch with Sam @mon 12:30 at the cafe"
        let hit = find(line)
        #expect(text(line, hit) == "@mon 12:30")
        #expect(hit?.day == DayKey("2026-10-05"))
        #expect(hit?.startMinute == 750)
        #expect(hit?.durationMin == nil)
    }

    @Test func aWordAndAnAmPmTime() {
        let line = "Call Sam @tomorrow 3pm"
        let hit = find(line)
        #expect(text(line, hit) == "@tomorrow 3pm")
        #expect(hit?.day == DayKey("2026-10-03") && hit?.startMinute == 900)
    }

    @Test func aLengthIsPartOfTheToken() {
        let line = "Review @today 9:30 for 1h30 and send it"
        let hit = find(line)
        #expect(text(line, hit) == "@today 9:30 for 1h30")
        #expect(hit?.startMinute == 570 && hit?.durationMin == 90)
    }

    @Test func aDayWithNoTimeHasNoStartMinute() {
        let hit = find("Dentist @tomorrow")
        #expect(hit?.day == DayKey("2026-10-03") && hit?.startMinute == nil)
    }

    @Test func aTimeWithNoDayLeavesTheDayToTheCaller() {
        let hit = find("Stand up @9am")
        #expect(hit?.day == nil && hit?.startMinute == 540)
    }

    @Test func aMonthAndADay() {
        let hit = find("Flight @oct 20 6am")
        #expect(hit?.day == DayKey("2026-10-20") && hit?.startMinute == 360)
    }

    @Test func aNameIsNotAToken() {
        #expect(find("Ask @sam about it") == nil)
        #expect(find("Ask @ about it") == nil)
        #expect(find("No at sign here, fri 3pm") == nil)
    }

    @Test func anEmailAddressIsNotAToken() {
        #expect(find("Write to sam@tomorrow.com") == nil)
    }

    @Test func wordsAfterTheDateStayOutsideTheToken() {
        let line = "@fri call Sam"
        #expect(text(line, find(line)) == "@fri")
    }

    @Test func tagsAndOtherQuickAddWordsAreNotPartOfTheToken() {
        let line = "Pay rent @fri #home"
        #expect(text(line, find(line)) == "@fri")
        #expect(find("Pay @every day") == nil)
        #expect(find("Pay @due fri") == nil)
        #expect(find("Plan @next week") == nil)   // a week is not a day
    }

    @Test func theFirstGoodTokenWins() {
        let line = "@sam says @fri 10am"
        let hit = find(line)
        #expect(text(line, hit) == "@fri 10am")
    }

    @Test func offsetsAreUTF16() {
        let line = "Café ☕ @fri 3pm"
        let hit = find(line)
        #expect(text(line, hit) == "@fri 3pm")
    }
}
