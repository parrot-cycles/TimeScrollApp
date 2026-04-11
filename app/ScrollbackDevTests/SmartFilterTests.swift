import XCTest
@testable import Scrollback

final class SmartFilterTests: XCTestCase {

    // MARK: - FilterCondition.toSQL()

    func test_appName_contains_generates_LIKE_sql() {
        let condition = FilterCondition(field: .appName, op: .contains, value: "Safari")
        let result = condition.toSQL()
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.sql.contains("LIKE"))
        XCTAssertEqual(result!.binds, ["%Safari%"])
    }

    func test_appName_equals_generates_exact_sql() {
        let condition = FilterCondition(field: .appName, op: .equals, value: "Safari")
        let result = condition.toSQL()
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.sql.contains("= ?"))
        XCTAssertEqual(result!.binds, ["Safari"])
    }

    func test_appName_notContains_generates_NOT_LIKE_sql() {
        let condition = FilterCondition(field: .appName, op: .notContains, value: "Chrome")
        let result = condition.toSQL()
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.sql.contains("NOT LIKE"))
    }

    func test_year_equals_generates_timestamp_range() {
        let condition = FilterCondition(field: .year, op: .equals, value: "2025")
        let result = condition.toSQL()
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.sql.contains("started_at_ms >="))
        XCTAssertTrue(result!.sql.contains("started_at_ms <"))
    }

    func test_year_invalid_returns_nil() {
        let condition = FilterCondition(field: .year, op: .equals, value: "abc")
        XCTAssertNil(condition.toSQL())
    }

    func test_text_field_returns_nil_for_sql() {
        let condition = FilterCondition(field: .text, op: .contains, value: "hello")
        XCTAssertNil(condition.toSQL(), "Text conditions should use FTS, not SQL")
    }

    func test_empty_value_returns_nil() {
        let condition = FilterCondition(field: .appName, op: .contains, value: "  ")
        XCTAssertNil(condition.toSQL())
    }

    // MARK: - FilterCondition.toFTS()

    func test_text_contains_returns_fts_match() {
        let condition = FilterCondition(field: .text, op: .contains, value: "Hello")
        let result = condition.toFTS()
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.match, "hello") // lowercased
        XCTAssertFalse(result!.isExclude)
    }

    func test_text_notContains_returns_exclude() {
        let condition = FilterCondition(field: .text, op: .notContains, value: "spam")
        let result = condition.toFTS()
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isExclude)
    }

    func test_nonText_field_returns_nil_for_fts() {
        let condition = FilterCondition(field: .appName, op: .contains, value: "Safari")
        XCTAssertNil(condition.toFTS())
    }
}
