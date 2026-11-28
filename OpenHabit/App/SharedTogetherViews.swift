import SwiftUI
import OpenHabitCore

/// The periods the Together Chart can show. Week is a rolling seven days ending on the anchor day.
enum TogetherPeriod: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", year = "Year"
    var id: Self { self }
}

/// One stacked column: a day (Week, Month) or a calendar month (Year).
private struct TogetherColumn: Identifiable {
    let id: String
    let first: String
    let last: String
    let label: String
    let isFuture: Bool
    let isToday: Bool
    let amounts: [Int]
    var total: Int { amounts.reduce(0, +) }
}

/// Shared Habit Detail's Together Chart, per-Member period totals, and the selected day's Share Bar.
struct SharedTogetherSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: Habit
    let members: [SharedMember]
    @Binding var selected: String
    /// The current Member's own count for a day, read from local data.
    let myCount: (String) -> Int
    let addToDay: (String) -> Void
    let editDay: (String) -> Void
    @State private var period: TogetherPeriod = .week
    @State private var anchor = LocalDay.string()
    @State private var selectedMonth = String(LocalDay.string().prefix(7))

    private var today: String { LocalDay.string() }
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private var unitLabel: String {
        if let unit = habit.counter?.unit, !unit.isEmpty { return unit }
        return habit.counter == nil ? "Completions" : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartCard
            selectionCard
        }
        .onChange(of: period) { _, _ in
            anchor = today
            selectedMonth = String(today.prefix(7))
            selected = today
        }
    }

    // MARK: Chart card

    private var chartCard: some View {
        let columns = self.columns
        let first = columns.first?.first ?? today, last = columns.last?.last ?? today
        let totals = members.map { $0.total(from: first, through: last) }
        let groupTotal = totals.reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Period", selection: $period) {
                ForEach(TogetherPeriod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Button("Previous \(period.rawValue.lowercased())", systemImage: "chevron.left") { shift(-1) }
                    .labelStyle(.iconOnly).frame(width: 44, height: 36).disabled(!canShift(-1))
                Spacer()
                Text(rangeTitle).font(.headline)
                Spacer()
                Button("Next \(period.rawValue.lowercased())", systemImage: "chevron.right") { shift(1) }
                    .labelStyle(.iconOnly).frame(width: 44, height: 36).disabled(!canShift(1))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(groupTotal.formatted())
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(habit.tint)
                    .contentTransition(.numericText())
                Text(unitLabel.isEmpty ? "together" : "\(unitLabel) together")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let delta = weekDelta(current: groupTotal) {
                Label("\(abs(delta))% \(delta >= 0 ? "more" : "fewer") than the 7 days before", systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, -6)
            }
            chart(columns)
            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: 10) {
                        MemberInitial(member: member, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(activeDaysText(member, from: first, through: last))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(totals[index] == 0 ? "–" : totals[index].formatted())
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(totals[index] == 0 ? .secondary : .primary)
                            .contentTransition(.numericText())
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                    if index < members.count - 1 { Divider().padding(.leading, 38) }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private func chart(_ columns: [TogetherColumn]) -> some View {
        let height: CGFloat = 150
        let maximum = max(1, columns.map(\.total).max() ?? 1)
        let barWidth: CGFloat? = period == .week ? 30 : nil
        return HStack(alignment: .bottom, spacing: period == .month ? 2 : 6) {
            ForEach(columns) { column in
                let isSelected = column.id == selectionID
                Button {
                    guard !column.isFuture else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { select(column) }
                } label: {
                    VStack(spacing: 4) {
                        VStack(spacing: 2) {
                            Spacer(minLength: 0)
                            if column.isFuture {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .frame(width: barWidth, height: 16)
                            } else if column.total == 0 {
                                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.25))
                                    .frame(width: barWidth, height: 2)
                            } else {
                                ForEach(Array(members.indices.reversed()), id: \.self) { index in
                                    let amount = column.amounts[index]
                                    if amount > 0 {
                                        RoundedRectangle(cornerRadius: period == .month ? 2 : 4)
                                            .fill(members[index].tint)
                                            .frame(width: barWidth, height: max(3, CGFloat(amount) / CGFloat(maximum) * (height - 16)))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .opacity(isSelected || column.isFuture ? 1 : 0.55)
                        Text(column.label)
                            .font(.caption2.monospacedDigit().weight(column.isToday || isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? habit.tint : column.isToday ? .primary : .secondary)
                            .lineLimit(2).multilineTextAlignment(.center)
                            .fixedSize()
                            .frame(maxWidth: .infinity)
                            .frame(height: period == .week ? 28 : 14, alignment: .top)
                    }
                    .padding(.horizontal, period == .month ? 0 : 2)
                    .padding(.top, 6)
                    .background {
                        if isSelected { RoundedRectangle(cornerRadius: period == .month ? 3 : 10).fill(habit.tint.opacity(0.10)) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(column.isFuture)
                .accessibilityLabel(accessibilityLabel(column))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(column.isFuture ? "" : "Shows each Member's amount")
            }
        }
        .sensoryFeedback(.selection, trigger: selectionID)
    }

    // MARK: Selection card

    @ViewBuilder private var selectionCard: some View {
        let isMonth = period == .year
        let first = isMonth ? selectedMonth + "-01" : selected
        let last = isMonth ? lastDay(ofMonth: selectedMonth) : selected
        let amounts = members.map { $0.total(from: first, through: last) }
        let total = amounts.reduce(0, +)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectionTitle).font(.headline)
                Spacer()
                Text(total == 0 ? "None yet" : "\(total.formatted()) together")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ShareBar(members: members, amounts: amounts)
            HStack(alignment: .center, spacing: 12) {
                FlowLayout(spacing: 12, lineSpacing: 6) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        HStack(spacing: 5) {
                            MemberInitial(member: member, size: 16)
                            Text("\(member.name) \(amounts[index] == 0 ? "–" : amounts[index].formatted())")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(amounts[index] == 0 ? .secondary : .primary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !isMonth && selected <= today {
                    dayActions
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    /// Edit pill and the Completion Button for the selected day: logging matches the Overview,
    /// and exact amounts and the private Day Note live behind Edit.
    private var dayActions: some View {
        let dateLabel = LocalDay.date(selected)?.formatted(date: .abbreviated, time: .omitted) ?? selected
        return HStack(spacing: 10) {
            Button { editDay(selected) } label: {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(habit.tint)
                    .frame(width: 44, height: 36)
                    .background(habit.tint.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit My Day")
            .accessibilityHint("Set an exact amount or a private Day Note for \(dateLabel)")
            CompletionButton(habit: habit, count: myCount(selected), action: { addToDay(selected) }, size: 40)
                .accessibilityLabel(habit.counter == nil ? "My Completions on \(dateLabel): \(myCount(selected)) of \(habit.target)"
                                    : "My amount on \(dateLabel): \(habit.progressText(myCount(selected)))")
                .accessibilityIdentifier("shared-day-complete")
        }
    }

    private var selectionTitle: String {
        if period == .year {
            return LocalDay.date(selectedMonth + "-01")?.formatted(.dateTime.month(.wide).year()) ?? selectedMonth
        }
        let date = LocalDay.date(selected)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? selected
        return selected == today ? "\(date) · Today" : date
    }

    // MARK: Columns and navigation

    private var selectionID: String { period == .year ? selectedMonth : selected }

    private func select(_ column: TogetherColumn) {
        if period == .year {
            selectedMonth = column.id
        } else {
            selected = column.id
        }
    }

    private var columns: [TogetherColumn] {
        let anchorDate = LocalDay.date(anchor) ?? Date()
        switch period {
        case .week:
            return (0..<7).reversed().compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: anchorDate) else { return nil }
                return dayColumn(date, label: "\(date.formatted(.dateTime.weekday(.narrow)))\n\(calendar.component(.day, from: date))")
            }
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: anchorDate),
                  let count = calendar.range(of: .day, in: .month, for: anchorDate)?.count else { return [] }
            return (0..<count).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
                let day = offset + 1
                return dayColumn(date, label: day == 1 || day % 7 == 1 ? "\(day)" : "")
            }
        case .year:
            let year = calendar.component(.year, from: anchorDate)
            return (1...12).map { month in
                let id = String(format: "%04d-%02d", year, month)
                let first = id + "-01", last = lastDay(ofMonth: id)
                let label = LocalDay.date(first)?.formatted(.dateTime.month(.narrow)) ?? ""
                return TogetherColumn(id: id, first: first, last: last, label: label,
                                      isFuture: first > today, isToday: id == today.prefix(7),
                                      amounts: members.map { $0.total(from: first, through: last) })
            }
        }
    }

    private func dayColumn(_ date: Date, label: String) -> TogetherColumn {
        let key = LocalDay.string(date)
        return TogetherColumn(id: key, first: key, last: key, label: label, isFuture: key > today, isToday: key == today,
                              amounts: members.map { $0.counts[key] ?? 0 })
    }

    private func lastDay(ofMonth month: String) -> String {
        guard let date = LocalDay.date(month + "-01"),
              let interval = calendar.dateInterval(of: .month, for: date),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return month + "-31" }
        return LocalDay.string(last)
    }

    private var rangeTitle: String {
        let anchorDate = LocalDay.date(anchor) ?? Date()
        switch period {
        case .week:
            if anchor == today { return "Last 7 days" }
            let start = calendar.date(byAdding: .day, value: -6, to: anchorDate) ?? anchorDate
            return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(anchorDate.formatted(.dateTime.month(.abbreviated).day()))"
        case .month: return anchorDate.formatted(.dateTime.month(.wide).year())
        case .year: return anchorDate.formatted(.dateTime.year())
        }
    }

    private var earliestDay: String {
        members.flatMap(\.counts.keys).min() ?? today
    }

    private func shiftedAnchor(_ direction: Int) -> String? {
        guard let date = LocalDay.date(anchor) else { return nil }
        let shifted: Date?
        switch period {
        case .week: shifted = calendar.date(byAdding: .day, value: 7 * direction, to: date)
        case .month: shifted = calendar.date(byAdding: .month, value: direction, to: date)
        case .year: shifted = calendar.date(byAdding: .year, value: direction, to: date)
        }
        return shifted.map { LocalDay.string($0) }
    }

    private func canShift(_ direction: Int) -> Bool {
        guard let next = shiftedAnchor(direction) else { return false }
        if direction > 0 {
            switch period {
            case .week: return anchor < today
            case .month: return next.prefix(7) <= today.prefix(7)
            case .year: return next.prefix(4) <= today.prefix(4)
            }
        }
        switch period {
        case .week: return anchor > earliestDay
        case .month: return next.prefix(7) >= earliestDay.prefix(7)
        case .year: return next.prefix(4) >= earliestDay.prefix(4)
        }
    }

    private func shift(_ direction: Int) {
        guard canShift(direction), let next = shiftedAnchor(direction) else { return }
        anchor = min(next, today)
        switch period {
        case .week, .month:
            let visible = columns
            let candidate = visible.last(where: { !$0.isFuture })?.id ?? anchor
            selected = candidate
        case .year:
            selectedMonth = String(min(anchor, today).prefix(7))
        }
    }

    private func weekDelta(current: Int) -> Int? {
        guard period == .week, let anchorDate = LocalDay.date(anchor),
              let end = calendar.date(byAdding: .day, value: -7, to: anchorDate),
              let start = calendar.date(byAdding: .day, value: -6, to: end) else { return nil }
        let previous = members.reduce(0) { $0 + $1.total(from: LocalDay.string(start), through: LocalDay.string(end)) }
        guard previous > 0 else { return nil }
        return Int((Double(current - previous) / Double(previous) * 100).rounded())
    }

    private func activeDaysText(_ member: SharedMember, from first: String, through last: String) -> String {
        let end = min(last, today)
        let first = max(first, earliestDay)
        guard first <= end else { return "" }
        let active = member.counts.filter { $0.key >= first && $0.key <= end && $0.value > 0 }.count
        let span = (calendar.dateComponents([.day], from: LocalDay.date(first) ?? Date(), to: LocalDay.date(end) ?? Date()).day ?? 0) + 1
        return "\(active) of \(span) days"
    }

    private func accessibilityLabel(_ column: TogetherColumn) -> String {
        let title: String
        if period == .year {
            title = LocalDay.date(column.first)?.formatted(.dateTime.month(.wide).year()) ?? column.id
        } else {
            title = LocalDay.date(column.first)?.formatted(date: .complete, time: .omitted) ?? column.id
        }
        if column.isFuture { return "\(title), upcoming" }
        let parts = zip(members, column.amounts).map { member, amount in "\(member.name) \(amount == 0 ? "none" : amount.formatted())" }
        return "\(title), \(column.total.formatted()) together. " + parts.joined(separator: ", ")
    }
}

/// One horizontal bar split by how much each Member contributed.
private struct ShareBar: View {
    let members: [SharedMember]
    let amounts: [Int]

    var body: some View {
        let total = amounts.reduce(0, +)
        GeometryReader { geometry in
            let gaps = CGFloat(max(0, amounts.filter { $0 > 0 }.count - 1)) * 2
            HStack(spacing: 2) {
                if total == 0 {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                } else {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        let amount = amounts[index]
                        if amount > 0 {
                            let width = (geometry.size.width - gaps) * CGFloat(amount) / CGFloat(total)
                            Rectangle().fill(member.tint)
                                .frame(width: width)
                                .overlay {
                                    if width >= 30 {
                                        Text(Counter.compact(amount))
                                            .font(.caption.monospacedDigit().weight(.bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1).minimumScaleFactor(0.7)
                                    }
                                }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

/// A Member's initial on their Member Color.
struct MemberInitial: View {
    let member: SharedMember
    let size: CGFloat

    var body: some View {
        Circle().fill(member.tint).frame(width: size, height: size)
            .overlay {
                Text(String(member.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// The Habit Card's Today Strip: each Member's amount today and the group total.
struct SharedTodayStrip: View {
    let members: [SharedMember]
    let tint: Color
    let today: String

    var body: some View {
        let amounts = members.map { $0.counts[today] ?? 0 }
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                HStack(spacing: 5) {
                    MemberInitial(member: member, size: 20)
                    Text(amounts[index] == 0 ? "–" : Counter.compact(amounts[index]))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(amounts[index] == 0 ? .secondary : .primary)
                        .contentTransition(.numericText())
                }
                .padding(.leading, 3).padding(.trailing, 9).padding(.vertical, 3)
                .background(Color(.tertiarySystemFill).opacity(0.6), in: Capsule())
            }
            Text("\(amounts.reduce(0, +).formatted()) today")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(tint.opacity(0.10), in: Capsule())
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today: " + zip(members, amounts).map { "\($0.name) \($1 == 0 ? "none" : $1.formatted())" }.joined(separator: ", "))
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            } else {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width = needed
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
