import XCTest
@testable import TimeScroll

final class CalendarPickerTests: XCTestCase {

    func test_daysWithSnapshots_current_month() throws {
        try DB.shared.openIfNeeded()
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)

        let days = try DB.shared.daysWithSnapshots(year: year, month: month)

        // Current month should have at least today (if capture is running)
        // Just verify it doesn't crash and returns valid day numbers
        for day in days {
            XCTAssertGreaterThanOrEqual(day, 1)
            XCTAssertLessThanOrEqual(day, 31)
        }
    }

    func test_daysWithSnapshots_empty_month() throws {
        try DB.shared.openIfNeeded()
        // Far future month should have no data
        let days = try DB.shared.daysWithSnapshots(year: 2099, month: 1)
        XCTAssertTrue(days.isEmpty)
    }

    func test_daysWithSnapshots_past_month_with_data() throws {
        try DB.shared.openIfNeeded()
        // March 2026 should have data (we've been capturing)
        let days = try DB.shared.daysWithSnapshots(year: 2026, month: 3)
        XCTAssertFalse(days.isEmpty, "March 2026 should have snapshot data")
    }
}
