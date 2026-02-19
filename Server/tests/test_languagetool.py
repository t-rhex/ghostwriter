"""Integration tests for LanguageTool correction and post-processing."""

import sys
import os

# Add Server/ to path so we can import ghostwriter_server
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import language_tool_python
from ghostwriter_server import post_process, _classify_tone

# ---------------------------------------------------------------------------
# LanguageTool direct tests
# ---------------------------------------------------------------------------

tool = language_tool_python.LanguageTool("en-US")


def test_subject_verb_agreement():
    matches = tool.check("Is you sure this works.")
    corrected = language_tool_python.utils.correct("Is you sure this works.", matches)
    assert "Are you" in corrected, f"Expected 'Are you' in: {corrected}"
    print(f"PASS subject-verb: {corrected}")


def test_multiple_sentences_preserved():
    text = "This is sentence one. This is sentence two."
    matches = tool.check(text)
    corrected = language_tool_python.utils.correct(text, matches)
    assert "sentence one" in corrected.lower(), f"Sentence 1 dropped: {corrected}"
    assert "sentence two" in corrected.lower(), f"Sentence 2 dropped: {corrected}"
    print(f"PASS multi-sentence: {corrected}")


def test_empty_text():
    matches = tool.check("")
    assert len(matches) == 0, "Empty text should have no matches"
    print("PASS empty text")


def test_spelling():
    matches = tool.check("I cant beleive there here.")
    corrected = language_tool_python.utils.correct(
        "I cant beleive there here.", matches
    )
    assert "believe" in corrected.lower() or "can't" in corrected, (
        f"Spelling not fixed: {corrected}"
    )
    print(f"PASS spelling: {corrected}")


# ---------------------------------------------------------------------------
# post_process tests
# ---------------------------------------------------------------------------


def test_post_process_capitalize_first():
    assert post_process("hello world") == "Hello world"
    print("PASS post_process capitalize first")


def test_post_process_capitalize_after_period():
    result = post_process("hello. world")
    assert result == "Hello. World", f"Got: {result}"
    print("PASS post_process capitalize after period")


def test_post_process_standalone_i():
    result = post_process("i think i can")
    assert "I think I can" == result, f"Got: {result}"
    print("PASS post_process standalone i")


def test_post_process_is_you():
    result = post_process("is you sure")
    assert "are you" in result.lower(), f"Got: {result}"
    print(f"PASS post_process is you: {result}")


def test_post_process_space_before_punctuation():
    result = post_process("What is this ?")
    assert "?" in result and " ?" not in result, f"Got: {result}"
    print(f"PASS post_process space before punct: {result}")


def test_post_process_no_forced_period():
    """post_process should NOT force a period on text without terminal punctuation."""
    result = post_process("Hello world")
    assert result == "Hello world", f"Got: {result}"
    print(f"PASS post_process no forced period: {result}")


# ---------------------------------------------------------------------------
# Tone classification tests
# ---------------------------------------------------------------------------


def test_classify_tone_casual():
    assert _classify_tone("Keep a casual, friendly tone") == "casual"
    assert _classify_tone("friendly and natural") == "casual"
    print("PASS classify tone casual")


def test_classify_tone_professional():
    assert _classify_tone("Use a polished, professional tone") == "professional"
    assert _classify_tone("formal business tone") == "professional"
    print("PASS classify tone professional")


def test_classify_tone_neutral():
    assert _classify_tone("") == "neutral"
    assert _classify_tone("standard English") == "neutral"
    print("PASS classify tone neutral")


def test_classify_tone_technical():
    assert _classify_tone("technical documentation style") == "technical"
    print("PASS classify tone technical")


# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    tests = [
        test_subject_verb_agreement,
        test_multiple_sentences_preserved,
        test_empty_text,
        test_spelling,
        test_post_process_capitalize_first,
        test_post_process_capitalize_after_period,
        test_post_process_standalone_i,
        test_post_process_is_you,
        test_post_process_space_before_punctuation,
        test_post_process_no_forced_period,
        test_classify_tone_casual,
        test_classify_tone_professional,
        test_classify_tone_neutral,
        test_classify_tone_technical,
    ]

    failed = 0
    for test in tests:
        try:
            test()
        except Exception as e:
            print(f"FAIL {test.__name__}: {e}")
            failed += 1

    tool.close()

    print(f"\n{len(tests) - failed}/{len(tests)} tests passed.")
    if failed:
        sys.exit(1)
    print("All tests passed.")
