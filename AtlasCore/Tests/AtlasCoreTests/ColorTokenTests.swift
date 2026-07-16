import XCTest
import SwiftUI
@testable import AtlasCore

/// Custom hex colors persist as plain-text `"#RRGGBB"` tokens and resolve back to
/// the same color — no migration, the columns are already text.
final class ColorTokenTests: XCTestCase {

    func testNamedTokensStillResolve() {
        XCTAssertEqual(ColorToken.color(for: "school"), AtlasTheme.Colors.school)
        XCTAssertEqual(ColorToken.color(for: "personal"), AtlasTheme.Colors.personal)
        XCTAssertEqual(ColorToken.color(for: "side"), AtlasTheme.Colors.side)
        XCTAssertEqual(ColorToken.color(for: "accent"), AtlasTheme.Colors.accent)
    }

    func testNamedColorsSerializeToTheirToken() {
        XCTAssertEqual(ColorToken.token(for: AtlasTheme.Colors.school), "school")
        XCTAssertEqual(ColorToken.token(for: AtlasTheme.Colors.accent), "accent")
    }

    func testHexStringRoundTrip() {
        let hex = "#3F6FA8"
        let color = Color(hex: hex)
        XCTAssertEqual(color.atlasHexString, hex)
        // token(for:) of an arbitrary color yields its hex; color(for:) restores it.
        let token = ColorToken.token(for: color)
        XCTAssertEqual(token, hex)
        XCTAssertEqual(ColorToken.color(for: token).atlasHexString, hex)
    }

    func testUnknownNonHexTokenFallsBackToAccent() {
        XCTAssertEqual(ColorToken.color(for: "bogus"), AtlasTheme.Colors.accent)
    }
}
