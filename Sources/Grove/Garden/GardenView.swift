import SwiftUI
import GroveCore

/// The Garden screen: one plant that grows with every task you finish.
struct GardenView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motionOn: Bool { MotionRules.isOn(setting: store.motionSetting, reduceMotion: reduceMotion) }

    var body: some View {
        let _ = store.revision
        let done = store.gardenDone()
        let stage = Garden.stage(done: done)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                hero(done: done, stage: stage)
                ladder(done: done, current: stage)
            }
            .padding(.horizontal, 24).padding(.top, 38).padding(.bottom, 24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Garden").themedHeading(theme, 28, weight: .semibold).foregroundStyle(theme.ink)
            Text("Your plant grows each time you finish a task.").font(theme.body(12)).foregroundStyle(theme.muted)
        }
    }

    // MARK: The plant

    private func hero(done: Int, stage: GardenStage) -> some View {
        VStack(spacing: 14) {
            plant(done: done)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
            VStack(spacing: 4) {
                Text(stage.name).themedHeading(theme, 24, weight: .semibold).foregroundStyle(theme.ink)
                Text(done == 1 ? "1 task finished" : "\(done) tasks finished").font(theme.body(13)).foregroundStyle(theme.muted)
            }
            nextStep(done: done)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .panel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Garden plant, \(stage.name)")
        .accessibilityValue(done == 1 ? "1 task finished" : "\(done) tasks finished")
    }

    private func plant(done: Int) -> some View {
        let growth = Garden.growth(done: done)
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motionOn)) { context in
            GardenDrawing(growth: growth)
                .rotationEffect(.degrees(motionOn ? sway(growth: growth, at: context.date.timeIntervalSinceReferenceDate) : 0),
                                anchor: .init(x: 0.5, y: 0.88))
        }
        .animation(motionOn ? .spring(response: 0.9, dampingFraction: 0.7) : nil, value: growth)
    }

    /// A big tree sways less than a sprout.
    private func sway(growth: Double, at seconds: Double) -> Double {
        PlantMath.swayDegrees(at: seconds) * (1 - 0.5 * growth / Garden.maxGrowth)
    }

    @ViewBuilder private func nextStep(done: Int) -> some View {
        if let next = Garden.next(after: done), let left = Garden.tasksToNext(done: done) {
            VStack(spacing: 6) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.surface2)
                        Capsule().strokeBorder(theme.line)
                        Capsule().fill(theme.accent).frame(width: max(8, g.size.width * Garden.progress(done: done)))
                    }
                }
                .frame(height: 8).frame(maxWidth: 360)
                Text("\(left) more \(left == 1 ? "task" : "tasks") to become a \(next.name.lowercased())")
                    .font(theme.body(12)).foregroundStyle(theme.muted)
            }
        } else {
            Text("Fully grown. Keep going. It likes company.").font(theme.body(12)).foregroundStyle(theme.muted)
        }
    }

    // MARK: All the stages

    private func ladder(done: Int, current: GardenStage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stages").themedHeading(theme, 16, weight: .semibold).foregroundStyle(theme.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 160), spacing: 10)], spacing: 10) {
                ForEach(Garden.stages, id: \.index) { stage in
                    stageCard(stage, reached: done >= stage.from, isCurrent: stage == current)
                }
            }
        }
    }

    private func stageCard(_ stage: GardenStage, reached: Bool, isCurrent: Bool) -> some View {
        VStack(spacing: 4) {
            GardenDrawing(growth: Double(stage.index))
                .frame(height: 96)
                .opacity(reached ? 1 : 0.25)
            Text(stage.name).font(theme.body(12, weight: .semibold)).foregroundStyle(reached ? theme.ink : theme.muted).lineLimit(1)
            Text(stage.from == 0 ? "Start" : "\(stage.from) \(stage.from == 1 ? "task" : "tasks")")
                .font(theme.body(10)).foregroundStyle(theme.muted)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surface2.opacity(reached ? 1 : 0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(isCurrent ? theme.accent : theme.line, lineWidth: isCurrent ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.name), from \(stage.from) tasks")
        .accessibilityValue(isCurrent ? "Now" : reached ? "Reached" : "Not yet")
    }
}
