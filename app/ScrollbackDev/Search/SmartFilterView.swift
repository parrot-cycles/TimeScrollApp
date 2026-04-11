import SwiftUI

/// A single filter condition row.
struct FilterCondition: Identifiable, Equatable {
    let id = UUID()
    var field: Field
    var op: Op
    var value: String

    enum Field: String, CaseIterable {
        case text = "Text"
        case appName = "App Name"
        case year = "Year"
        case month = "Month"
        case day = "Day"
    }

    enum Op: String, CaseIterable {
        case contains = "contains"
        case notContains = "not contains"
        case equals = "is"
        case notEquals = "is not"
    }

    /// Convert to SQL fragments for ts_snapshot queries.
    /// Returns (sql fragment, bind values) or nil if not applicable.
    func toSQL() -> (sql: String, binds: [String])? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch field {
        case .text:
            // Text filtering is handled via FTS, not SQL WHERE
            return nil
        case .appName:
            switch op {
            case .contains:
                return ("s.app_name LIKE ?", ["%\(trimmed)%"])
            case .notContains:
                return ("(s.app_name NOT LIKE ? OR s.app_name IS NULL)", ["%\(trimmed)%"])
            case .equals:
                return ("s.app_name = ?", [trimmed])
            case .notEquals:
                return ("(s.app_name != ? OR s.app_name IS NULL)", [trimmed])
            }
        case .year:
            guard let yr = Int(trimmed) else { return nil }
            let startMs = Self.msForDate(year: yr, month: 1, day: 1)
            let endMs = Self.msForDate(year: yr + 1, month: 1, day: 1)
            switch op {
            case .equals, .contains:
                return ("s.started_at_ms >= \(startMs) AND s.started_at_ms < \(endMs)", [])
            case .notEquals, .notContains:
                return ("(s.started_at_ms < \(startMs) OR s.started_at_ms >= \(endMs))", [])
            }
        case .month:
            guard let mo = Int(trimmed), mo >= 1, mo <= 12 else { return nil }
            // Match any year with this month — use strftime equivalent via computation
            // Since we can't use strftime on ms, we'll match month via extraction
            return nil // handled specially in query builder
        case .day:
            guard let d = Int(trimmed), d >= 1, d <= 31 else { return nil }
            return nil // handled specially in query builder
        }
    }

    /// Text conditions return FTS match string.
    func toFTS() -> (match: String, isExclude: Bool)? {
        guard field == .text else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        switch op {
        case .contains, .equals:
            return (trimmed, false)
        case .notContains, .notEquals:
            return (trimmed, true)
        }
    }

    private static func msForDate(year: Int, month: Int, day: Int) -> Int64 {
        var cal = Calendar.current
        cal.timeZone = .current
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return 0 }
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}

/// Match mode for combining conditions.
enum FilterMatchMode: String, CaseIterable {
    case all = "all"
    case any = "any"
}

/// Smart filter builder UI (Apple Mail-style).
struct SmartFilterView: View {
    @Binding var conditions: [FilterCondition]
    @Binding var matchMode: FilterMatchMode
    var onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Match mode
            HStack(spacing: 6) {
                Text("Match")
                Picker("", selection: $matchMode) {
                    Text("all").tag(FilterMatchMode.all)
                    Text("any").tag(FilterMatchMode.any)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                Text("of the following:")
            }
            .font(.subheadline)

            Divider()

            // Condition rows
            ForEach($conditions) { $condition in
                HStack(spacing: 6) {
                    Picker("", selection: $condition.field) {
                        ForEach(FilterCondition.Field.allCases, id: \.self) { field in
                            Text(field.rawValue).tag(field)
                        }
                    }
                    .frame(width: 100)
                    .labelsHidden()

                    Picker("", selection: $condition.op) {
                        ForEach(FilterCondition.Op.allCases, id: \.self) { op in
                            Text(op.rawValue).tag(op)
                        }
                    }
                    .frame(width: 110)
                    .labelsHidden()

                    TextField("value", text: $condition.value)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 100)

                    Button {
                        conditions.removeAll { $0.id == condition.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(conditions.count <= 1)

                    Button {
                        if let idx = conditions.firstIndex(where: { $0.id == condition.id }) {
                            conditions.insert(FilterCondition(field: .text, op: .contains, value: ""), at: idx + 1)
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.green)
                }
            }

            Divider()

            HStack {
                Button("Clear All") {
                    conditions = [FilterCondition(field: .text, op: .contains, value: "")]
                    matchMode = .all
                }
                Spacer()
                Button("Apply") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
