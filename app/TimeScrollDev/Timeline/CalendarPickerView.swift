import SwiftUI

/// A monthly calendar picker that highlights days containing snapshots.
struct CalendarPickerView: View {
    @Binding var selectedDate: Date
    var daysWithContent: Set<Int> // day-of-month values (1-31) that have snapshots
    var onSelectDay: (Date) -> Void

    @State private var displayedMonth: Date

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    init(selectedDate: Binding<Date>, daysWithContent: Set<Int>, onSelectDay: @escaping (Date) -> Void) {
        self._selectedDate = selectedDate
        self.daysWithContent = daysWithContent
        self.onSelectDay = onSelectDay
        self._displayedMonth = State(initialValue: selectedDate.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Month navigation
            HStack {
                Text(monthYearString)
                    .font(.title2.bold())
                Spacer()
                HStack(spacing: 4) {
                    Button { changeMonth(by: -1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        displayedMonth = Date()
                        selectedDate = Date()
                        onSelectDay(Date())
                    } label: {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .help("Today")

                    Button { changeMonth(by: 1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(dayCells(), id: \.id) { cell in
                    if let day = cell.day {
                        DayCell(
                            day: day,
                            isToday: cell.isToday,
                            isSelected: cell.isSelected,
                            hasContent: cell.hasContent,
                            isCurrentMonth: cell.isCurrentMonth
                        )
                        .onTapGesture {
                            if let date = cell.date {
                                selectedDate = date
                                onSelectDay(date)
                            }
                        }
                    } else {
                        Text("")
                            .frame(width: 32, height: 32)
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 8, height: 8)
                Text("Days with red color have content on them")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .onChange(of: selectedDate) { newDate in
            // Keep displayed month in sync when date changes externally
            if !calendar.isDate(newDate, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = newDate
            }
        }
    }

    // MARK: - Helpers

    private var monthYearString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: displayedMonth)
    }

    private func changeMonth(by offset: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private struct DayCellData: Identifiable {
        let id: Int // position in grid 0-41
        let day: Int?
        let date: Date?
        let isToday: Bool
        let isSelected: Bool
        let hasContent: Bool
        let isCurrentMonth: Bool
    }

    private func dayCells() -> [DayCellData] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        // Offset: how many blank cells before day 1 (Sunday = 1)
        let offset = firstWeekday - calendar.firstWeekday
        let adjustedOffset = offset < 0 ? offset + 7 : offset

        let today = Date()
        let todayComps = calendar.dateComponents([.year, .month, .day], from: today)
        let selectedComps = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let monthComps = calendar.dateComponents([.year, .month], from: displayedMonth)

        // Previous month days to fill leading blanks
        let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: firstOfMonth)!
        let prevMonthRange = calendar.range(of: .day, in: .month, for: prevMonthDate)!
        let prevMonthLastDay = prevMonthRange.upperBound - 1

        var cells: [DayCellData] = []

        // Leading days from previous month
        for i in 0..<adjustedOffset {
            let day = prevMonthLastDay - adjustedOffset + 1 + i
            cells.append(DayCellData(id: i, day: day, date: nil, isToday: false, isSelected: false, hasContent: false, isCurrentMonth: false))
        }

        // Current month days
        for day in range {
            let idx = cells.count
            let isToday = todayComps.year == monthComps.year && todayComps.month == monthComps.month && todayComps.day == day
            let isSelected = selectedComps.year == monthComps.year && selectedComps.month == monthComps.month && selectedComps.day == day
            let hasContent = daysWithContent.contains(day)
            let date = calendar.date(from: DateComponents(year: monthComps.year, month: monthComps.month, day: day))
            cells.append(DayCellData(id: idx, day: day, date: date, isToday: isToday, isSelected: isSelected, hasContent: hasContent, isCurrentMonth: true))
        }

        // Trailing days from next month
        let totalCells = cells.count <= 35 ? 35 : 42
        var nextDay = 1
        while cells.count < totalCells {
            let idx = cells.count
            cells.append(DayCellData(id: idx, day: nextDay, date: nil, isToday: false, isSelected: false, hasContent: false, isCurrentMonth: false))
            nextDay += 1
        }

        return cells
    }
}

private struct DayCell: View {
    let day: Int
    let isToday: Bool
    let isSelected: Bool
    let hasContent: Bool
    let isCurrentMonth: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
            } else if hasContent && isCurrentMonth {
                Circle()
                    .fill(Color.red.opacity(0.75))
                    .frame(width: 32, height: 32)
            }

            Text("\(day)")
                .font(.system(.body, design: .rounded).weight(isToday ? .bold : .regular))
                .foregroundColor(textColor)
                .frame(width: 32, height: 32)

            if isToday && !isSelected {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 32, height: 32)
            }
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
    }

    private var textColor: Color {
        if isSelected { return .white }
        if hasContent && isCurrentMonth { return .white }
        if !isCurrentMonth { return .secondary.opacity(0.4) }
        return .primary
    }
}
