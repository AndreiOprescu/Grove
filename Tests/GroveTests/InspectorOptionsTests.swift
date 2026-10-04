import Testing
import GroveCore
@testable import Grove

struct InspectorOptionsTests {
    @Test func everyPresetReadsBackAsItself() {
        for p in RepeatPreset.allCases where p != .custom {
            #expect(RepeatPreset.of(p.rule) == p, "\(p)")
        }
    }

    @Test func noRuleIsNone() {
        #expect(RepeatPreset.of(nil) == .none)
        #expect(RepeatPreset.none.rule == nil)
    }

    @Test func presetRules() {
        #expect(RepeatPreset.daily.rule == RecurrenceRule(freq: .daily))
        #expect(RepeatPreset.weekdays.rule == RecurrenceRule(freq: .weekly, weekdays: [1, 2, 3, 4, 5]))
        #expect(RepeatPreset.biweekly.rule == RecurrenceRule(freq: .weekly, interval: 2))
    }

    @Test func otherRulesAreCustomAndKeepTheirDetails() {
        #expect(RepeatPreset.of(RecurrenceRule(freq: .daily, interval: 3)) == .custom)
        #expect(RepeatPreset.of(RecurrenceRule(freq: .weekly, weekdays: [2, 4])) == .custom)
        #expect(RepeatPreset.of(RecurrenceRule(freq: .daily, until: "2027-01-01")) == .custom)
        #expect(RepeatPreset.of(RecurrenceRule(freq: .monthly, count: 5)) == .custom)
    }

    @Test func estimateChoicesAlwaysHoldTheCurrentValueOnce() {
        #expect(InspectorOptions.estimates(including: 30).filter { $0 == 30 }.count == 1)
        let odd = InspectorOptions.estimates(including: 37)
        #expect(odd.contains(37) && odd == odd.sorted())
        #expect(!InspectorOptions.estimates(including: 30).contains(37))
    }

    @Test func estimateChoicesFollowTheFifteenMinuteGrid() {
        #expect(InspectorOptions.estimates(including: 30).allSatisfy { $0 % 15 == 0 })
        #expect(InspectorOptions.estimates(including: 30).first == 15)
    }

    @Test func dueDatesReadAndWrite() {
        #expect(InspectorOptions.dueDay("2026-10-05") == "2026-10-05")
        #expect(InspectorOptions.dueDay("2026-10-05T14:30") == "2026-10-05")
        #expect(InspectorOptions.dueDay(nil) == nil)
        #expect(InspectorOptions.dueString(day: "2026-10-05", keepingTimeOf: "2026-10-01T14:30") == "2026-10-05T14:30")
        #expect(InspectorOptions.dueString(day: "2026-10-05", keepingTimeOf: "2026-10-01") == "2026-10-05")
        #expect(InspectorOptions.dueString(day: "2026-10-05", keepingTimeOf: nil) == "2026-10-05")
    }

    @Test func planBucketsMapToPlacements() {
        let mon: DayKey = "2026-10-05", wed: DayKey = "2026-10-07"
        #expect(InspectorOptions.placement(bucket: .inbox, date: wed) == .inbox)
        #expect(InspectorOptions.placement(bucket: .someday, date: wed) == .someday)
        #expect(InspectorOptions.placement(bucket: .day, date: wed) == .day(wed))
        #expect(InspectorOptions.placement(bucket: .week, date: wed) == .week(mon))
    }
}
