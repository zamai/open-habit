import SwiftUI
import OpenHabitCore

struct WatchHabitsView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("watchSelectedHabit") private var selectedHabit = ""
    @State private var selection: UUID?
    @State private var page = UUID()
    @State private var date = Date()

    var body: some View {
        Group {
            if model.data.active.isEmpty {
                ContentUnavailableView {
                    Label("No Habits", systemImage: "leaf")
                } description: {
                    Text(model.data.initialized ? "Add a Habit on your iPhone." : "Open Open Habit on your iPhone to sync your Habits.")
                }
            } else {
                navigation(date: date)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                date = Date()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { date = Date() }
        }
        .onChange(of: model.data.active.map(\.id), initial: true) { _, ids in
            #if DEBUG && targetEnvironment(simulator)
            // Opens on the Habit list, for layout checks without simulator input.
            if ProcessInfo.processInfo.arguments.contains("--watch-list") { return }
            #endif
            guard selection.map(ids.contains) != true || !ids.contains(page) else { return }
            selection = UUID(uuidString: selectedHabit).flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
            if let selection { page = selection }
        }
        .onChange(of: selection) { _, id in
            if let id { page = id; selectedHabit = id.uuidString }
        }
        .onChange(of: page) { _, id in
            selectedHabit = id.uuidString
        }
    }

    private func navigation(date: Date) -> some View {
        NavigationSplitView {
            List(model.data.active, selection: $selection) { habit in
                WatchHabitRow(habit: habit, data: model.data, date: date)
                    .tag(habit.id)
                    .listRowBackground(Color.black)
            }
            .listStyle(.plain)
            .containerBackground(.black, for: .navigation)
        } detail: {
            TabView(selection: $page) {
                ForEach(model.data.active) { habit in
                    WatchHabitPage(habit: habit, data: model.data, date: date)
                        .tag(habit.id)
                }
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

private struct WatchHabitPage: View {
    let habit: Habit
    let data: Dataset
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            let weeks = geometry.size.width < 180 ? 8 : 10
            let side = min((geometry.size.width - CGFloat(weeks - 1) * 4) / CGFloat(weeks),
                           max(7, (geometry.size.height - 104) / 7))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text(habit.emoji).font(.system(size: 22)).accessibilityHidden(true)
                    Text(habit.name).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    WatchCompletionButton(habit: habit, count: data.day(habit.id, LocalDay.string(date)).count)
                }
                HistoryGrid(habit: habit, data: data, weeks: weeks, spacing: 4, end: date,
                            emptyColor: .white.opacity(0.28))
                    .frame(width: CGFloat(weeks) * side + CGFloat(weeks - 1) * 4, height: 7 * side + 24)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(weeks) weeks of \(habit.name) history. The outlined square is today.")
                HStack {
                    Text("Today").foregroundStyle(.secondary)
                    Spacer()
                    Text(habit.counter == nil ? "\(data.day(habit.id, LocalDay.string(date)).count) / \(habit.target)"
                         : habit.progressText(data.day(habit.id, LocalDay.string(date)).count))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                }.font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
    }
}

private struct WatchHabitRow: View {
    let habit: Habit
    let data: Dataset
    let date: Date
    @Environment(\.counterScales) private var counterScales

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(habit.emoji).font(.system(size: 22)).accessibilityHidden(true)
                Text(habit.name).font(.system(.caption, design: .rounded).weight(.semibold))
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                WatchCompletionButton(habit: habit, count: data.day(habit.id, LocalDay.string(date)).count, size: 38)
            }
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = Calendar.current.date(byAdding: .day, value: offset - 6, to: date)!
                        let tile = data.day(habit.id, LocalDay.string(day))
                        DayTile(day: tile, target: habit.target,
                                color: habit.tint, today: offset == 6, emptyColor: .white.opacity(0.28),
                                intensity: habit.counter == nil ? nil : habit.intensity(tile.count, reference: counterScales[habit.id]?.reference))
                            .frame(width: 7, height: 7)
                    }
                }.accessibilityHidden(true)
                Spacer(minLength: 4)
                let count = data.day(habit.id, LocalDay.string(date)).count
                Text(habit.counter == nil ? "\(count)/\(habit.target)" : Counter.compact(count))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 3)
    }
}

private struct WatchCompletionButton: View {
    @Environment(WatchModel.self) private var model
    let habit: Habit
    let count: Int
    var size: CGFloat = 42

    var body: some View {
        Button { model.complete(habit.id) } label: {
            CompletionGlyph(count: count, target: habit.target, color: habit.tint, size: size, counterStep: habit.counter?.step)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(CompletionStyle())
        .completionFeedback(count: count)
        .accessibilityLabel(habit.counter == nil ? "\(habit.name), \(count) of \(habit.target) Completions today" : "\(habit.name), \(habit.progressText(count)) today")
        .accessibilityHint(habit.completionHint(count: count))
        .accessibilityIdentifier("watch-complete-\(habit.id.uuidString)")
    }
}
