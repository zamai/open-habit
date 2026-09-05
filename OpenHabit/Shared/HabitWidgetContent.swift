import SwiftUI
import WidgetKit
import AppIntents
import OpenHabitCore

struct HabitEntry: TimelineEntry {
    let date: Date
    let data: Dataset
    let ids: [UUID?]
    static var example: HabitEntry {
        var journal = Journal(); journal.seedIfEmpty()
        return HabitEntry(date: Date(), data: journal.dataset, ids: journal.dataset.active.map { $0.id })
    }
}
struct HabitWidgetContent: View {
    let entry: HabitEntry
    let medium: Bool
    var body: some View {
        GeometryReader { geometry in
            Group {
                if medium {
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { row in
                            let id = entry.ids.indices.contains(row) ? entry.ids[row] : nil
                            Group {
                                if let id, let habit = entry.data.habit(id), !habit.archived {
                                    widgetRow(habit)
                                } else { placeholder(row: row) }
                            }
                            .frame(height: max(0, geometry.size.height / 3))
                        }
                    }
                } else if let id = entry.ids.first ?? nil, let habit = entry.data.habit(id), !habit.archived {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(habit.emoji).font(.system(size: 18)).frame(width: 20)
                            Text(habit.name).font(.system(size: 12, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            widgetButton(habit, size: 36)
                        }.frame(height: 44)
                        WidgetHistory(habit: habit, data: entry.data, weeks: 10, spacing: 4, end: entry.date)
                    }.widgetURL(URL(string: "openhabit://habit/\(habit.id.uuidString)"))
                } else { placeholder(row: 0) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .padding(14)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { Color.black }
    }
    private func widgetRow(_ habit: Habit) -> some View {
        GeometryReader { geometry in
            let linkWidth = max(0, geometry.size.width - 54)
            HStack(spacing: 10) {
                Link(destination: URL(string: "openhabit://habit/\(habit.id.uuidString)")!) {
                    HStack(spacing: 8) {
                        Text(habit.emoji).font(.title2).frame(width: 28)
                        WidgetHistory(habit: habit, data: entry.data, weeks: 24, spacing: 1.5, end: entry.date)
                            .frame(width: max(0, linkWidth - 62))
                        Text("\(entry.data.day(habit.id, LocalDay.string(entry.date)).count)")
                            .font(.system(.headline, design: .rounded)).foregroundStyle(habit.tint).frame(width: 18)
                    }
                    .frame(width: linkWidth, height: geometry.size.height)
                }.buttonStyle(.plain).accessibilityLabel("Open \(habit.name)")
                widgetButton(habit, size: 32)
            }
        }
        .padding(.vertical, 3)
    }
    private func widgetButton(_ habit: Habit, size: CGFloat) -> some View {
        let count = entry.data.day(habit.id, LocalDay.string(entry.date)).count
        return Button(intent: ToggleHabitIntent(id: habit.id)) {
            CompletionGlyph(count: count, target: habit.target, color: habit.tint, size: size).frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(habit.name), \(count) Completions, Daily Target \(habit.target)")
            .accessibilityHint(count >= habit.target ? "Clear today’s Completions" : "Add one Completion")
    }
    private func placeholder(row: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(medium ? "Choose Habit \(row + 1)" : "Choose a Habit", systemImage: "leaf").font(.caption.weight(.semibold))
            Text("Hold widget → Edit Widget").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// WidgetKit archives this drawing once instead of hundreds of interactive DayTile views.
// History taps belong to the enclosing Link; only completion buttons run an intent.
private struct WidgetHistory: View {
    let habit: Habit
    let data: Dataset
    let weeks: Int
    let spacing: CGFloat
    let end: Date

    var body: some View {
        let cells = cells
        Canvas { context, size in
            let side = max(0, min((size.width - CGFloat(weeks - 1) * spacing) / CGFloat(weeks),
                                  (size.height - 6 * spacing) / 7))
            let gridHeight = 7 * side + 6 * spacing
            let top = max(0, (size.height - gridHeight) / 2)
            for (index, cell) in cells.enumerated() where !cell.future {
                let rect = CGRect(x: CGFloat(index / 7) * (side + spacing),
                                  y: top + CGFloat(index % 7) * (side + spacing), width: side, height: side)
                let path = Path(roundedRect: rect, cornerRadius: side * 0.25)
                let opacity = cell.day.count == 0 ? 0.22 : 0.35 + 0.65 * cell.day.progress(target: habit.target)
                context.fill(path, with: .color(habit.tint.opacity(opacity)))
                if cell.today {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), cornerRadius: side * 0.22),
                                   with: .color(.white.opacity(0.9)), lineWidth: 1.2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cells: [(day: HabitDay, today: Bool, future: Bool)] {
        var calendar = Calendar(identifier: .gregorian)
        switch data.settings.weekStart {
        case .system: calendar.firstWeekday = Calendar.current.firstWeekday
        case .monday: calendar.firstWeekday = 2
        case .sunday: calendar.firstWeekday = 1
        }
        let today = LocalDay.string(end)
        let trailing = (calendar.firstWeekday + 6 - calendar.component(.weekday, from: end) + 7) % 7
        let last = calendar.date(byAdding: .day, value: trailing, to: end)!
        return (0..<(weeks * 7)).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - weeks * 7 + 1, to: last)!
            let key = LocalDay.string(date)
            return (data.day(habit.id, key), key == today, key > today)
        }
    }
}
