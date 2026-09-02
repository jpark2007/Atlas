import XCTest
@testable import AtlasCore

/// `ClassInfoFormat` parses a syllabus's own grade-weight lines for display. The
/// "200% grading total" bug (2026-09-01 handoff) traced to a syllabus's own summary row
/// ("Total: 100%") being counted alongside the weights it summarizes, not excluded —
/// these lock down the exclusion rule these tests exist to protect.
final class ClassInfoFormatTests: XCTestCase {

    // MARK: - weightTotal

    func testNormalWeightListSumsCorrectly() {
        let lines = ["Midterms 30%", "Final 40%", "Homework 30%"]
        XCTAssertEqual(ClassInfoFormat.weightTotal(lines), "100%")
    }

    func testTotalSummaryRowIsExcludedFromSum() {
        let lines = ["Midterms 30%", "Final 40%", "Homework 30%", "Total: 100%"]
        XCTAssertEqual(ClassInfoFormat.weightTotal(lines), "100%")
    }

    func testSumSummaryRowIsExcludedFromSum() {
        let lines = ["Midterms 30%", "Final 40%", "Homework 30%", "Sum 100%"]
        XCTAssertEqual(ClassInfoFormat.weightTotal(lines), "100%")
    }

    /// The approximate shape behind the reported "200%" card: six weights that already
    /// sum to 100%, plus the syllabus's own "TOTAL" row restating that — the bug was
    /// this row being summed as a seventh weight instead of recognized as a summary.
    func testCalcIShapeDoesNotDoubleCount() {
        let lines = [
            "Homework 10%",
            "Quizzes 15%",
            "First Midterm 20%",
            "Second Midterm 20%",
            "Final Exam 30%",
            "Participation 5%",
            "TOTAL 100%",
        ]
        XCTAssertEqual(ClassInfoFormat.weightTotal(lines), "100%")
        XCTAssertEqual(ClassInfoFormat.weightRows(lines).count, 6)
    }

    func testCaseAndWhitespaceVariantsOfSummaryRowAreExcluded() {
        XCTAssertTrue(ClassInfoFormat.isSummaryRow("TOTAL: 100%"))
        XCTAssertTrue(ClassInfoFormat.isSummaryRow("  total  100%"))
        XCTAssertTrue(ClassInfoFormat.isSummaryRow("Sum: 100%"))
        XCTAssertTrue(ClassInfoFormat.isSummaryRow("SUM 100%"))
        XCTAssertFalse(ClassInfoFormat.isSummaryRow("Midterms 30%"))
    }

    func testRowWithNoPercentIsNotCountedAndNotASummaryRow() {
        let lines = ["Midterms 30%", "Final 40%", "Participation (see syllabus)"]
        XCTAssertEqual(ClassInfoFormat.weightTotal(lines), "70%")
        XCTAssertFalse(ClassInfoFormat.isSummaryRow("Participation (see syllabus)"))
        XCTAssertEqual(ClassInfoFormat.weightRows(lines).count, 3)
    }

    func testEmptyOrAllSummaryListHasNoTotal() {
        XCTAssertNil(ClassInfoFormat.weightTotal([]))
        XCTAssertNil(ClassInfoFormat.weightTotal(["Total: 100%"]))
    }

    // MARK: - weight

    func testWeightSplitsLabelAndPercent() {
        let parts = ClassInfoFormat.weight("Midterms 36%")
        XCTAssertEqual(parts.label, "Midterms")
        XCTAssertEqual(parts.percent, "36%")
    }

    func testWeightWithNoPercentReturnsWholeLineAsLabel() {
        let parts = ClassInfoFormat.weight("Extra credit available")
        XCTAssertEqual(parts.label, "Extra credit available")
        XCTAssertNil(parts.percent)
    }
}
