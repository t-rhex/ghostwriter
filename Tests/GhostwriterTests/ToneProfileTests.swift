import XCTest
@testable import Ghostwriter

final class ToneProfileTests: XCTestCase {
    func testSlackIsCasual() {
        let tone = ToneProfile.tone(for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(tone, .casual)
    }

    func testMessagesIsCasual() {
        let tone = ToneProfile.tone(for: "com.apple.MobileSMS")
        XCTAssertEqual(tone, .casual)
    }

    func testDiscordIsCasual() {
        let tone = ToneProfile.tone(for: "com.hnc.Discord")
        XCTAssertEqual(tone, .casual)
    }

    func testMailIsProfessional() {
        let tone = ToneProfile.tone(for: "com.apple.mail")
        XCTAssertEqual(tone, .professional)
    }

    func testOutlookIsProfessional() {
        let tone = ToneProfile.tone(for: "com.microsoft.Outlook")
        XCTAssertEqual(tone, .professional)
    }

    func testTerminalIsTechnical() {
        let tone = ToneProfile.tone(for: "com.apple.Terminal")
        XCTAssertEqual(tone, .technical)
    }

    func testXcodeIsTechnical() {
        let tone = ToneProfile.tone(for: "com.apple.dt.Xcode")
        XCTAssertEqual(tone, .technical)
    }

    func testVSCodeIsTechnical() {
        let tone = ToneProfile.tone(for: "com.microsoft.VSCode")
        XCTAssertEqual(tone, .technical)
    }

    func testUnknownAppIsNeutral() {
        let tone = ToneProfile.tone(for: "com.unknown.app")
        XCTAssertEqual(tone, .neutral)
    }

    func testNilBundleIDIsNeutral() {
        let tone = ToneProfile.tone(for: nil)
        XCTAssertEqual(tone, .neutral)
    }

    func testToneHasSystemPromptModifier() {
        for tone in [Tone.casual, .professional, .technical, .neutral] {
            XCTAssertFalse(tone.systemPromptModifier.isEmpty, "\(tone) should have a prompt modifier")
        }
    }
}
