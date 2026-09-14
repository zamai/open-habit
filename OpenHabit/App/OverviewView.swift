import SwiftUI
import UniformTypeIdentifiers
import OpenHabitCore

struct DaySelection: Identifiable {
    let habitID: UUID
    let date: String
    var id: String { Dataset.key(habitID, date) }
}
enum AppSheet: Identifiable {
    case settings, create, edit(Habit), day(DaySelection), share(Habit)
    var id: String {
        switch self { case .settings: "settings"; case .create: "create"; case .edit(let habit): "edit-\(habit.id)"; case .day(let day): day.id; case .share(let habit): "share-\(habit.id)" }
    }
}

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: AppSheet?
    @State private var path: [UUID] = []
    @State private var deleting: Habit?
    @State private var dragging: UUID?
    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(timeline.date.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                                .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                            Text("A little, every day.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        }.padding(.top, 10)
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
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: sizeClass == .regular && !typeSize.isAccessibilitySize ? 2 : 1), spacing: 16) {
                            ForEach(model.data.active) { habit in
                                HabitCard(habit: habit, data: model.data, now: timeline.date,
                                          sharedMemberCount: model.sharedHabit(for: habit.id)?.snapshot.members.count,
                                          open: { path.append(habit.id) },
                                          complete: { model.update { try $0.toggle(habit.id) } },
                                          quickMenu: { quickMenu(habit) })
                                .onDrag { dragging = habit.id; UIImpactFeedbackGenerator(style: .medium).impactOccurred(); return NSItemProvider(object: habit.id.uuidString as NSString) }
                                .onDrop(of: [.text], delegate: HabitDrop(target: habit.id, dragging: $dragging, model: model))
                                .accessibilityAction(named: "Move earlier") { move(habit.id, offset: -1) }
                                .accessibilityAction(named: "Move later") { move(habit.id, offset: 1) }
                            }
                        }
                        }
                        Text("Small steps. Your own pace.").font(.footnote).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.padding(.horizontal, 20).padding(.bottom, 24).frame(maxWidth: 1100)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Open Habit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { sheet = .settings } }
                ToolbarItem(placement: .topBarTrailing) { Button("Add Habit", systemImage: "plus") { sheet = .create }.accessibilityIdentifier("add-habit") }
            }
            .navigationDestination(for: UUID.self) { id in
                HabitDetailView(habitID: id, onDelete: deleteFromDetail)
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .settings: SettingsView()
                case .create: HabitEditor(habit: Habit(), isNew: true)
                case .edit(let habit): HabitEditor(habit: habit, isNew: false)
                case .day(let day): DayEditor(selection: day, data: model.data)
                case .share(let habit): SharedHabitSetupView(habit: habit)
                }
            }
            .sheet(item: Binding(get: { model.pendingJoin }, set: { model.pendingJoin = $0 })) { offer in
                SharedHabitJoinView(offer: offer).interactiveDismissDisabled()
            }
            .alert("Permanently delete \(deleting?.name ?? "Habit")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete", role: .destructive) { if let habit = deleting { delete(habit) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("All Completions and Day Notes will also be deleted from your synchronized devices.") }
            .onOpenURL { url in
                guard url.scheme == "openhabit", url.host == "habit", let id = UUID(uuidString: url.lastPathComponent) else { return }
                model.reload(); path = [id]
            }
        }
    }
    @ViewBuilder private func quickMenu(_ habit: Habit) -> some View {
        Button("Undo latest Completion today", systemImage: "arrow.uturn.backward") { model.update { try $0.remove(habit.id, day: LocalDay.string()) } }
        Button("Mark today complete", systemImage: "checkmark.circle") { model.update { try $0.setCount(habit.id, day: LocalDay.string(), count: habit.target) } }
        Button("Mark yesterday complete", systemImage: "clock.arrow.circlepath") { model.update { try $0.setCount(habit.id, day: LocalDay.string(Calendar.current.date(byAdding: .day, value: -1, to: Date())!), count: habit.target) } }
        Button("Edit today’s Habit Day", systemImage: "calendar") { sheet = .day(DaySelection(habitID: habit.id, date: LocalDay.string())) }
        if model.sharedHabit(for: habit.id)?.membership.role != .member {
            Button("Edit Habit", systemImage: "pencil") { sheet = .edit(habit) }
        }
        if model.sharedHabit(for: habit.id) == nil {
            Button("Archive Habit", systemImage: "archivebox") { model.update { $0.append(.archive(habit.id, true)) } }
            Button("Delete Habit", systemImage: "trash", role: .destructive) { deleting = habit }
        }
    }
    private func move(_ id: UUID, offset: Int) {
        var ids = model.data.habits.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset); model.update { $0.append(.order(ids)) }
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

private struct HabitCard<Menu: View>: View {
    let habit: Habit
    let data: Dataset
    let now: Date
    let sharedMemberCount: Int?
    let open: () -> Void
    let complete: () -> Void
    @ViewBuilder let quickMenu: () -> Menu
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Button(action: open) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(habit.emoji).font(.system(size: 30)).frame(width: 44, height: 48)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(habit.name).font(.system(.headline, design: .rounded)).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Text(habit.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if habit.streakGoal != nil || sharedMemberCount != nil {
                                HStack(spacing: 8) {
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
                                            .fixedSize()
                                            .accessibilityLabel("Current streak: \(streak) \(unit)")
                                    }
                                    if let sharedMemberCount {
                                        Label("\(sharedMemberCount) \(sharedMemberCount == 1 ? "Member" : "Members")", systemImage: "person.2.fill")
                                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                            .fixedSize()
                                    }
                                }
                            }
                        }.padding(.top, 3).frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Open Habit Detail")
                CompletionButton(habit: habit, count: data.day(habit.id, LocalDay.string(now)).count, action: complete).contextMenu { quickMenu() }
            }
            Button(action: open) {
                LabeledHistoryGrid(habit: habit, data: data, end: now)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }.buttonStyle(.plain).accessibilityElement(children: .ignore).accessibilityLabel("View \(habit.name) history")
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(habit.tint.opacity(0.12), lineWidth: 1) }
        .transition(.blurReplace)
    }
}

private struct HabitDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let model: AppModel
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        var ids = model.data.habits.map(\.id)
        guard let from = ids.firstIndex(of: dragging), let to = ids.firstIndex(of: target) else { return }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.snappy) { model.update { $0.append(.order(ids)) } }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
