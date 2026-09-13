import SwiftUI
import OpenHabitCore

struct HabitDetailView: View {
    @Environment(AppModel.self) private var model
    let habitID: UUID
    @State private var selected = LocalDay.string()
    @State private var month = Date()
    @State private var sheet: AppSheet?
    @State private var noteDraft = ""
    @FocusState private var noteFocused: Bool
    var body: some View {
        Group {
            if let habit = model.data.habit(habitID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 16) {
                                Text(habit.emoji).font(.system(size: 56)).frame(width: 64)
                                Text(habit.name).font(.system(.largeTitle, design: .rounded, weight: .bold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !habit.detail.isEmpty { Text(habit.detail).foregroundStyle(.secondary) }
                            if habit.archived { Label("Archived Habit", systemImage: "archivebox").font(.subheadline).foregroundStyle(.secondary) }
                            if let state = model.sharedHabit(for: habit.id) {
                                Label("\(state.snapshot.members.count) \(state.snapshot.members.count == 1 ? "Member" : "Members")", systemImage: "person.2.fill").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        metrics(for: habit)
                        if let state = model.sharedHabit(for: habit.id) {
                            SharedHabitMembersSection(state: state)
                        } else if !habit.archived {
                            if #available(iOS 18.0, *) {
                                Button("Share Habit", systemImage: "person.2.badge.plus") { sheet = .share(habit) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            ScrollView(.horizontal) {
                                HistoryGrid(habit: habit, data: model.data, weeks: 53, onSelect: { selected = $0 }, onEdit: { sheet = .day(DaySelection(habitID: habitID, date: $0)) })
                                    .frame(width: 1_035)
                            }.defaultScrollAnchor(.trailing)
                            HStack(spacing: 6) {
                                Text("Empty"); ForEach([0, 1, 3], id: \.self) { count in DayTile(day: HabitDay(count: count), target: 3, color: habit.tint, today: false).frame(width: 13, height: 13) }; Text("Complete")
                                Spacer(); Image(systemName: "circle.fill").font(.system(size: 4)); Text("Day Note")
                            }.font(.caption2).foregroundStyle(.secondary)
                        }
                        MonthCalendar(habit: habit, data: model.data, month: $month, selected: $selected,
                                      complete: { date in
                                          selected = date
                                          model.update { try $0.toggle(habitID, day: date) }
                                      },
                                      edit: { date in sheet = .day(DaySelection(habitID: habitID, date: date)) })
                        selectedDay(habit)
                    }.padding(22).frame(maxWidth: 850).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.sync() }
                .background(Color(.systemGroupedBackground))
                    .toolbar {
                        if model.sharedHabit(for: habit.id)?.membership.role != .member {
                            ToolbarItem(placement: .topBarTrailing) { Button("Edit Habit", systemImage: "slider.horizontal.3") { sheet = .edit(habit) } }
                        }
                    }
            } else { ContentUnavailableView("Habit unavailable", systemImage: "leaf", description: Text("This Habit may have been deleted from another device.")) }
        }
        .onAppear { loadSelectedNote() }
        .task(id: habitID) {
            if model.sharedHabit(for: habitID) != nil { await model.sync() }
        }
        .onChange(of: selected) { _, _ in
            noteFocused = false
            loadSelectedNote()
        }
        .onChange(of: model.data.day(habitID, selected).note) { oldValue, newValue in
            if !noteFocused && noteDraft == oldValue { noteDraft = newValue }
        }
        .navigationTitle("Habit Detail").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .edit(let habit): HabitEditor(habit: habit, isNew: false)
            case .day(let day): DayEditor(selection: day, data: model.data)
            case .create: HabitEditor(habit: Habit(), isNew: true)
            case .settings: SettingsView()
            case .share(let habit): SharedHabitSetupView(habit: habit)
            }
        }
    }
    private func selectedDay(_ habit: Habit) -> some View {
        let day = model.data.day(habitID, selected)
        let future = selected > LocalDay.string()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalDay.date(selected)?.formatted(date: .abbreviated, time: .omitted) ?? selected).font(.headline)
                Spacer()
                if !future {
                    Button("Save Note", systemImage: "checkmark") { saveSelectedNote() }
                        .disabled(noteDraft == day.note)
                }
            }
            if future { Text("Future dates are read-only.").foregroundStyle(.secondary) }
            else {
                TextField("Add a Day Note", text: $noteDraft, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($noteFocused)
                    .onChange(of: noteDraft) { _, value in noteDraft = String(value.prefix(500)) }
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Day Note")
                Text("\(noteDraft.count) / 500").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private func metrics(for habit: Habit) -> some View {
        let streak = model.data.currentStreak(for: habit)
        let monthTotal = model.data.completionTotal(for: habit.id, inMonthContaining: month)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            HabitMetric(value: "\(habit.target)", label: "Daily Target", color: habit.tint)
            HabitMetric(value: "\(monthTotal)", label: "\(month.formatted(.dateTime.month(.abbreviated))) Total", color: habit.tint)
            if let goal = habit.streakGoal {
                let weeklyProgress = model.data.completedDays(for: habit, inWeekContaining: Date())
                let label = goal.period == .daily ? "Day Streak" : "Week Streak\n\(weeklyProgress) / \(goal.target) this week"
                HabitMetric(value: "\(streak)", label: label, color: habit.tint)
            }
        }
    }

    private func loadSelectedNote() {
        noteDraft = model.data.day(habitID, selected).note
    }

    private func saveSelectedNote() {
        model.update { try $0.setNote(habitID, day: selected, note: noteDraft) }
        if model.error == nil { noteFocused = false }
    }
}

private struct HabitMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct MonthCalendar: View {
    let habit: Habit
    let data: Dataset
    @Binding var month: Date
    @Binding var selected: String
    let complete: (String) -> Void
    let edit: (String) -> Void
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        switch data.settings.weekStart { case .system: calendar.firstWeekday = Calendar.current.firstWeekday; case .monday: calendar.firstWeekday = 2; case .sunday: calendar.firstWeekday = 1 }
        return calendar
    }
    private var start: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month))! }
    private var offset: Int { (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7 }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Previous month", systemImage: "chevron.left") { month = calendar.date(byAdding: .month, value: -1, to: month)! }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button("Next month", systemImage: "chevron.right") { month = calendar.date(byAdding: .month, value: 1, to: month)! }.labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7]).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                ForEach(0..<(offset + calendar.range(of: .day, in: .month, for: start)!.count), id: \.self) { index in
                    if index < offset { Color.clear.frame(height: 44) }
                    else {
                        let date = calendar.date(byAdding: .day, value: index - offset, to: start)!
                        let key = LocalDay.string(date)
                        let day = data.day(habit.id, key)
                        let canComplete = !habit.archived && key <= LocalDay.string()
                        Button { if canComplete { complete(key) } } label: {
                            Text("\(index - offset + 1)").font(.body.monospacedDigit())
                                .foregroundStyle(key > LocalDay.string() ? .secondary : .primary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(habit.tint.opacity(day.count == 0 ? 0.05 : 0.15 + day.progress(target: habit.target) * 0.55), in: RoundedRectangle(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(key == selected ? habit.tint : key == LocalDay.string() ? Color.primary.opacity(0.5) : .clear, lineWidth: key == selected ? 2 : 1) }
                                .overlay(alignment: .bottom) { if !day.note.isEmpty { Circle().fill(.primary).frame(width: 4, height: 4).padding(.bottom, 3) } }
                        }.buttonStyle(.plain)
                            .disabled(!canComplete)
                            .sensoryFeedback(.impact(weight: .light), trigger: day.count)
                            .accessibilityLabel("\(key), \(day.count) Completions, target \(habit.target)\(day.note.isEmpty ? "" : ", has Day Note")")
                            .accessibilityHint(canComplete ? (day.count >= habit.target ? "Clear this day’s Completions" : "Add one Completion") : "Future dates and Archived Habits are read-only")
                            .accessibilityAddTraits(key == selected ? .isSelected : [])
                            .accessibilityAction(named: "Edit Habit Day") { if key <= LocalDay.string() { edit(key) } }
                    }
                }
            }
            Button("Go to today") { month = Date(); selected = LocalDay.string() }.font(.subheadline).padding(.top, 6)
        }
    }
}

struct DayEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let selection: DaySelection
    @State private var count: Int
    @State private var note: String
    init(selection: DaySelection, data: Dataset) {
        self.selection = selection
        let day = data.day(selection.habitID, selection.date)
        _count = State(initialValue: day.count); _note = State(initialValue: day.note)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(LocalDay.date(selection.date)?.formatted(date: .complete, time: .omitted) ?? selection.date).font(.headline)
                    Stepper("Completions: \(count)", value: $count, in: 0...max(99, count))
                        .sensoryFeedback(.impact(weight: .light), trigger: count)
                }
                Section {
                    TextEditor(text: $note).frame(minHeight: 150).accessibilityLabel("Day Note")
                        .onChange(of: note) { _, value in note = String(value.prefix(500)) }
                } header: { Text("Day Note (optional)") } footer: { Text("\(note.count) / 500 characters") }
            }
            .disabled(selection.date > LocalDay.string())
            .navigationTitle("Edit Habit Day").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.update { journal in
                            try journal.setCount(selection.habitID, day: selection.date, count: count)
                            try journal.setNote(selection.habitID, day: selection.date, note: note)
                        }
                        if model.error == nil { dismiss() }
                    }.disabled(selection.date > LocalDay.string())
                }
            }
        }
    }
}
