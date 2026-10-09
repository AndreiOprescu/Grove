import Testing
import Foundation
@testable import GroveCore

/// How the garden plant grows with the tasks you finish.
struct GardenTests {
    private let last = Garden.stages.count - 1

    @Test func thereAreManyStagesFromASeedToATree() {
        #expect(Garden.stages.count == 12)
        #expect(Garden.stages.first?.name == "Seed")
        #expect(Garden.stages.last?.name == "Ancient tree")
    }

    @Test func stagesStartAtZeroAndNeedMoreTasksEachTime() {
        #expect(Garden.stages.first?.from == 0)
        for (a, b) in zip(Garden.stages, Garden.stages.dropFirst()) { #expect(a.from < b.from) }
        #expect(Set(Garden.stages.map(\.name)).count == Garden.stages.count)
        #expect(Garden.stages.enumerated().allSatisfy { $0.offset == $0.element.index })
    }

    @Test func theStageComesFromTheNumberOfFinishedTasks() {
        #expect(Garden.stage(done: 0).name == "Seed")
        #expect(Garden.stage(done: 1).name == "Sprout")
        #expect(Garden.stage(done: 2).name == "Sprout")
        #expect(Garden.stage(done: 3).name == "Seedling")
        #expect(Garden.stage(done: 119).name == "Full tree")
        #expect(Garden.stage(done: 120).name == "Ancient tree")
        #expect(Garden.stage(done: 5000).name == "Ancient tree")
        #expect(Garden.stage(done: -4).name == "Seed")
    }

    @Test func everyFinishedTaskMakesThePlantGrowAUnit() {
        // A real, gradual change: no task leaves the plant as it was, until the last stage.
        let top = Garden.stages[last].from
        for done in 0..<top { #expect(Garden.growth(done: done + 1) > Garden.growth(done: done), "task \(done + 1)") }
    }

    @Test func growthIsTheStageNumberAtTheStartOfAStage() {
        for s in Garden.stages { #expect(Garden.growth(done: s.from) == Double(s.index)) }
    }

    @Test func growthStaysBetweenTheStagesAndStopsAtTheTop() {
        let mid = Garden.growth(done: 4)
        #expect(mid > 2 && mid < 3)
        #expect(Garden.growth(done: 100_000) == Double(last))
        #expect(Garden.growth(done: -1) == 0)
        #expect(Garden.maxGrowth == Double(last))
    }

    @Test func theProgressInAStageGoesFromZeroToJustUnderOne() {
        #expect(Garden.progress(done: 3) == 0)
        let p = Garden.progress(done: 4)
        #expect(p > 0 && p < 1)
        #expect(Garden.progress(done: 5) > p)
        #expect(Garden.progress(done: 120) == 1)
        #expect(Garden.progress(done: 9999) == 1)
    }

    @Test func theNextStageAndTheTasksStillNeeded() {
        #expect(Garden.next(after: 0)?.name == "Sprout")
        #expect(Garden.tasksToNext(done: 0) == 1)
        #expect(Garden.tasksToNext(done: 1) == 2)
        #expect(Garden.tasksToNext(done: 2) == 1)
        #expect(Garden.next(after: 120) == nil)
        #expect(Garden.tasksToNext(done: 120) == nil)
    }

    @Test func theDoneCountIsTheFinishedTasksInTheDatabase() throws {
        let r = Repos(db: try Database.inMemory())
        #expect(try r.tasks.doneCount() == 0)
        var a = TaskItem(id: "A", title: "a"); a.status = .done
        var b = TaskItem(id: "B", title: "b"); b.status = .cancelled
        try r.tasks.save(a); try r.tasks.save(b); try r.tasks.save(TaskItem(id: "C", title: "c"))
        #expect(try r.tasks.doneCount() == 1)
    }
}
