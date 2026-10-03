import Testing
import Foundation
import GroveCore
@testable import Grove

/// The plant, the check-off burst and the greeting (PLAN §6.2, §6.3).
struct PlantMathTests {
    @Test func noTasksMeansNoLeaves() {
        #expect(PlantMath.leaves(done: 0, total: 0) == 0)
        #expect(PlantMath.leaves(done: 3, total: 0) == 0)
    }

    @Test func nothingDoneMeansNoLeaves() {
        #expect(PlantMath.leaves(done: 0, total: 5) == 0)
    }

    @Test func everythingDoneMeansSixLeaves() {
        #expect(PlantMath.leaves(done: 5, total: 5) == 6)
        #expect(PlantMath.leaves(done: 1, total: 1) == 6)
    }

    @Test func halfDoneMeansThreeLeaves() {
        #expect(PlantMath.leaves(done: 2, total: 4) == 3)
    }

    @Test func anyProgressShowsAtLeastOneLeaf() {
        #expect(PlantMath.leaves(done: 1, total: 100) == 1)
    }

    @Test func neverMoreThanSixLeaves() {
        #expect(PlantMath.leaves(done: 9, total: 3) == 6)
    }

    @Test func moreDoneNeverMeansFewerLeaves() {
        var last = 0
        for done in 0...10 {
            let n = PlantMath.leaves(done: done, total: 10)
            #expect(n >= last)
            last = n
        }
    }

    @Test func theStemGrowsWithTheLeaves() {
        #expect(PlantMath.stemGrowth(leaves: 0) > 0)
        #expect(PlantMath.stemGrowth(leaves: 0) < PlantMath.stemGrowth(leaves: 3))
        #expect(PlantMath.stemGrowth(leaves: 3) < PlantMath.stemGrowth(leaves: 6))
        #expect(PlantMath.stemGrowth(leaves: 6) == 1)
    }

    @Test func theFlowerOpensOnlyWhenEverythingIsDone() {
        #expect(!PlantMath.hasFlower(done: 4, total: 5))
        #expect(PlantMath.hasFlower(done: 5, total: 5))
        #expect(!PlantMath.hasFlower(done: 0, total: 0))
    }

    @Test func theSwayIsThreeDegreesEveryFiveSeconds() {
        for t in stride(from: 0.0, through: 30, by: 0.37) { #expect(abs(PlantMath.swayDegrees(at: t)) <= 3.0001) }
        #expect(abs(PlantMath.swayDegrees(at: 1.25) - 3) < 0.001)   // a quarter of the period is the top
        #expect(abs(PlantMath.swayDegrees(at: 0) - PlantMath.swayDegrees(at: 5)) < 0.001)
    }
}

struct BurstMathTests {
    @Test func groveThrowsSixLeavesOut18Points() {
        #expect(BurstMath.style(for: .grove) == .leaves)
        let p = BurstMath.particles(for: .leaves)
        #expect(p.count == 6)
        #expect(p.allSatisfy { $0.distance == 18 })
        let angles = p.map(\.angle).sorted()
        for i in 1..<angles.count { #expect(abs(angles[i] - angles[i - 1] - 60) < 0.001) }
    }

    @Test func eachThemeHasItsOwnBurst() {
        #expect(BurstMath.style(for: .minimal) == .fade)
        #expect(BurstMath.style(for: .futuristic) == .ringAndSparks)
        #expect(BurstMath.style(for: .vintage) == .stamp)
    }

    @Test func aFadeAndAStampHaveNoFlyingParts() {
        #expect(BurstMath.particles(for: .fade).isEmpty)
        #expect(BurstMath.particles(for: .stamp).isEmpty)
        #expect(!BurstMath.particles(for: .ringAndSparks).isEmpty)
    }

    @Test func aParticleFliesOutAndFades() {
        #expect(BurstMath.distance(18, progress: 0) == 0)
        #expect(BurstMath.distance(18, progress: 1) == 18)
        #expect(BurstMath.opacity(progress: 0) == 1)
        #expect(BurstMath.opacity(progress: 1) == 0)
        #expect(BurstMath.duration == 0.5)
    }
}

struct GreetingTests {
    @Test func theGreetingFollowsTheTimeOfDay() {
        #expect(Greeting.text(hour: 5) == "Good morning")
        #expect(Greeting.text(hour: 11) == "Good morning")
        #expect(Greeting.text(hour: 12) == "Good afternoon")
        #expect(Greeting.text(hour: 17) == "Good afternoon")
        #expect(Greeting.text(hour: 18) == "Good evening")
        #expect(Greeting.text(hour: 23) == "Good evening")
        #expect(Greeting.text(hour: 0) == "Good evening")
        #expect(Greeting.text(hour: 4) == "Good evening")
    }
}

@MainActor
struct PlantProgressStoreTests {
    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    @Test func theProgressCountsTodaysTasks() throws {
        let s = try makeStore()
        let today = DayKey("2026-10-04")
        let a = try #require(s.quickAdd("A", default: .day(today)))
        _ = s.quickAdd("B", default: .day(today))
        _ = s.quickAdd("C", default: .day(DayKey("2026-10-05")))   // another day
        #expect(s.plantProgress(on: today) == PlantProgress(done: 0, total: 2))
        s.toggleDone(taskId: a.id)
        #expect(s.plantProgress(on: today) == PlantProgress(done: 1, total: 2))
    }

    @Test func theTextUnderThePlantSaysHowMuchIsGrown() {
        #expect(PlantProgress(done: 0, total: 0).growthText == "Nothing planned today")
        #expect(PlantProgress(done: 1, total: 4).growthText == "25% of today grown")
        #expect(PlantProgress(done: 3, total: 3).growthText == "100% of today grown")
        #expect(PlantProgress(done: 1, total: 3).percent == 33)
    }

    @Test func aTaskCheckedOffWithLingerStaysInTheOpenListForAMoment() async throws {
        let s = try makeStore()
        let today = DayKey("2026-10-04")
        let a = try #require(s.quickAdd("A", default: .day(today)))
        s.toggleDone(taskId: a.id, linger: true)
        #expect(s.task(a.id)?.isDone == true)
        #expect(s.openTasks(in: .day(today)).map(\.id) == [a.id])
        try await Task.sleep(for: .milliseconds(1000))
        #expect(s.openTasks(in: .day(today)).isEmpty)
    }

    @Test func withoutLingerADoneTaskLeavesTheOpenListAtOnce() throws {
        let s = try makeStore()
        let today = DayKey("2026-10-04")
        let a = try #require(s.quickAdd("A", default: .day(today)))
        s.toggleDone(taskId: a.id)
        #expect(s.openTasks(in: .day(today)).isEmpty)
    }

    @Test func aDayWithNoTasksIsEmpty() throws {
        #expect(try makeStore().plantProgress(on: DayKey("2026-10-04")) == PlantProgress(done: 0, total: 0))
    }
}

struct ThemeDecorTests {
    @Test func theNowLinePulsesBetween1And045InThreePointTwoSeconds() {
        #expect(PulseMath.period == 3.2)
        #expect(abs(PulseMath.opacity(at: 0) - 1) < 0.0001)
        #expect(abs(PulseMath.opacity(at: 1.6) - 0.45) < 0.0001)
        #expect(abs(PulseMath.opacity(at: 3.2) - 1) < 0.0001)
        for t in stride(from: 0.0, through: 20, by: 0.13) {
            let o = PulseMath.opacity(at: t)
            #expect(o >= 0.45 - 0.0001 && o <= 1.0001)
        }
    }

    @Test func theGridHasALineEvery32Points() {
        #expect(GridMath.spacing == 32)
        #expect(GridMath.lines(length: 100) == [0, 32, 64, 96])
        #expect(GridMath.lines(length: 0) == [0])
        #expect(GridMath.lines(length: -1).isEmpty)
        #expect(GridMath.lines(length: 100, spacing: 0).isEmpty)
    }

    @Test func ruledLinesAre28PointsApart() {
        #expect(GridMath.ruledPitch == 28)
        #expect(GridMath.ruledRows(top: 4, minY: 0, maxY: 100) == [32, 60, 88])
        #expect(GridMath.ruledRows(top: 4, minY: 40, maxY: 70) == [60])
        #expect(GridMath.ruledRows(top: 4, minY: 33, maxY: 59).isEmpty)
        #expect(GridMath.ruledRows(top: 4, minY: 50, maxY: 10).isEmpty)
    }

    @Test func theNoiseIsTheSameEveryTime() {
        let a = NoiseMath.dots(count: 50, size: 200, seed: 7)
        #expect(a == NoiseMath.dots(count: 50, size: 200, seed: 7))
        #expect(a != NoiseMath.dots(count: 50, size: 200, seed: 8))
        #expect(a.count == 50)
        #expect(a.allSatisfy { $0.x >= 0 && $0.x <= 200 && $0.y >= 0 && $0.y <= 200 })
        #expect(NoiseMath.dots(count: -3, size: 10, seed: 1).isEmpty)
    }

    @Test func onlyVintageHasRuledLinesAndDashedChips() {
        for id in ThemeID.allCases {
            let t = Theme.make(id)
            #expect(t.ruledLines == (id == .vintage))
            #expect(t.dashedChips == (id == .vintage))
            #expect(t.gridLines == (id == .futuristic))
        }
    }
}
