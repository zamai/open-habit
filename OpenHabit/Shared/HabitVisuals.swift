import SwiftUI
import OpenHabitCore

extension HabitColor {
    var tint: Color {
        switch self {
        case .orange: Color(red: 0.94, green: 0.43, blue: 0.16)
        case .blue: Color(red: 0.20, green: 0.52, blue: 0.96)
        case .green: Color(red: 0.22, green: 0.67, blue: 0.39)
        case .pink: .pink
        case .purple: .purple
        case .teal: .teal
        case .red: .red
        case .yellow: Color(red: 0.78, green: 0.61, blue: 0.08)
        case .indigo: .indigo
        case .mint: .mint
        case .brown: .brown
        }
    }
}

extension Habit {
    var tint: Color {
        guard let rgb = customColorRGB else { return color.tint }
        return Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
}

struct CompletionGlyph: View {
    let count: Int
    let target: Int
    let color: Color
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            if count >= target || target == 1 {
                RoundedRectangle(cornerRadius: size * 0.29)
                    .fill(count >= target ? color : color.opacity(0.10))
                RoundedRectangle(cornerRadius: size * 0.29)
                    .strokeBorder(color.opacity(count >= target ? 1 : 0.6), lineWidth: 2)
                if count >= target { Image(systemName: "checkmark").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white) }
            } else {
                Canvas { context, canvas in
                    let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                    let gap = min(8.0, 100.0 / Double(target))
                    for segment in 0..<target {
                        var path = Path()
                        path.addArc(center: center, radius: canvas.width / 2 - 3,
                                    startAngle: .degrees(Double(segment) * 360 / Double(target) - 90 + gap / 2),
                                    endAngle: .degrees(Double(segment + 1) * 360 / Double(target) - 90 - gap / 2), clockwise: false)
                        context.stroke(path, with: .color(segment < count ? color : color.opacity(0.20)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                }
                Image(systemName: "plus").font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CompletionButton: View {
    let habit: Habit
    let count: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            CompletionGlyph(count: count, target: habit.target, color: habit.tint)
                .frame(width: 56, height: 56, alignment: .center)
        }
            .buttonStyle(CompletionStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: count)
            .accessibilityLabel("\(habit.name), \(count) Completions today, Daily Target \(habit.target)")
            .accessibilityHint(count >= habit.target ? "Clear today’s Completions" : "Add one Completion")
            .accessibilityIdentifier("complete-\(habit.id.uuidString)")
    }
}
struct CompletionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(.rect(cornerRadius: 18))
    }
}

struct DayTile: View {
    let day: HabitDay
    let target: Int
    let color: Color
    let today: Bool
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: geometry.size.width * 0.22)
                .fill(day.count == 0 ? color.opacity(0.10) : color.opacity(0.25 + 0.75 * day.progress(target: target)))
                .overlay(alignment: .topTrailing) {
                    if !day.note.isEmpty { Circle().fill(.primary).frame(width: 3, height: 3).offset(x: 1, y: -1) }
                }
                .overlay { if today { RoundedRectangle(cornerRadius: geometry.size.width * 0.22).strokeBorder(.primary.opacity(0.8), lineWidth: 1) } }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct LabeledHistoryGrid: View {
    let habit: Habit
    let data: Dataset
    var weeks = 24
    var spacing: CGFloat = 3
    var maxTileSide: CGFloat = 11
    var end: Date = Date()

    private var calendar: Calendar { historyCalendar(for: data) }
    private var dates: [Date] { historyDates(weeks: weeks, end: end, calendar: calendar) }

    var body: some View {
        let dates = dates
        let monthLabels = monthLabels(for: dates)
        Canvas { context, size in
            let labelWidth: CGFloat = 30
            let labelGap: CGFloat = 10
            let gridX = labelWidth + labelGap
            let availableWidth = max(0, size.width - gridX)
            let side = min(maxTileSide, max(0, (availableWidth - CGFloat(weeks - 1) * spacing) / CGFloat(weeks)))
            let pitch = side + spacing
            let gridY: CGFloat = 22

            for (week, label) in monthLabels {
                context.draw(Text(label).font(.caption).foregroundStyle(.secondary),
                             at: CGPoint(x: gridX + CGFloat(week) * pitch, y: 0), anchor: .topLeading)
            }
            for row in 0..<7 {
                let y = gridY + CGFloat(row) * pitch
                let weekday = weekdayLabel(for: row)
                if !weekday.isEmpty {
                    context.draw(Text(weekday).font(.caption).foregroundStyle(.secondary),
                                 at: CGPoint(x: 0, y: y + side / 2), anchor: .leading)
                }
                for week in 0..<weeks {
                    let date = dates[week * 7 + row]
                    let key = LocalDay.string(date)
                    let isFuture = key > LocalDay.string(end)
                    let day = isFuture ? HabitDay(count: 0) : data.day(habit.id, key)
                    let rect = CGRect(x: gridX + CGFloat(week) * pitch, y: y, width: side, height: side)
                    let shape = Path(roundedRect: rect, cornerRadius: side * 0.22)
                    let opacity = day.count == 0 ? 0.10 : 0.25 + 0.75 * day.progress(target: habit.target)
                    context.fill(shape, with: .color(habit.tint.opacity(opacity)))
                    if key == LocalDay.string(end) {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: side * 0.20),
                                       with: .color(.primary.opacity(0.8)), lineWidth: 1)
                    }
                    if !isFuture && !day.note.isEmpty {
                        let dot = CGRect(x: rect.maxX - 2, y: rect.minY - 1, width: 3, height: 3)
                        context.fill(Path(ellipseIn: dot), with: .color(.primary))
                    }
                }
            }
        }
        .frame(height: 112)
        .accessibilityHidden(true)
    }

    private func monthLabels(for dates: [Date]) -> [Int: String] {
        var labels: [Int: String] = [:]
        for week in 0..<weeks {
            let weekDates = dates[(week * 7)..<(week * 7 + 7)]
            if week == 0, let first = weekDates.first {
                labels[week] = first.formatted(.dateTime.month(.abbreviated))
            }
            if let monthStart = weekDates.first(where: { calendar.component(.day, from: $0) == 1 }) {
                labels[week] = monthStart.formatted(.dateTime.month(.abbreviated))
            }
        }
        return labels
    }

    private func weekdayLabel(for row: Int) -> String {
        guard row.isMultiple(of: 2) == false else { return "" }
        let symbolIndex = (calendar.firstWeekday - 1 + row) % 7
        return calendar.shortWeekdaySymbols[symbolIndex]
    }
}

struct HistoryGrid: View {
    let habit: Habit
    let data: Dataset
    var weeks = 18
    var spacing: CGFloat = 3
    var maxTileSide: CGFloat? = nil
    var end: Date = Date()
    var onSelect: ((String) -> Void)?
    var onEdit: ((String) -> Void)?
    private var calendar: Calendar { historyCalendar(for: data) }
    private var dates: [Date] {
        historyDates(weeks: weeks, end: end, calendar: calendar)
    }
    var body: some View {
        let dates = dates
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { row in
                        let date = dates[week * 7 + row]
                        let key = LocalDay.string(date)
                        let isFuture = key > LocalDay.string(end)
                        let day = isFuture ? HabitDay() : data.day(habit.id, key)
                        DayTile(day: day, target: habit.target, color: habit.tint, today: key == LocalDay.string(end))
                            .frame(maxWidth: maxTileSide, maxHeight: maxTileSide)
                            .contentShape(Rectangle())
                            .onTapGesture { if !isFuture { onSelect?(key) } }
                            .onLongPressGesture { if !isFuture && key <= LocalDay.string() { onEdit?(key) } }
                            .accessibilityLabel("\(key), \(day.count) of \(habit.target) Completions\(day.note.isEmpty ? "" : ", has Day Note")")
                            .accessibilityHidden(onSelect == nil || isFuture)
                    }
                }
            }
        }
    }
}

private func historyCalendar(for data: Dataset) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    switch data.settings.weekStart {
    case .system: calendar.firstWeekday = Calendar.current.firstWeekday
    case .monday: calendar.firstWeekday = 2
    case .sunday: calendar.firstWeekday = 1
    }
    return calendar
}

private func historyDates(weeks: Int, end: Date, calendar: Calendar) -> [Date] {
    let weekday = calendar.component(.weekday, from: end)
    let trailing = (calendar.firstWeekday + 6 - weekday + 7) % 7
    let last = calendar.date(byAdding: .day, value: trailing, to: end)!
    return (0..<(weeks * 7)).map { calendar.date(byAdding: .day, value: $0 - weeks * 7 + 1, to: last)! }
}

struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: 20, content: content) }
        else { content() }
    }
}
