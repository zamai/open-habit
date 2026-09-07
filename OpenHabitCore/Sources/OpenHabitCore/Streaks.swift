import Foundation

public extension Dataset {
    func currentStreak(for habit: Habit, asOf date: Date = Date()) -> Int {
        guard let goal = habit.streakGoal else { return 0 }
        let calendar = trackingCalendar

        switch goal.period {
        case .daily:
            var cursor = date
            if !isCompleted(habit, on: cursor) {
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            }
            var result = 0
            while isCompleted(habit, on: cursor) {
                result += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            }
            return result
        case .weekly:
            var week = startOfWeek(containing: date, calendar: calendar)
            if completedDays(for: habit, inWeekContaining: week) < goal.target {
                week = calendar.date(byAdding: .weekOfYear, value: -1, to: week)!
            }
            var result = 0
            while completedDays(for: habit, inWeekContaining: week) >= goal.target {
                result += 1
                week = calendar.date(byAdding: .weekOfYear, value: -1, to: week)!
            }
            return result
        }
    }

    func completedDays(for habit: Habit, inWeekContaining date: Date) -> Int {
        let calendar = trackingCalendar
        let start = startOfWeek(containing: date, calendar: calendar)
        return (0..<7).reduce(into: 0) { total, offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            if isCompleted(habit, on: day) { total += 1 }
        }
    }

    func completionTotal(for habitID: UUID, inMonthContaining date: Date) -> Int {
        let calendar = trackingCalendar
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return 0 }
        var cursor = interval.start
        var result = 0
        while cursor < interval.end {
            result += day(habitID, LocalDay.string(cursor)).count
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return result
    }

    private var trackingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        switch settings.weekStart {
        case .system: calendar.firstWeekday = Calendar.current.firstWeekday
        case .monday: calendar.firstWeekday = 2
        case .sunday: calendar.firstWeekday = 1
        }
        return calendar
    }

    private func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date))!
    }

    private func isCompleted(_ habit: Habit, on date: Date) -> Bool {
        day(habit.id, LocalDay.string(date)).count >= habit.target
    }
}
