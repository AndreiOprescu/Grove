import SwiftUI
import AppKit
import GroveCore

/// State of a move or resize in progress. Nothing is written to the database until it ends.
struct LiveEdit {
    var mode: DragMode
    var ids: [String]
    var primaryId: String
    var originals: [String: BlockEdit]
    var deltaMinutes = 0
    var deltaDays = 0
}

struct CreateDrag {
    var dayIndex: Int
    var anchor: Int
    var current: Int
}

struct Draft: Equatable {
    var day: DayKey
    var start: Int
    var end: Int
    var asEvent = false
    var text = ""
}

/// Where the pointer is during a drag, in grid space. Used by auto-scroll too.
struct PointerContext {
    var startX: CGFloat
    var startY: CGFloat
    var lastX: CGFloat
    var lastY: CGFloat
    var scrollAtEvent: CGFloat
}

struct PlannerGrid: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let days: [DayKey]
    @Binding var geo: PlannerGeometry
    @Binding var dropToTray: Bool
    /// Bump to scroll to "now".
    let scrollRequest: Int
    let snapStep: Int
    let workStart: Int
    let workEnd: Int

    @State private var blocks: [PlannerBlock] = []
    @State private var layerMap: [String: Layer] = [:]
    @State private var live: LiveEdit?
    @State private var create: CreateDrag?
    @State private var draft: Draft?
    @State private var renamingId: String?
    @State private var pointer: PointerContext?
    @State private var position = ScrollPosition()
    @State private var scrollY: CGFloat = 0
    @State private var viewportH: CGFloat = 600
    @State private var gridWidth: CGFloat = 800
    @State private var targetedDay: DayKey?
    @State private var autoScroll: Task<Void, Never>?
    @State private var zoomBase: CGFloat?
    @State private var lastSnapped: Int?
    @FocusState private var focused: Bool

    private var dayWidth: CGFloat { max(60, (gridWidth - geo.gutterWidth) / CGFloat(max(days.count, 1))) }
    private var isDragging: Bool { live != nil || create != nil }
    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86) }

    var body: some View {
        ScrollView(.vertical) {
            // The layers are drawn in an overlay on purpose. They have fixed widths (from `gridWidth`),
            // so as the scroll content they set a minimum width. That minimum never shrank, so the
            // grid stayed wide after the tray opened and pushed the window content off screen.
            // This base view only takes the width the scroll view offers; the layers cannot change it.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: geo.totalHeight, maxHeight: geo.totalHeight)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                    if abs(w - gridWidth) > 0.5 { gridWidth = w }
                }
                .overlay(alignment: .topLeading) { layers }
                .coordinateSpace(name: "plannerGrid")
        }
        .scrollPosition($position)
        .scrollDisabled(isDragging)
        .scrollIndicators(.automatic)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in scrollY = y }
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, h in viewportH = h }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { handleKey($0) }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { v in
                    if zoomBase == nil { zoomBase = geo.hourHeight }
                    geo.hourHeight = min(max(zoomBase! * v.magnification, PlannerGeometry.zoomRange.lowerBound), PlannerGeometry.zoomRange.upperBound)
                }
                .onEnded { _ in zoomBase = nil })
        .onAppear {
            reload()
            DispatchQueue.main.async { scrollToNow(animated: false) }
        }
        .onChange(of: store.revision) { reload() }
        .onChange(of: days) { reload(); draft = nil; renamingId = nil }
        .onChange(of: geo.hourHeight) { relayout() }
        .onChange(of: scrollRequest) { scrollToNow(animated: true) }
        .animation(animation, value: layerMap)
    }

    // MARK: Layers

    private var layers: some View {
        let indents = indentMap
        return ZStack(alignment: .topLeading) {
            gridLines
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                dayColumn(index: index, day: day)
            }
            pastFade
            ForEach(blocks) { block in blockView(block, indents: indents) }
            createRect
            draftView
            nowLine
            liveLabel
        }
    }

    private var gridLines: some View {
        Canvas { ctx, size in
            for h in 0...24 {
                let y = geo.y(forMinute: h * 60)
                var line = Path()
                line.move(to: CGPoint(x: geo.gutterWidth - 6, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(theme.line), lineWidth: 1)
                if h < 24 {
                    var half = Path()
                    half.move(to: CGPoint(x: geo.gutterWidth, y: y + geo.hourHeight / 2))
                    half.addLine(to: CGPoint(x: size.width, y: y + geo.hourHeight / 2))
                    ctx.stroke(half, with: .color(theme.line.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
        }
        .frame(width: gridWidth, height: geo.totalHeight)
        .overlay(alignment: .topLeading) {
            ForEach(1..<24, id: \.self) { h in
                Text(String(format: "%02d:00", h))
                    .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(theme.muted)
                    .frame(width: geo.gutterWidth - 10, alignment: .trailing)
                    .offset(y: geo.y(forMinute: h * 60) - 7)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func dayColumn(index: Int, day: DayKey) -> some View {
        let x = geo.gutterWidth + CGFloat(index) * dayWidth
        ZStack(alignment: .topLeading) {
            Rectangle().fill(theme.accent.opacity(0.045))
                .frame(height: geo.y(forMinute: workEnd - workStart))
                .offset(y: geo.y(forMinute: workStart))
            if targetedDay == day { Rectangle().fill(theme.accent.opacity(0.10)) }
            if index > 0 { Rectangle().fill(theme.line).frame(width: 1) }
            if day == .today() && days.count > 1 {
                Rectangle().fill(theme.accent.opacity(0.06))
            }
        }
        .frame(width: dayWidth, height: geo.totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, coordinateSpace: .named("plannerGrid")) { p in
            guard !isDragging else { return }
            let s = PlannerMath.clampMove(start: PlannerMath.snap(geo.minute(forY: p.y), step: snapStep), length: 30)
            draft = Draft(day: day, start: s, end: s + 30)
            store.selection = []
            renamingId = nil
        }
        .onTapGesture {
            store.selection = []
            draft = nil
            renamingId = nil
            focused = true
        }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("plannerGrid"))
                .onChanged { createChanged(index: index, $0) }
                .onEnded { createEnded(index: index, day: day, $0) })
        .dropDestination(for: String.self) { items, location in
            guard let raw = items.first, raw.hasPrefix(DragPayload.taskPrefix) else { return false }
            let id = String(raw.dropFirst(DragPayload.taskPrefix.count))
            let minute = PlannerMath.snap(geo.minute(forY: location.y), step: snapStep)
            store.schedule(taskId: id, day: day, start: minute)
            return true
        } isTargeted: { targeted in
            if targeted { targetedDay = day } else if targetedDay == day { targetedDay = nil }
        }
        .offset(x: x)
    }

    @ViewBuilder private var pastFade: some View {
        if let i = days.firstIndex(of: .today()) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Rectangle().fill(theme.bg.opacity(0.35))
                    .frame(width: dayWidth, height: geo.y(forMinute: store.nowMinute()))
                    .offset(x: geo.gutterWidth + CGFloat(i) * dayWidth)
            }
            .allowsHitTesting(false)
        }
    }

    /// Overlapping blocks sit on top of each other, each a little to the right of the one under it.
    /// The points depend on the column width, so they are worked out here and not in the layout step.
    private var indentMap: [String: Double] {
        let colW = Double(dayWidth - 9)
        let byId = Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let base = min(150, max(56, colW * 0.45))
        // A one-row block shows only its title, so the block above it moves right by about the title's width.
        let tight: (String) -> Double = { id in
            guard let b = byId[id], b.endMinute - b.startMinute < 25 || geo.y(forMinute: b.endMinute - b.startMinute) < 34
            else { return base }
            return min(colW * 0.5, max(base, 38 + 6 * Double(b.title.count)))
        }
        return PlannerMath.indents(layerMap, far: min(16, max(8, colW * 0.10)), tight: tight, maxIndent: colW * 0.62)
    }

    @ViewBuilder private func blockView(_ block: PlannerBlock, indents: [String: Double]) -> some View {
        let shown = displayed(block)
        if let dayIndex = days.firstIndex(of: shown.day) {
            let layer = shown.day == block.day ? layerMap[block.id] : nil
            let indent = CGFloat(layer == nil ? 0 : indents[block.id] ?? 0)
            let width = max(20, dayWidth - 9 - indent)
            let top = geo.y(forMinute: shown.start)
            let height = max(PlannerGeometry.minBlockHeight, geo.y(forMinute: shown.end - shown.start) - 1)
            let isLive = live?.ids.contains(block.id) == true
            BlockView(
                block: block, start: shown.start, end: shown.end, size: CGSize(width: width, height: height),
                isOverlay: (layer?.depth ?? 0) > 0,
                isSelected: store.selection.contains(block.id), isDragging: isLive,
                isRenaming: renamingId == block.id,
                onTap: { selectBlock(block) },
                onDoubleTap: { selectBlock(block); renamingId = block.id },
                onToggleDone: { if let t = block.taskId { store.toggleDone(taskId: t) } },
                onRename: { store.rename(blockId: block.id, to: $0); renamingId = nil; focused = true },
                onCancelRename: { if renamingId == block.id { renamingId = nil; focused = true } },
                onDrag: { mode, value, ended in blockDrag(block, mode, value, ended) })
            .offset(x: geo.gutterWidth + CGFloat(dayIndex) * dayWidth + 2 + indent, y: top)
            // Later start = on top. Stays between 1 and 9, under the drag (10), the now line and the draft.
            .zIndex(isLive ? 10 : 9 - 8 / Double((layer?.order ?? 0) + 1))
            .contextMenu { blockMenu(block) }
            .animation(isLive ? nil : animation, value: shown.start)
            .animation(isLive ? nil : animation, value: shown.end)
        }
    }

    @ViewBuilder private var createRect: some View {
        if let c = create {
            let s = min(c.anchor, c.current), e = max(c.anchor, c.current)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.accent.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.accent, lineWidth: 1.5))
                .overlay(alignment: .topLeading) {
                    Text(PlannerMath.label(start: s, end: max(e, s + 5)))
                        .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(theme.accent).padding(5)
                }
                .frame(width: dayWidth - 6, height: max(4, geo.y(forMinute: max(e - s, 5))))
                .offset(x: geo.gutterWidth + CGFloat(c.dayIndex) * dayWidth + 2, y: geo.y(forMinute: s))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var draftView: some View {
        if let d = draft, let i = days.firstIndex(of: d.day) {
            let height = max(26, geo.y(forMinute: d.end - d.start))
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(PlannerMath.label(start: d.start, end: d.end))
                        .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(theme.accent)
                    InlineTitleField(
                        initial: "", placeholder: d.asEvent ? "New event" : "New task",
                        onChange: { draft?.text = $0 },
                        onCommit: { text, command in
                            guard var current = draft else { return }
                            current.text = text
                            store.createFromDraft(title: text, day: current.day, start: current.start, end: current.end,
                                                  asEvent: command || current.asEvent)
                            draft = nil
                            focused = true
                        },
                        onCancel: { draft = nil })
                }
                .padding(.horizontal, 9).padding(.vertical, 3)
                .frame(width: dayWidth - 6, height: height, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.accent, lineWidth: 2))
                suggestions(d)
            }
            .offset(x: geo.gutterWidth + CGFloat(i) * dayWidth + 2, y: geo.y(forMinute: d.start))
            .zIndex(20)
        }
    }

    @ViewBuilder private func suggestions(_ d: Draft) -> some View {
        let matches = store.matchingTasks(d.text, on: d.day)
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Schedule existing task").font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.muted).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
                ForEach(matches) { t in
                    Button {
                        store.schedule(taskId: t.id, day: d.day, start: d.start, length: d.end - d.start)
                        draft = nil
                    } label: {
                        Text(t.title).font(.system(size: 12, design: .rounded)).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: max(160, dayWidth - 6))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
    }

    @ViewBuilder private var nowLine: some View {
        if let i = days.firstIndex(of: .today()) {
            TimelineView(.periodic(from: .now, by: 20)) { _ in
                let y = geo.y(forMinute: store.nowMinute())
                HStack(spacing: 0) {
                    Circle().fill(theme.accent2).frame(width: 9, height: 9)
                    Rectangle().fill(theme.accent2).frame(height: 2)
                }
                .frame(width: dayWidth + 4, height: 9)
                .offset(x: geo.gutterWidth + CGFloat(i) * dayWidth - 4, y: y - 4.5)
            }
            .allowsHitTesting(false)
            .zIndex(15)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var liveLabel: some View {
        if let l = live, let orig = l.originals[l.primaryId], let b = blocks.first(where: { $0.id == l.primaryId }) {
            let shown = displayed(b)
            if let i = days.firstIndex(of: shown.day) {
                Text(PlannerMath.label(start: shown.start, end: shown.end))
                    .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(theme.ink))
                    .fixedSize()
                    .offset(x: geo.gutterWidth + CGFloat(i) * dayWidth + 8, y: geo.y(forMinute: shown.start) - 26 + (shown.start < 40 ? 40 : 0))
                    .allowsHitTesting(false)
                    .zIndex(30)
                    .id(orig.id + "label")
            }
        }
    }

    // MARK: Menu

    @ViewBuilder private func blockMenu(_ block: PlannerBlock) -> some View {
        let ids = store.selection.contains(block.id) ? Array(store.selection) : [block.id]
        Menu("Duration") {
            ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { m in
                Button(PlannerMath.duration(m)) { store.setDuration(blockIds: ids, minutes: m) }
            }
        }
        Menu("Colour") {
            ForEach(Theme.blockColorNames, id: \.self) { name in
                Button(name.capitalized) { store.setColor(blockIds: ids, name: name) }
            }
        }
        Divider()
        Button("Duplicate") { store.duplicate(blockIds: ids) }
        Button("Split in Two") { store.split(blockId: block.id) }
        if let t = block.taskId {
            Button(block.isDone ? "Mark Not Done" : "Mark Done") { store.toggleDone(taskId: t) }
        }
        Divider()
        if block.isTaskBlock {
            Button("Unschedule") { store.deleteBlocks(ids, name: "Unschedule") }
        } else {
            Button("Delete Event", role: .destructive) { store.deleteBlocks(ids, name: "Delete Event") }
        }
    }

    // MARK: Data

    private func reload() {
        guard let first = days.first, let last = days.last else { return }
        blocks = store.blocks(for: first...last)
        relayout()
        let ids = Set(blocks.map(\.id))
        if !store.selection.isSubset(of: ids) { store.selection = store.selection.intersection(ids) }
    }

    /// Works out which block sits on which, per day. Runs again when the zoom changes,
    /// because a short block is drawn taller than its length and so covers more minutes.
    private func relayout() {
        var result: [String: Layer] = [:]
        for day in days {
            result.merge(PlannerMath.layoutLayers(blocks.filter { $0.day == day }.map(\.span),
                                                  minLength: geo.minDrawnMinutes,
                                                  tightWithin: geo.tightMinutes)) { a, _ in a }
        }
        layerMap = result
    }

    /// Where a block is drawn. Live drags change it before anything is saved.
    private func displayed(_ b: PlannerBlock) -> (day: DayKey, start: Int, end: Int) {
        guard let l = live, let o = l.originals[b.id] else { return (b.day, b.startMinute, b.endMinute) }
        switch l.mode {
        case .move:
            let s = o.start + l.deltaMinutes
            return (o.day.adding(days: l.deltaDays), s, s + (o.end - o.start))
        case .resizeTop:
            return (o.day, o.start + l.deltaMinutes, o.end)
        case .resizeBottom:
            return (o.day, o.start, o.end + l.deltaMinutes)
        case .create:
            return (o.day, o.start, o.end)
        }
    }

    private func scrollToNow(animated: Bool) {
        let target = max(0, geo.y(forMinute: max(0, store.nowMinute() - 60)))
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.4)) { position.scrollTo(y: target) }
        } else {
            position.scrollTo(y: target)
        }
    }

    private func selectBlock(_ block: PlannerBlock) {
        if NSEvent.modifierFlags.contains(.command) {
            if store.selection.contains(block.id) { store.selection.remove(block.id) } else { store.selection.insert(block.id) }
        } else {
            store.selection = [block.id]
        }
        draft = nil
        focused = true
    }

    // MARK: Dragging a block

    private func blockDrag(_ block: PlannerBlock, _ mode: DragMode, _ v: DragGesture.Value, _ ended: Bool) {
        if ended {
            updatePointer(v)
            refreshLive()
            finishDrag()
            return
        }
        if live == nil {
            let ids: [String]
            if mode == .move, store.selection.contains(block.id) { ids = blocks.filter { store.selection.contains($0.id) }.map(\.id) }
            else { ids = [block.id]; store.selection = [block.id] }
            var originals: [String: BlockEdit] = [:]
            for b in blocks where ids.contains(b.id) {
                originals[b.id] = BlockEdit(id: b.id, day: b.day, start: b.startMinute, end: b.endMinute)
            }
            live = LiveEdit(mode: mode, ids: ids, primaryId: block.id, originals: originals)
            pointer = PointerContext(startX: v.startLocation.x, startY: v.startLocation.y,
                                     lastX: v.location.x, lastY: v.location.y, scrollAtEvent: scrollY)
            draft = nil
            focused = true
            startAutoScroll()
        }
        updatePointer(v)
        refreshLive()
    }

    private func updatePointer(_ v: DragGesture.Value) {
        pointer?.lastX = v.location.x
        pointer?.lastY = v.location.y
        pointer?.scrollAtEvent = scrollY
    }

    private func effectiveY() -> CGFloat {
        guard let p = pointer else { return 0 }
        return p.lastY + (scrollY - p.scrollAtEvent)
    }

    private func currentStep() -> Int { NSEvent.modifierFlags.contains(.option) ? 1 : snapStep }

    private func refreshLive() {
        guard var l = live, let p = pointer, let primary = l.originals[l.primaryId] else { return }
        let step = currentStep()
        let raw = Int(((effectiveY() - p.startY) / geo.hourHeight * 60).rounded())
        switch l.mode {
        case .move:
            let target = PlannerMath.snap(primary.start + raw, step: step)
            let minStart = l.originals.values.map(\.start).min() ?? 0
            let maxEnd = l.originals.values.map(\.end).max() ?? 1440
            l.deltaMinutes = max(-minStart, min(target - primary.start, 1440 - maxEnd))
            if days.count > 1 {
                let indexes = l.originals.values.compactMap { o in days.firstIndex(of: o.day) }
                let rawDays = Int(((p.lastX - p.startX) / dayWidth).rounded())
                let lo = -(indexes.min() ?? 0), hi = days.count - 1 - (indexes.max() ?? 0)
                l.deltaDays = max(lo, min(rawDays, hi))
            }
            let overTray = p.lastX < 0 && blocks.first { $0.id == l.primaryId }?.isTaskBlock == true
            if dropToTray != overTray { dropToTray = overTray }
        case .resizeTop:
            let r = PlannerMath.resizeTop(start: primary.start, end: primary.end, newStart: primary.start + raw, step: step)
            l.deltaMinutes = r.0 - primary.start
        case .resizeBottom:
            let r = PlannerMath.resizeBottom(start: primary.start, end: primary.end, newEnd: primary.end + raw, step: step)
            l.deltaMinutes = r.1 - primary.end
        case .create:
            break
        }
        if l.deltaMinutes != live?.deltaMinutes { haptic() }
        live = l
    }

    private func finishDrag() {
        defer {
            live = nil
            pointer = nil
            autoScroll?.cancel()
            if dropToTray { dropToTray = false }
        }
        guard let l = live else { return }
        if dropToTray, l.mode == .move {
            store.deleteBlocks(l.ids, name: "Unschedule")
            return
        }
        var edits: [BlockEdit] = []
        for id in l.ids {
            guard let b = blocks.first(where: { $0.id == id }) else { continue }
            let s = displayed(b)
            edits.append(BlockEdit(id: id, day: s.day, start: s.start, end: s.end))
        }
        edits.sort { $0.id == l.primaryId && $1.id != l.primaryId }
        let name = l.mode == .move ? "Move Block" : "Resize Block"
        store.applyEdits(edits, ripple: NSEvent.modifierFlags.contains(.shift), name: name)
    }

    // MARK: Dragging on empty time

    private func createChanged(index: Int, _ v: DragGesture.Value) {
        if create == nil {
            let anchor = PlannerMath.snap(geo.minute(forY: v.startLocation.y), step: currentStep())
            create = CreateDrag(dayIndex: index, anchor: anchor, current: anchor)
            pointer = PointerContext(startX: v.startLocation.x, startY: v.startLocation.y,
                                     lastX: v.location.x, lastY: v.location.y, scrollAtEvent: scrollY)
            draft = nil
            store.selection = []
            focused = true
            startAutoScroll()
        }
        updatePointer(v)
        refreshCreate()
    }

    private func refreshCreate() {
        guard var c = create else { return }
        let minute = PlannerMath.snap(geo.minute(forY: effectiveY()), step: currentStep())
        c.current = max(0, min(1440, minute))
        if c.current != create?.current { haptic() }
        create = c
    }

    private func createEnded(index: Int, day: DayKey, _ v: DragGesture.Value) {
        updatePointer(v)
        refreshCreate()
        defer { create = nil; pointer = nil; autoScroll?.cancel() }
        guard let c = create else { return }
        var s = min(c.anchor, c.current), e = max(c.anchor, c.current)
        if e - s < 5 { e = s + 30 }
        if e > 1440 { e = 1440; s = min(s, 1435) }
        draft = Draft(day: day, start: s, end: e, asEvent: NSEvent.modifierFlags.contains(.command))
    }

    // MARK: Auto-scroll and haptics

    private func startAutoScroll() {
        autoScroll?.cancel()
        autoScroll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let p = pointer else { continue }
                let viewportY = p.lastY - p.scrollAtEvent
                var speed: CGFloat = 0
                if viewportY < 40 { speed = -min(24, (40 - viewportY) / 40 * 24) }
                else if viewportY > viewportH - 40 { speed = min(24, (viewportY - (viewportH - 40)) / 40 * 24) }
                guard speed != 0 else { continue }
                let maxY = max(0, geo.totalHeight - viewportH)
                let next = max(0, min(maxY, scrollY + speed))
                guard next != scrollY else { continue }
                scrollY = next
                position.scrollTo(y: next)
                if live != nil { refreshLive() }
                if create != nil { refreshCreate() }
            }
        }
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard draft == nil, renamingId == nil else { return .ignored }
        let selected = blocks.filter { store.selection.contains($0.id) }
        let cmd = press.modifiers.contains(.command), shift = press.modifiers.contains(.shift)
        let option = press.modifiers.contains(.option)

        if cmd {
            switch press.characters {
            case "d": if !selected.isEmpty { store.duplicate(blockIds: selected.map(\.id)); return .handled }
            case "t": scrollToNow(animated: true); return .handled
            case "=", "+": geo.hourHeight = min(PlannerGeometry.zoomRange.upperBound, geo.hourHeight * 1.2); return .handled
            case "-": geo.hourHeight = max(PlannerGeometry.zoomRange.lowerBound, geo.hourHeight / 1.2); return .handled
            default: break
            }
            return .ignored
        }

        switch press.key {
        case .escape:
            store.selection = []
            return .handled
        case .upArrow, .downArrow:
            guard !selected.isEmpty else { return .ignored }
            let amount = (option ? 5 : 15) * (press.key == .upArrow ? -1 : 1)
            var edits: [BlockEdit] = []
            if shift {
                // Shorter / longer: the end edge moves.
                for b in selected {
                    let r = PlannerMath.resizeBottom(start: b.startMinute, end: b.endMinute, newEnd: b.endMinute + amount, step: 1)
                    edits.append(BlockEdit(id: b.id, day: b.day, start: r.0, end: r.1))
                }
                store.applyEdits(edits, ripple: false, name: "Resize Block")
            } else {
                let minStart = selected.map(\.startMinute).min() ?? 0
                let maxEnd = selected.map(\.endMinute).max() ?? 1440
                let d = max(-minStart, min(amount, 1440 - maxEnd))
                for b in selected {
                    edits.append(BlockEdit(id: b.id, day: b.day, start: b.startMinute + d, end: b.endMinute + d))
                }
                store.applyEdits(edits, ripple: false, name: "Move Block")
            }
            return .handled
        case .leftArrow, .rightArrow:
            guard !selected.isEmpty else { return .ignored }
            let step = press.key == .leftArrow ? -1 : 1
            let edits = selected.map { BlockEdit(id: $0.id, day: $0.day.adding(days: step), start: $0.startMinute, end: $0.endMinute) }
            store.applyEdits(edits, ripple: false, name: "Move Block")
            if days.count == 1 { store.selectedDay = store.selectedDay.adding(days: step) }
            return .handled
        case .return:
            guard let first = selected.first else { return .ignored }
            renamingId = first.id
            return .handled
        case .space:
            guard !selected.isEmpty else { return .ignored }
            for b in selected { if let t = b.taskId { store.toggleDone(taskId: t) } }
            return .handled
        case .delete, .deleteForward:
            guard !selected.isEmpty else { return .ignored }
            store.deleteBlocks(selected.map(\.id), name: selected.allSatisfy(\.isTaskBlock) ? "Unschedule" : "Delete Block")
            return .handled
        default:
            if press.characters == "n", press.modifiers.isEmpty {
                let day = days.contains(.today()) ? DayKey.today() : (days.first ?? .today())
                if let slot = store.nextFreeSlot(day: day, length: 30, workStart: workStart, step: snapStep) {
                    draft = Draft(day: day, start: slot, end: slot + 30)
                    store.selection = []
                    return .handled
                }
            }
            return .ignored
        }
    }
}
