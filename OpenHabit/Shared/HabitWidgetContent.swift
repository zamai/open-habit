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
        var data = journal.dataset
        data.habits += [
            Habit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Meditate", emoji: "🧘", color: .pink),
            Habit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Check in", emoji: "❤️", color: .teal, target: 3),
            Habit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, name: "Practice", emoji: "🥁", color: .yellow)
        ]
        for (habitIndex, habit) in data.habits.enumerated() {
            for offset in 0..<10 where (offset + habitIndex * 2) % 4 == 0 {
                let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
                data.days[Dataset.key(habit.id, LocalDay.string(date))] = HabitDay(count: habit.target)
            }
        }
        return HabitEntry(date: Date(), data: data, ids: data.active.map { $0.id })
    }
}

struct HabitWidgetContent: View {
    let entry: HabitEntry
    let compactRows: Int?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let compactRows {
                    compactWidget(rows: compactRows, size: geometry.size)
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
                } else {
                    singlePlaceholder
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .padding(compactRows == nil ? 14 : 12)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { Color.black }
    }

    private func compactWidget(rows: Int, size: CGSize) -> some View {
        let dates = recentDates
        let columnSpacing: CGFloat = 4
        let iconGap: CGFloat = 8
        let tileSide = min(27, max(0, (size.width - iconGap - columnSpacing * 9 - 4) / 11))
        let iconSide = tileSide + 4
        return VStack(spacing: rows == 6 ? 8 : 7) {
            HStack(spacing: iconGap) {
                Color.clear.frame(width: iconSide, height: 12)
                HStack(spacing: columnSpacing) {
                    ForEach(dates, id: \.self) { date in
                        Text(weekday(date)).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary).frame(width: tileSide)
                    }
                }
            }
            ForEach(0..<rows, id: \.self) { row in
                let id = entry.ids.indices.contains(row) ? entry.ids[row] : nil
                if let id, let habit = entry.data.habit(id), !habit.archived {
                    compactRow(habit, dates: dates, tileSide: tileSide, iconSide: iconSide,
                               iconGap: iconGap, columnSpacing: columnSpacing)
                } else {
                    compactPlaceholder(row: row, height: iconSide)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func compactRow(_ habit: Habit, dates: [Date], tileSide: CGFloat, iconSide: CGFloat,
                            iconGap: CGFloat, columnSpacing: CGFloat) -> some View {
        HStack(spacing: iconGap) {
            Text(habit.emoji).font(.system(size: tileSide * 0.7))
                .frame(width: iconSide, height: iconSide)
                .background(habit.tint.opacity(0.24), in: RoundedRectangle(cornerRadius: iconSide * 0.26))
                .accessibilityLabel(habit.name)
            HStack(spacing: columnSpacing) {
                ForEach(dates, id: \.self) { date in
                    let today = LocalDay.string(date) == LocalDay.string(entry.date)
                    let tile = RecentDayTile(day: entry.data.day(habit.id, LocalDay.string(date)), target: habit.target,
                                             color: habit.tint, today: today, size: tileSide)
                    if today {
                        Button(intent: ToggleHabitIntent(id: habit.id)) { tile }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Track \(habit.name)")
                    } else {
                        Link(destination: URL(string: "openhabit://habit/\(habit.id.uuidString)")!) { tile }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(habit.name) history")
                    }
                }
            }
        }
    }

    private func compactPlaceholder(row: Int, height: CGFloat) -> some View {
        Label("Choose Habit \(row + 1)", systemImage: "leaf")
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }

    private var singlePlaceholder: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Choose a Habit", systemImage: "leaf").font(.caption.weight(.semibold))
            Text("Hold widget → Edit Widget").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentDates: [Date] {
        (0..<10).compactMap { Calendar.current.date(byAdding: .day, value: $0 - 9, to: entry.date) }
    }

    private func weekday(_ date: Date) -> String {
        let index = Calendar.current.component(.weekday, from: date) - 1
        return String(Calendar.current.shortWeekdaySymbols[index].prefix(2))
    }

    private func widgetButton(_ habit: Habit, size: CGFloat) -> some View {
        let count = entry.data.day(habit.id, LocalDay.string(entry.date)).count
        return Button(intent: ToggleHabitIntent(id: habit.id)) {
            CompletionGlyph(count: count, target: habit.target, color: habit.tint, size: size).frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(habit.name), \(count) Completions, Daily Target \(habit.target)")
            .accessibilityHint(count >= habit.target ? "Clear today’s Completions" : "Add one Completion")
    }
}

private struct RecentDayTile: View {
    let day: HabitDay
    let target: Int
    let color: Color
    let today: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(color.opacity(day.count == 0 ? 0.20 : day.count >= target ? 1 : 0.28))
            if day.count > 0 && day.count < target {
                Circle().trim(from: 0, to: day.progress(target: target))
                    .stroke(color, style: StrokeStyle(lineWidth: max(2, size * 0.11), lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(size * 0.20)
            }
            if day.count >= target {
                Image(systemName: "checkmark")
                    .font(.system(size: max(7, size * 0.36), weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if today {
                RoundedRectangle(cornerRadius: size * 0.22).strokeBorder(.white.opacity(0.85), lineWidth: 1.3)
            }
        }
    }
}

// WidgetKit archives this drawing once instead of hundreds of interactive DayTile views.
// History taps belong to the enclosing Link; only completion buttons run an intent.
struct WidgetHistory: View {
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
            for (index, cell) in cells.enumerated() {
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

    private var cells: [(day: HabitDay, today: Bool)] {
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
            return (key > today ? HabitDay() : data.day(habit.id, key), key == today)
        }
    }
}
