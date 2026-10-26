import SwiftUI
import UniformTypeIdentifiers
import OpenHabitCore

struct DaySelection: Identifiable {
    let habitID: UUID
    let date: String
    var id: String { Dataset.key(habitID, date) }
}
enum AppSheet: Identifiable {
    case settings, create, edit(Habit), day(DaySelection)
    var id: String {
        switch self { case .settings: "settings"; case .create: "create"; case .edit(let habit): "edit-\(habit.id)"; case .day(let day): day.id }
    }
}

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("overviewCompact") private var compact = false
    @State private var sheet: AppSheet?
    @State private var path: [UUID] = []
    @State private var dragging: UUID?
    /// Card order while a drag is in progress, saved once when the drop finishes.
    @State private var draftOrder: [UUID]?
    /// Reorder mode: cards show drag handles and ignore taps, like the Home Screen's edit mode.
    @State private var reordering = false
    @State private var pendingCreatedHabitID: UUID?
    @State private var layoutSwitcherVisible = true
    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroll in
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(timeline.date.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                                .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                            Text("A little, every day.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        }.padding(.top, 10).id("overview-top")
                        if !model.data.settings.examplesDismissed && !model.data.habits.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "leaf").foregroundStyle(.green).font(.title3)
                                Text("A few habits to make your own. Edit, reorder, archive, or delete these examples.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button { model.setSettings { $0.examplesDismissed = true } } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44) }
                                    .accessibilityLabel("Dismiss example habits message")
                            }.padding(16).background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                        }
                        if model.loading && model.data.habits.isEmpty { ProgressView("Checking your local and iCloud data…").frame(maxWidth: .infinity).padding(30) }
                        else if model.data.active.isEmpty {
                            ContentUnavailableView {
                                Label("Room for a new habit", systemImage: "leaf")
                            } description: { Text("Start small. Choose something you’d like to do every day.") }
                            actions: { Button("Create a Habit") { sheet = .create }.buttonStyle(.borderedProminent) }
                        }
                        GlassGroup {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: !typeSize.isAccessibilitySize && (compact || sizeClass == .regular) ? 2 : 1), spacing: 16) {
                            ForEach(displayedHabits) { habit in
                                habitCard(habit, now: timeline.date)
                                .transition(habitTransition)
                                .onDrag { commitDraftOrder(); dragging = habit.id; UIImpactFeedbackGenerator(style: .medium).impactOccurred(); return NSItemProvider(object: habit.id.uuidString as NSString) }
                                .onDrop(of: [.text], delegate: HabitDrop(target: habit.id, dragging: $dragging, draftOrder: $draftOrder, commit: commitDraftOrder, model: model))
                                .contextMenu(menuItems: { if !reordering { quickMenu(habit) } })
                                .accessibilityAction(named: "Move earlier") { move(habit.id, offset: -1) }
                                .accessibilityAction(named: "Move later") { move(habit.id, offset: 1) }
                            }
                        }
                        }
                        Text("Small steps. Your own pace.").font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.padding(.horizontal, 20).padding(.bottom, 92).frame(maxWidth: compact && !typeSize.isAccessibilitySize ? 600 : 1100)
                        .frame(maxWidth: .infinity)
                        // A drop in a gap between cards still ends the reorder.
                        .onDrop(of: [.text], isTargeted: nil) { _ in dragging = nil; commitDraftOrder(); return true }
                }
                .modifier(OverviewScrollVisibility(visible: $layoutSwitcherVisible))
                .background(Color(.systemGroupedBackground))
            }
            .overlay(alignment: .bottom) {
                if layoutSwitcherVisible && !reordering {
                    OverviewLayoutSwitcher(compact: $compact)
                        .padding(.bottom, 8)
                        .transition(reduceMotion ? .opacity : .offset(y: 28).combined(with: .opacity)
                            .combined(with: .scale(scale: 0.94, anchor: .bottom)))
                }
            }
            .animation(reduceMotion ? .linear(duration: 0.15) : .smooth(duration: 0.24), value: layoutSwitcherVisible)
            .onChange(of: path) { _, _ in layoutSwitcherVisible = true; commitDraftOrder() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { commitDraftOrder() } }
            .onChange(of: model.data.active.count) { _, count in if count < 2 { setReordering(false) } }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if reordering {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { setReordering(false) }.accessibilityIdentifier("done-reordering")
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { sheet = .settings } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Add Habit", systemImage: "plus") { sheet = .create }.accessibilityIdentifier("add-habit") }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                HabitDetailView(habitID: id, onDelete: deleteFromDetail)
            }
            .sheet(item: $sheet, onDismiss: {
                guard pendingCreatedHabitID != nil else { return }
                scroll.scrollTo("overview-top", anchor: .top)
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
                    pendingCreatedHabitID = nil
                }
            }) { destination in
                switch destination {
                case .settings: SettingsView()
                case .create: HabitEditor(habit: Habit(), isNew: true, onCreated: { pendingCreatedHabitID = $0 })
                case .edit(let habit): HabitEditor(habit: habit, isNew: false)
                case .day(let day): DayEditor(selection: day, data: model.data)
                }
            }
            .sheet(isPresented: Binding(
                get: { model.preparingShare || model.pendingJoin != nil },
                set: { if !$0 { model.pendingJoin = nil } }
            )) {
                Group {
                    if model.preparingShare {
                        ProgressView("Opening invitation…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let offer = model.pendingJoin {
                        SharedHabitJoinView(offer: offer)
                    }
                }
                .interactiveDismissDisabled()
            }
            .onOpenURL { url in
                guard url.scheme == "openhabit", url.host == "habit", let id = UUID(uuidString: url.lastPathComponent) else { return }
                model.reload(); path = [id]
            }
            }
        }
    }
    @ViewBuilder private func habitCard(_ habit: Habit, now: Date) -> some View {
        let memberCount = model.sharedHabit(for: habit.id)?.snapshot.members.count
        if compact && !typeSize.isAccessibilitySize {
            CompactHabitCard(habit: habit, data: model.data, now: now, sharedMemberCount: memberCount,
                             reordering: reordering,
                             open: { if !reordering { path.append(habit.id) } },
                             complete: { model.update { try $0.toggle(habit.id) } })
        } else {
            HabitCard(habit: habit, data: model.data, now: now, sharedMemberCount: memberCount,
                      reordering: reordering,
                      open: { if !reordering { path.append(habit.id) } },
                      complete: { model.update { try $0.toggle(habit.id) } })
        }
    }
    private var habitTransition: AnyTransition {
        .asymmetric(insertion: reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity), removal: .opacity)
    }
    @ViewBuilder private func quickMenu(_ habit: Habit) -> some View {
        if let counter = habit.counter {
            let today = LocalDay.string()
            Button("Undo \(counter.step)\(counter.unit.isEmpty ? "" : " \(counter.unit)")", systemImage: "minus.circle") {
                model.update { try $0.remove(habit.id, day: today, amount: counter.step) }
            }.disabled(model.data.day(habit.id, today).count == 0)
            Button("Set today’s amount", systemImage: "number") { sheet = .day(DaySelection(habitID: habit.id, date: today)) }
            Divider()
        }
        if habit.counter == nil { markYesterdayComplete(habit) }
        Button("Add today’s note", systemImage: "note.text") { sheet = .day(DaySelection(habitID: habit.id, date: LocalDay.string())) }
        if model.sharedHabit(for: habit.id)?.membership.role != .member {
            Button("Edit Habit", systemImage: "slider.horizontal.3") { sheet = .edit(habit) }
        }
        if model.data.active.count > 1 {
            Divider()
            Button("Reorder Habits", systemImage: "arrow.up.arrow.down") { setReordering(true) }
        }
    }
    private func markYesterdayComplete(_ habit: Habit) -> some View {
        Button("Mark yesterday complete", systemImage: "clock.arrow.circlepath") {
            let day = LocalDay.string(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
            let previousCount = model.data.day(habit.id, day).count
            model.update { try $0.setCount(habit.id, day: day, count: habit.target) }
            if model.error == nil && previousCount < habit.target {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
            }
        }
    }
    private func setReordering(_ value: Bool) {
        if !value { commitDraftOrder() }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { reordering = value }
    }
    private func move(_ id: UUID, offset: Int) {
        var ids = model.data.habits.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset); model.update { $0.append(.order(ids)) }
    }
    private var displayedHabits: [Habit] {
        let habits = model.data.active.filter { $0.id != pendingCreatedHabitID }
        guard let draftOrder else { return habits }
        let positions = Dictionary(draftOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return habits.sorted { (positions[$0.id] ?? .max) < (positions[$1.id] ?? .max) }
    }
    private func commitDraftOrder() {
        guard let ids = draftOrder else { return }
        draftOrder = nil
        if ids != model.data.habits.map(\.id) { model.update { $0.append(.order(ids)) } }
    }
    private func delete(_ habit: Habit) {
        withAnimation(reduceMotion ? nil : .smooth) { model.delete(habit.id) }
    }
    private func deleteFromDetail(_ habit: Habit) {
        withAnimation(reduceMotion ? nil : .smooth, completionCriteria: .logicallyComplete) {
            path.removeAll { $0 == habit.id }
        } completion: {
            delete(habit)
        }
    }
}

/// Observe actual scrolling, so switching layouts or resizing cannot hide the control.
private struct OverviewScrollVisibility: ViewModifier {
    @Binding var visible: Bool
    @State private var scrolling = false
    @State private var previousTranslation: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollPhaseChange { _, phase in
                    scrolling = phase == .interacting || phase == .decelerating
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    min(max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                        max(0, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom))
                } action: { old, new in
                    guard scrolling else { return }
                    if new <= 2 { visible = true }
                    else if new - old > 0.5 { visible = false }
                    else if old - new > 1.5 { visible = true }
                }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let delta = value.translation.height - previousTranslation
                        if delta < -1 { visible = false }
                        else if delta > 1 { visible = true }
                        previousTranslation = value.translation.height
                    }
                    .onEnded { _ in previousTranslation = 0 }
            )
        }
    }
}

struct OverviewLayoutSwitcher: View {
    @Binding var compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                picker.glassEffect(.regular, in: .capsule)
            } else {
                picker.background(.regularMaterial, in: Capsule())
            }
        }
        .sensoryFeedback(.selection, trigger: compact)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.77), value: compact)
    }

    private var picker: some View {
        Picker("Habit layout", selection: $compact) {
            Image(systemName: "rectangle.grid.1x2").accessibilityLabel("Details").tag(false)
            Image(systemName: "square.grid.2x2").accessibilityLabel("Compact").tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("overview-layout")
        .frame(width: 152).padding(8)
    }
}

struct HabitCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let habit: Habit
    let data: Dataset
    let now: Date
    let sharedMemberCount: Int?
    var reordering = false
    let open: () -> Void
    let complete: () -> Void
    @ScaledMetric(relativeTo: .caption) private var historyLabelFontSize: CGFloat = 12

    private var historyLeadingInset: CGFloat {
        LabeledHistoryGrid.leadingInset(fontSize: historyLabelFontSize, data: data)
    }

    private var hasDescription: Bool { !habit.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasSupportingText: Bool { hasDescription || habit.streakGoal != nil || sharedMemberCount != nil || habit.counter != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: hasSupportingText ? 18 : 8) {
            HStack(alignment: .top, spacing: 14) {
                Button(action: open) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(habit.emoji).font(.system(size: 26))
                            .frame(width: historyLeadingInset - 8)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(habit.name).font(.system(.headline, design: .rounded)).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            if hasDescription {
                                Text(habit.detail).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                            }
                            if habit.counter != nil {
                                Text("Today: \(habit.progressText(data.day(habit.id, LocalDay.string(now)).count))")
                                    .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(habit.tint)
                                    .contentTransition(.numericText())
                            }
                            if habit.streakGoal != nil || sharedMemberCount != nil {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 8) { badges }.fixedSize(horizontal: true, vertical: false)
                                    VStack(alignment: .leading, spacing: 6) { badges }
                                }
                            }
                        }.padding(.top, 3).frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Open Habit Detail")
                if reordering {
                    ReorderHandle(size: 48)
                } else {
                    CompletionButton(habit: habit, count: data.day(habit.id, LocalDay.string(now)).count,
                                     action: complete, alignment: .trailing)
                }
            }
            Button(action: open) {
                // Counter Habits trade months of history for tiles large enough to read their amounts.
                LabeledHistoryGrid(habit: habit, data: data, tileSide: habit.counter == nil ? 11 : 16, end: now)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("View \(habit.name) history")
                .accessibilityHint("Open Habit Detail")
                .accessibilityIdentifier("history-\(habit.id.uuidString)")
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(habit.tint.opacity(0.12), lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .transition(.blurReplace)
    }

    @ViewBuilder private var badges: some View {
        if let goal = habit.streakGoal {
            let streak = data.currentStreak(for: habit, asOf: now)
            let unit = goal.period == .daily
                ? (streak == 1 ? "day" : "days")
                : (streak == 1 ? "week" : "weeks")
            Label("\(streak) \(unit)", systemImage: "flame.fill")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(habit.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(habit.tint.opacity(0.12), in: Capsule())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Current streak: \(streak) \(unit)")
        }
        if let sharedMemberCount {
            Label("\(sharedMemberCount) \(sharedMemberCount == 1 ? "Member" : "Members")", systemImage: "person.2.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shown in place of the Completion Button while reordering, so the card reads as movable.
private struct ReorderHandle: View {
    let size: CGFloat
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: max(44, size + 8), height: max(44, size + 8), alignment: .trailing)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .accessibilityHidden(true)
    }
}

private struct HabitDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    @Binding var draftOrder: [UUID]?
    let commit: () -> Void
    let model: AppModel
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        var ids = draftOrder ?? model.data.habits.map(\.id)
        guard let from = ids.firstIndex(of: dragging), let to = ids.firstIndex(of: target) else { return }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.snappy) { draftOrder = ids }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; commit(); return true }
}

/// Geometry shared by every Compact Habit Card, independent of its content.
struct CompactHabitCardLayout {
    let contentWidth: CGFloat
    let weeks: Int
    let gridHeight: CGFloat
    let sectionGap: CGFloat

    init(side: CGFloat) {
        contentWidth = max(0, side - 28)
        let availableGridHeight = max(1, contentWidth - 44 - 8)
        weeks = max(11, Int(ceil(7 * (contentWidth + 3) / (availableGridHeight + 3))))
        let tileSide = max(0, (contentWidth - CGFloat(weeks - 1) * 3) / CGFloat(weeks))
        gridHeight = tileSide * 7 + 18
        sectionGap = max(0, contentWidth - 44 - gridHeight)
    }
}

struct CompactHabitCard: View {
    @Environment(\.counterScales) private var counterScales
    let habit: Habit
    let data: Dataset
    let now: Date
    let sharedMemberCount: Int?
    var reordering = false
    let open: () -> Void
    let complete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let layout = CompactHabitCardLayout(side: geometry.size.width)

            VStack(alignment: .leading, spacing: layout.sectionGap) {
                cardHeader(habit).frame(width: layout.contentWidth, height: 44)
                Button(action: open) {
                    history(habit, weeks: layout.weeks)
                        .frame(width: layout.contentWidth, height: layout.gridHeight)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("View \(habit.name) history")
                    .accessibilityHint("Open Habit Detail")
                    .accessibilityIdentifier("history-\(habit.id.uuidString)")
            }
            .padding(14)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .fill(habit.tint.opacity(0.08)).allowsHitTesting(false)
            }
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(habit.tint.opacity(0.22), lineWidth: 1) }
        }.aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 26))
    }

    private func cardHeader(_ habit: Habit) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(habit.emoji).font(.system(size: 18))
                        if let sharedMemberCount {
                            Image(systemName: "person.2.fill").font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Shared Habit, \(sharedMemberCount) Members")
                        }
                        if habit.streakGoal != nil {
                            streak(habit)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(habit.tint.opacity(0.12), in: Capsule())
                        }
                    }.frame(height: 20, alignment: .leading)
                    Text(habit.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(height: 18, alignment: .leading)
                        .overlay(alignment: .topLeading) {
                            // Compact tiles are too small for amounts, so today's amount rides under the name.
                            if habit.counter != nil {
                                Text("Today \(Counter.compact(data.day(habit.id, LocalDay.string(now)).count))")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(habit.tint).fixedSize()
                                    .offset(y: 16)
                            }
                        }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHint("Open Habit Detail")
            if reordering {
                ReorderHandle(size: 32)
            } else {
                CompletionButton(habit: habit, count: data.day(habit.id, LocalDay.string(now)).count,
                                 action: complete, alignment: .trailing, size: 32)
            }
        }
    }

    private func streak(_ habit: Habit) -> some View {
        let value = data.currentStreak(for: habit, asOf: now)
        let weekly = habit.streakGoal?.period == .weekly
        let unit = weekly ? (value == 1 ? "week" : "weeks") : (value == 1 ? "day" : "days")
        return Label("\(value) \(unit)", systemImage: "flame.fill")
            .foregroundStyle(value == 0 ? Color.secondary : habit.tint)
            .lineLimit(1).minimumScaleFactor(0.75)
            .accessibilityLabel("Current Streak, \(value) \(unit)")
    }

    private func history(_ habit: Habit, weeks: Int) -> some View {
        Canvas { context, size in
            var calendar = Calendar(identifier: .gregorian)
            switch data.settings.weekStart {
            case .system: calendar.firstWeekday = Calendar.current.firstWeekday
            case .monday: calendar.firstWeekday = 2
            case .sunday: calendar.firstWeekday = 1
            }
            let start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let side = max(0, (size.width - CGFloat(weeks - 1) * 3) / CGFloat(weeks))
            let reference = counterScales[habit.id]?.reference
            for column in 0..<weeks {
                for row in 0..<7 {
                    let offset = (column - weeks + 1) * 7 + row
                    let date = calendar.date(byAdding: .day, value: offset, to: start)!
                    let key = LocalDay.string(date)
                    let day = key > LocalDay.string(now) ? HabitDay() : data.day(habit.id, key)
                    let rect = CGRect(x: CGFloat(column) * (side + 3), y: CGFloat(row) * (side + 3), width: side, height: side)
                    let path = Path(roundedRect: rect, cornerRadius: side * 0.22)
                    let intensity = habit.intensity(day.count, reference: reference)
                    context.fill(path, with: .color(habit.tint.opacity(day.count == 0 ? 0.10 : 0.25 + 0.75 * intensity)))
                    if habit.counter != nil {
                        TileAmount.draw(day.count, in: rect, intensity: intensity, color: habit.tint, context: context)
                    }
                    if !day.note.isEmpty {
                        context.fill(Path(ellipseIn: CGRect(x: rect.maxX - 2, y: rect.minY - 1, width: 3, height: 3)),
                                     with: .color(.primary))
                    }
                    if key == LocalDay.string(now) {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: side * 0.2),
                                       with: .color(.primary.opacity(0.8)), lineWidth: 1)
                    }
                }
            }
        }.accessibilityHidden(true)
    }

}
