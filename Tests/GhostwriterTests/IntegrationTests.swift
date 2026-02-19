import XCTest
@testable import Ghostwriter

final class IntegrationTests: XCTestCase {

    // MARK: - KeystrokeBuffer Tests

    func testKeystrokeBufferAccumulation() {
        let buffer = KeystrokeBuffer()
        buffer.append("H")
        buffer.append("e")
        buffer.append("l")
        buffer.append("l")
        buffer.append("o")

        XCTAssertEqual(buffer.content, "Hello")
        XCTAssertEqual(buffer.count, 5)
        XCTAssertFalse(buffer.isEmpty)
    }

    func testKeystrokeBufferDelete() {
        let buffer = KeystrokeBuffer()
        buffer.append("H")
        buffer.append("e")
        buffer.append("l")
        buffer.append("l")
        buffer.append("o")

        buffer.handleDelete()
        XCTAssertEqual(buffer.content, "Hell")
        XCTAssertEqual(buffer.count, 4)

        buffer.handleDelete()
        buffer.handleDelete()
        XCTAssertEqual(buffer.content, "He")

        // Delete all remaining characters
        buffer.handleDelete()
        buffer.handleDelete()
        XCTAssertEqual(buffer.content, "")
        XCTAssertTrue(buffer.isEmpty)

        // Deleting from an empty buffer should be safe
        buffer.handleDelete()
        XCTAssertTrue(buffer.isEmpty)
    }

    // MARK: - CorrectionUndoManager Tests

    func testUndoManagerPreventsLoops() {
        let undoManager = CorrectionUndoManager()
        undoManager.recordCorrection(original: "teh", corrected: "the")

        XCTAssertTrue(undoManager.wasRecentlyCorrected("the"),
                       "Text that was just corrected should be detected as recently corrected")
        XCTAssertFalse(undoManager.wasRecentlyCorrected("teh"),
                        "Original text should not be detected as recently corrected")
        XCTAssertFalse(undoManager.wasRecentlyCorrected("unrelated"),
                        "Unrelated text should not be detected as recently corrected")
    }

    func testUndoManagerTracksUndo() {
        let undoManager = CorrectionUndoManager()
        undoManager.recordCorrection(original: "recieve", corrected: "receive")

        XCTAssertTrue(undoManager.isUndoneCorrection("recieve"),
                       "Original text should be detected as an undone correction")
        XCTAssertFalse(undoManager.isUndoneCorrection("receive"),
                        "Corrected text should not be detected as an undone correction")
        XCTAssertFalse(undoManager.isUndoneCorrection("something else"),
                        "Unrelated text should not be detected as an undone correction")
    }

    func testUndoManagerClear() {
        let undoManager = CorrectionUndoManager()
        undoManager.recordCorrection(original: "teh", corrected: "the")
        undoManager.recordCorrection(original: "recieve", corrected: "receive")

        // Verify records exist before clearing
        XCTAssertTrue(undoManager.wasRecentlyCorrected("the"))
        XCTAssertTrue(undoManager.isUndoneCorrection("teh"))

        undoManager.clear()

        // After clearing, nothing should be tracked
        XCTAssertFalse(undoManager.wasRecentlyCorrected("the"),
                        "Cleared manager should not track corrected text")
        XCTAssertFalse(undoManager.isUndoneCorrection("teh"),
                        "Cleared manager should not track original text")
        XCTAssertFalse(undoManager.wasRecentlyCorrected("receive"),
                        "Cleared manager should not track any corrections")
    }

    // MARK: - LLMResponse Codable Tests

    func testLLMResponseDecoding() throws {
        let json = """
        {
            "result": "Hello, world!",
            "elapsed_ms": 42.5
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LLMResponse.self, from: json)
        XCTAssertEqual(response.result, "Hello, world!")
        XCTAssertEqual(response.elapsedMs, 42.5, accuracy: 0.001)
    }

    func testLLMResponseEncoding() throws {
        let response = LLMResponse(result: "Corrected text here", elapsedMs: 123.45)
        let data = try JSONEncoder().encode(response)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["result"] as? String, "Corrected text here")
        let elapsedMs = try XCTUnwrap(json["elapsed_ms"] as? Double)
        XCTAssertEqual(elapsedMs, 123.45, accuracy: 0.001)
        // Verify the snake_case key is used (not camelCase)
        XCTAssertNil(json["elapsedMs"], "Should use snake_case key 'elapsed_ms' not camelCase")
    }

    // MARK: - Edit Distance (Levenshtein) Tests

    /// Simple Levenshtein distance implementation for test verification.
    private func levenshteinDistance(_ s: String, _ t: String) -> Int {
        let sArray = Array(s)
        let tArray = Array(t)
        let m = sArray.count
        let n = tArray.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Create distance matrix
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = sArray[i - 1] == tArray[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,       // deletion
                    matrix[i][j - 1] + 1,       // insertion
                    matrix[i - 1][j - 1] + cost  // substitution
                )
            }
        }

        return matrix[m][n]
    }

    func testEditDistanceIdentical() {
        let text = "Hello, world!"
        let distance = levenshteinDistance(text, text)
        XCTAssertEqual(distance, 0, "Identical strings should have zero edit distance")
    }

    func testEditDistanceCompleteDifference() {
        let a = "aaaa"
        let b = "bbbb"
        let distance = levenshteinDistance(a, b)
        XCTAssertEqual(distance, 4,
                        "Completely different strings of length 4 should have edit distance 4")

        // Verify ratio is high
        let maxLen = max(a.count, b.count)
        let ratio = Double(distance) / Double(maxLen)
        XCTAssertGreaterThanOrEqual(ratio, 0.9,
                                     "Completely different strings should have a high edit distance ratio")
    }

    func testEditDistanceSmallChange() {
        let original = "recieve"
        let corrected = "receive"
        let distance = levenshteinDistance(original, corrected)
        XCTAssertEqual(distance, 2,
                        "Swapping 'ie' to 'ei' should have edit distance 2")

        // Single character insertion
        let a = "color"
        let b = "colour"
        let insertDistance = levenshteinDistance(a, b)
        XCTAssertEqual(insertDistance, 1,
                        "Inserting one character should have edit distance 1")

        // Verify the edit distance ratio is small relative to text length
        let maxLen = max(original.count, corrected.count)
        let ratio = Double(distance) / Double(maxLen)
        XCTAssertLessThan(ratio, Configuration.maxEditDistanceRatio,
                           "A small typo fix should be within the configured max edit distance ratio")
    }

    // MARK: - KeystrokeBuffer Flush Tests

    func testKeystrokeBufferFlush() {
        let buffer = KeystrokeBuffer()
        buffer.append("T")
        buffer.append("e")
        buffer.append("s")
        buffer.append("t")

        let flushed = buffer.flush()
        XCTAssertEqual(flushed, "Test")
        XCTAssertTrue(buffer.isEmpty, "Buffer should be empty after flush")
        XCTAssertEqual(buffer.content, "")
    }

    // MARK: - Pipeline Component Interaction Tests

    func testBufferToPromptBuilderPipeline() throws {
        // Simulate keystroke accumulation, then use the text for prompt building
        let buffer = KeystrokeBuffer()
        for char in "meeting tmrw" {
            buffer.append(String(char))
        }

        let text = buffer.flush()
        XCTAssertEqual(text, "meeting tmrw")

        // Build a correction payload from the buffer output
        let payload = try XCTUnwrap(PromptBuilder.correctionPayload(text: text, tone: .professional))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: String])
        XCTAssertEqual(json["text"], "meeting tmrw")
        XCTAssertNotNil(json["tone"])
    }

    func testCorrectionResponseToUndoManagerPipeline() throws {
        // Simulate receiving a correction response and tracking it in the undo manager
        let responseJSON = """
        {
            "result": "meeting tomorrow",
            "elapsed_ms": 85.2
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LLMResponse.self, from: responseJSON)
        XCTAssertEqual(response.result, "meeting tomorrow")

        let undoManager = CorrectionUndoManager()
        undoManager.recordCorrection(original: "meeting tmrw", corrected: response.result)

        // The corrected text should be detected to prevent re-correction loops
        XCTAssertTrue(undoManager.wasRecentlyCorrected("meeting tomorrow"))

        // If user undoes, the original text should be recognized
        XCTAssertTrue(undoManager.isUndoneCorrection("meeting tmrw"))
    }

    func testEditDistanceRatioGuardsCorrection() {
        // Simulate the safety check: if edit distance ratio exceeds threshold, reject
        let original = "Hello"
        let drasticChange = "Goodbye to all of you"
        let distance = levenshteinDistance(original, drasticChange)
        let maxLen = max(original.count, drasticChange.count)
        let ratio = Double(distance) / Double(maxLen)

        XCTAssertGreaterThan(ratio, Configuration.maxEditDistanceRatio,
                              "A drastic change should exceed the max edit distance ratio and be rejected")

        // A minor correction should pass the threshold
        let minorCorrection = "hello"
        let minorDistance = levenshteinDistance(original, minorCorrection)
        let minorMaxLen = max(original.count, minorCorrection.count)
        let minorRatio = Double(minorDistance) / Double(minorMaxLen)

        XCTAssertLessThanOrEqual(minorRatio, Configuration.maxEditDistanceRatio,
                                  "A minor capitalization fix should be within the allowed ratio")
    }
}
