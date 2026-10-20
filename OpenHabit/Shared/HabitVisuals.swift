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
                    .fill(count >= target ? color : .clear)
                RoundedRectangle(cornerRadius: size * 0.29)
                    .strokeBorder(color.opacity(count >= target ? 1 : 0.65), lineWidth: 2.5)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(count >= target ? .white : color.opacity(0.35))
            } else {
                Canvas { context, canvas in
                    let inset: CGFloat = 3
                    let outline = Path(roundedRect: CGRect(x: inset, y: inset,
                                                           width: canvas.width - inset * 2,
                                                           height: canvas.height - inset * 2),
                                       cornerRadius: size * 0.29)
                    let segments = target
                    // Leave visible space after the rounded line caps extend into each gap.
                    let gap = min(0.055, 0.4 / CGFloat(segments))
                    for segment in 0..<segments {
                        let start = CGFloat(segment) / CGFloat(segments) + gap / 2
                        let end = CGFloat(segment + 1) / CGFloat(segments) - gap / 2
                        let path = outline.trimmedPath(from: start, to: end)
                        context.stroke(path, with: .color(segment < count ? color : color.opacity(0.25)),
                                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
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
    var alignment: Alignment = .center
    var size: CGFloat = 48
    var body: some View {
        Button(action: action) {
            CompletionGlyph(count: count, target: habit.target, color: habit.tint, size: size)
                .frame(width: max(44, size + 8), height: max(44, size + 8), alignment: alignment)
        }
            .buttonStyle(CompletionStyle())
            .completionFeedback(count: count)
            .accessibilityLabel("\(habit.name), \(count) Completions today, Daily Target \(habit.target)")
            .accessibilityHint(count >= habit.target ? "Clear today’s Completions" : "Add one Completion")
            .accessibilityIdentifier("complete-\(habit.id.uuidString)")
    }
}
struct CompletionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(.rect(cornerRadius: 18))
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func completionFeedback(count: Int) -> some View {
        modifier(CompletionFeedback(count: count))
    }
}

private struct CompletionFeedback: ViewModifier {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var additions = 0

    func body(content: Content) -> some View {
        let motionReduced = reduceMotion
        return content
            .keyframeAnimator(initialValue: CGFloat(1), trigger: additions) { content, scale in
                content.scaleEffect(motionReduced ? 1 : scale)
            } keyframes: { _ in
                LinearKeyframe(0.82, duration: 0.07)
                SpringKeyframe(1.2, duration: 0.2, spring: .bouncy)
                SpringKeyframe(1, duration: 0.3, spring: .bouncy)
            }
            .onChange(of: count) { old, new in
                if new > old { additions += 1 }
            }
            .sensoryFeedback(trigger: count) { old, new in
                new > old ? .impact(flexibility: .soft, intensity: 0.8) : .selection
            }
    }
}

struct DayTile: View {
    let day: HabitDay
    let target: Int
    let color: Color
    let today: Bool
    var emptyColor: Color? = nil
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: geometry.size.width * 0.22)
                .fill(day.count == 0 ? (emptyColor ?? color.opacity(0.10)) : color.opacity(0.25 + 0.75 * day.progress(target: target)))
                .overlay(alignment: .topTrailing) {
                    if !day.note.isEmpty { Circle().fill(.primary).frame(width: 3, height: 3).offset(x: 1, y: -1) }
                }
                .overlay { if today { RoundedRectangle(cornerRadius: geometry.size.width * 0.22).strokeBorder(.primary.opacity(0.8), lineWidth: 1) } }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#if os(iOS)
struct LabeledHistoryGrid: View {
    let habit: Habit
    let data: Dataset
    var spacing: CGFloat = 3
    var tileSide: CGFloat = 11
    var end: Date = Date()
    @ScaledMetric(relativeTo: .caption) private var labelFontSize: CGFloat = 12

    private var calendar: Calendar { historyCalendar(for: data) }

    static func leadingInset(fontSize: CGFloat, data: Dataset) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize)
        let weekdayWidth = historyCalendar(for: data).shortWeekdaySymbols.map {
            ($0 as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return max(30, weekdayWidth) + 10
    }

    private static func minimumTileSide(fontSize: CGFloat, data: Dataset, tileSide: CGFloat, spacing: CGFloat) -> CGFloat {
        let calendar = historyCalendar(for: data)
        let font = UIFont.systemFont(ofSize: fontSize)
        let monthWidth = calendar.shortMonthSymbols.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // Month starts are at least four columns apart. Budget for two labels and an
        // 8-point gap when the newest label must shift left from the final column.
        return max(tileSide, ceil((2 * monthWidth + 8 - 4 * spacing) / 5))
    }

    var body: some View {
        let side = Self.minimumTileSide(fontSize: labelFontSize, data: data, tileSide: tileSide, spacing: spacing)
        let gridY = labelFontSize + 10
        let gridX = Self.leadingInset(fontSize: labelFontSize, data: data)
        HistoryCanvasLayout(leadingInset: gridX, labelFontSize: labelFontSize, minimumTileSide: side,
                            spacing: spacing, calendar: calendar, end: end) {
            Canvas { context, size in
                let availableWidth = max(0, size.width - gridX)
                let layout = CompactHistoryLayout(width: availableWidth, end: end, calendar: calendar,
                                                  tileSide: side, spacing: spacing)
                let dates = layout.dates
                let pitch = layout.tileSide + spacing

                for month in layout.months {
                    let label = context.resolve(Text(calendar.shortMonthSymbols[calendar.component(.month, from: month) - 1])
                        .font(.system(size: labelFontSize)).foregroundStyle(.secondary))
                    let labelSize = label.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                    context.draw(label, at: CGPoint(x: gridX + layout.labelX(for: month, width: labelSize.width), y: 0), anchor: .topLeading)
                }
                for row in 0..<7 {
                    let y = gridY + CGFloat(row) * pitch
                    let weekday = weekdayLabel(for: row)
                    if !weekday.isEmpty {
                        context.draw(Text(weekday).font(.system(size: labelFontSize)).foregroundStyle(.secondary),
                                     at: CGPoint(x: 0, y: y + layout.tileSide / 2), anchor: .leading)
                    }
                    for week in 0..<layout.weeks {
                        let date = dates[week * 7 + row]
                        let key = LocalDay.string(date)
                        let isFuture = key > LocalDay.string(end)
                        let day = isFuture ? HabitDay(count: 0) : data.day(habit.id, key)
                        let rect = CGRect(x: gridX + CGFloat(week) * pitch, y: y, width: layout.tileSide, height: layout.tileSide)
                        let shape = Path(roundedRect: rect, cornerRadius: layout.tileSide * 0.22)
                        let opacity = day.count == 0 ? 0.10 : 0.25 + 0.75 * day.progress(target: habit.target)
                        context.fill(shape, with: .color(habit.tint.opacity(opacity)))
                        if key == LocalDay.string(end) {
                            context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: layout.tileSide * 0.20),
                                           with: .color(.primary.opacity(0.8)), lineWidth: 1)
                        }
                        if !isFuture && !day.note.isEmpty {
                            let dot = CGRect(x: rect.maxX - 2, y: rect.minY - 1, width: 3, height: 3)
                            context.fill(Path(ellipseIn: dot), with: .color(.primary))
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func weekdayLabel(for row: Int) -> String {
        guard row.isMultiple(of: 2) == false else { return "" }
        let symbolIndex = (calendar.firstWeekday - 1 + row) % 7
        return calendar.shortWeekdaySymbols[symbolIndex]
    }
}

/// Size the canvas from its actual width so full-width day squares stay square.
private struct HistoryCanvasLayout: Layout {
    let leadingInset: CGFloat
    let labelFontSize: CGFloat
    let minimumTileSide: CGFloat
    let spacing: CGFloat
    let calendar: Calendar
    let end: Date

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(leadingInset, proposal.replacingUnspecifiedDimensions().width)
        let history = CompactHistoryLayout(width: width - leadingInset, end: end, calendar: calendar,
                                           tileSide: minimumTileSide, spacing: spacing)
        return CGSize(width: width, height: labelFontSize + 10 + 7 * history.tileSide + 6 * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

/// Choose whole months at the preferred density, then fill the available width.
struct CompactHistoryLayout {
    let calendar: Calendar
    let months: [Date]
    let dates: [Date]
    let tileSide: CGFloat
    let spacing: CGFloat
    var weeks: Int { dates.count / 7 }
    var width: CGFloat { CGFloat(weeks) * (tileSide + spacing) - spacing }

    init(width: CGFloat, end: Date, calendar: Calendar, tileSide: CGFloat = 11, spacing: CGFloat = 3) {
        self.calendar = calendar
        self.spacing = spacing
        let currentMonth = calendar.dateInterval(of: .month, for: end)!.start
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: end)!.start
        var monthCount = 1
        var weekCount = 1
        for count in 1...12 {
            let firstMonth = calendar.date(byAdding: .month, value: 1 - count, to: currentMonth)!
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstMonth)!.start
            let weeks = calendar.dateComponents([.day], from: firstWeek, to: currentWeek).day! / 7 + 1
            if count > 1 && CGFloat(weeks) * (tileSide + spacing) - spacing > width { break }
            monthCount = count
            weekCount = weeks
        }
        months = (0..<monthCount).map { calendar.date(byAdding: .month, value: $0 + 1 - monthCount, to: currentMonth)! }
        dates = historyDates(weeks: weekCount, end: calendar.startOfDay(for: end), calendar: calendar)
        self.tileSide = max(0, (width - CGFloat(weekCount - 1) * spacing) / CGFloat(weekCount))
    }

    func labelX(for month: Date, width labelWidth: CGFloat) -> CGFloat {
        let week = calendar.dateComponents([.day], from: dates[0], to: month).day! / 7
        return max(0, min(CGFloat(week) * (tileSide + spacing), width - labelWidth))
    }
}
#endif

struct HistoryGrid: View {
    let habit: Habit
    let data: Dataset
    var weeks = 18
    var spacing: CGFloat = 3
    var maxTileSide: CGFloat? = nil
    var end: Date = Date()
    var emptyColor: Color? = nil
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
                        DayTile(day: day, target: habit.target, color: habit.tint, today: key == LocalDay.string(end), emptyColor: emptyColor)
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
    calendar.locale = .current
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

#if os(iOS)
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: 20, content: content) }
        else { content() }
    }
}
#endif
