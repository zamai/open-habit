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
            .accessibilityLabel("\(habit.name), \(count) Completions today, Daily Target \(habit.target)")
            .accessibilityHint(count >= habit.target ? "Clear today’s Completions" : "Add one Completion")
            .accessibilityIdentifier("complete-\(habit.id.uuidString)")
    }
}
struct CompletionStyle: ButtonStyle {
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        } else {
            configuration.label.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

struct DayTile: View {
    let day: HabitDay
    let target: Int
    let color: Color
    let today: Bool
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: min(2, geometry.size.width * 0.18))
                .fill(day.count == 0 ? color.opacity(0.10) : color.opacity(0.25 + 0.75 * day.progress(target: target)))
                .overlay(alignment: .bottom) {
                    if day.count > 0 && day.count < target {
                        Rectangle().fill(.primary.opacity(0.55)).frame(width: geometry.size.width * day.progress(target: target), height: 1)
                    }
                }
                .overlay {
                    if day.count >= target && geometry.size.width >= 13 {
                        Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if !day.note.isEmpty { Circle().fill(.primary).frame(width: 3, height: 3).offset(x: 1, y: -1) }
                }
                .overlay { if today { RoundedRectangle(cornerRadius: min(2, geometry.size.width * 0.18)).strokeBorder(.primary.opacity(0.8), lineWidth: 1) } }
        }
        .aspectRatio(1, contentMode: .fit)
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
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        switch data.settings.weekStart { case .system: calendar.firstWeekday = Calendar.current.firstWeekday; case .monday: calendar.firstWeekday = 2; case .sunday: calendar.firstWeekday = 1 }
        return calendar
    }
    private var dates: [Date] {
        let weekday = calendar.component(.weekday, from: end)
        let trailing = (calendar.firstWeekday + 6 - weekday + 7) % 7
        let last = calendar.date(byAdding: .day, value: trailing, to: end)!
        return (0..<(weeks * 7)).map { calendar.date(byAdding: .day, value: $0 - weeks * 7 + 1, to: last)! }
    }
    var body: some View {
        let dates = dates
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { row in
                        let date = dates[week * 7 + row]
                        let key = LocalDay.string(date)
                        let day = data.day(habit.id, key)
                        DayTile(day: day, target: habit.target, color: habit.tint, today: key == LocalDay.string(end))
                            .frame(maxWidth: maxTileSide, maxHeight: maxTileSide)
                            .opacity(key > LocalDay.string(end) ? 0 : 1)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect?(key) }
                            .onLongPressGesture { if key <= LocalDay.string() { onEdit?(key) } }
                            .accessibilityLabel("\(key), \(day.count) of \(habit.target) Completions\(day.note.isEmpty ? "" : ", has Day Note")")
                            .accessibilityHidden(onSelect == nil || key > LocalDay.string(end))
                    }
                }
            }
        }
    }
}

struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: 20, content: content) }
        else { content() }
    }
}
