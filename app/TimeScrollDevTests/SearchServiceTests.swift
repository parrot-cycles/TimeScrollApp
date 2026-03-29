import XCTest
@testable import TimeScroll

final class SearchServiceTests: XCTestCase {

    let svc = SearchService()

    // MARK: - FTS Parts

    func test_ftsParts_single_token() {
        let parts = svc.ftsParts(for: "hello", fuzziness: .off, intelligentAccuracy: false)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first, "hello")
    }

    func test_ftsParts_multiple_tokens_AND() {
        let parts = svc.ftsParts(for: "hello world", fuzziness: .off, intelligentAccuracy: false)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], "hello")
        XCTAssertEqual(parts[1], "world")
    }

    func test_ftsParts_phrase() {
        let parts = svc.ftsParts(for: "\"hello world\"", fuzziness: .off, intelligentAccuracy: false)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first, "\"hello world\"")
    }

    func test_ftsParts_empty_query() {
        let parts = svc.ftsParts(for: "", fuzziness: .off, intelligentAccuracy: false)
        XCTAssertTrue(parts.isEmpty)
    }

    func test_ftsParts_fuzziness_medium_adds_prefix() {
        let parts = svc.ftsParts(for: "automation", fuzziness: .medium, intelligentAccuracy: false)
        XCTAssertEqual(parts.count, 1)
        XCTAssertTrue(parts.first?.hasSuffix("*") == true, "Medium fuzziness should add prefix wildcard")
    }

    func test_ftsParts_short_token_no_prefix() {
        let parts = svc.ftsParts(for: "go", fuzziness: .medium, intelligentAccuracy: false)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first, "go", "Short tokens should not get prefix wildcard")
    }

    // MARK: - Search Count

    func test_searchCount_returns_nonnegative() {
        let count = svc.searchCount(for: "zzzznonexistent", fuzziness: .off, intelligentAccuracy: false)
        XCTAssertGreaterThanOrEqual(count, 0)
    }

    // MARK: - DB Integration

    func test_daysWithSnapshots_returns_set() throws {
        try DB.shared.openIfNeeded()
        let days = try DB.shared.daysWithSnapshots(year: 2026, month: 3)
        // Should return a set of day numbers (could be empty if no data for that month)
        XCTAssertTrue(days is Set<Int>)
        for day in days {
            XCTAssertGreaterThanOrEqual(day, 1)
            XCTAssertLessThanOrEqual(day, 31)
        }
    }

    func test_searchCount_db_query() throws {
        try DB.shared.openIfNeeded()
        let count = try DB.shared.searchCount(["dtf"])
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}
