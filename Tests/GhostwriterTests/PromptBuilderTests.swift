import XCTest
@testable import Ghostwriter

final class PromptBuilderTests: XCTestCase {
    func testCorrectionPayloadContainsText() throws {
        let data = try XCTUnwrap(PromptBuilder.correctionPayload(text: "hello world", tone: .neutral))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["text"], "hello world")
        XCTAssertNotNil(json["tone"])
    }

    func testElaborationPayloadContainsText() throws {
        let data = try XCTUnwrap(PromptBuilder.elaborationPayload(text: "meeting tmrw", tone: .professional))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["text"], "meeting tmrw")
        XCTAssertTrue(json["tone"]?.contains("professional") ?? false)
    }

    func testExtractRelevantTextShortText() {
        let text = "This is short."
        let result = PromptBuilder.extractRelevantText(text, maxLength: 2000)
        XCTAssertEqual(result, text)
    }

    func testExtractRelevantTextLongText() {
        let paragraph1 = String(repeating: "a", count: 1500)
        let paragraph2 = String(repeating: "b", count: 300)
        let text = paragraph1 + "\n\n" + paragraph2

        let result = PromptBuilder.extractRelevantText(text, maxLength: 500)
        XCTAssertTrue(result.count <= 500)
        XCTAssertTrue(result.contains("b"))
    }

    func testExtractRelevantTextExactlyAtLimit() {
        let text = String(repeating: "x", count: 2000)
        let result = PromptBuilder.extractRelevantText(text, maxLength: 2000)
        XCTAssertEqual(result, text)
    }

    func testToneModifierInPayload() throws {
        let data = try XCTUnwrap(PromptBuilder.correctionPayload(text: "test", tone: .casual))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertTrue(json["tone"]?.contains("casual") ?? false)
    }
}
