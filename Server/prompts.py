"""System prompts and few-shot examples for the Ghostwriter LLM server."""

ELABORATION_SYSTEM_PROMPT = """You are a text continuation assistant. The user has typed the beginning of a sentence or thought. Your job is to provide a natural continuation that completes their text. Rules:
- Return ONLY the continuation text — the part that comes AFTER what the user typed
- Do NOT repeat or rephrase any of the user's original text
- Do NOT add explanations or quotation marks
- The continuation should flow naturally from the last word the user typed
- Keep it concise — 1-2 sentences maximum
- Match the tone indicated in the system context"""

ELABORATION_FEW_SHOT = [
    {"role": "user", "content": "meeting tmrw 3pm discuss"},
    {"role": "assistant", "content": " the budget and project timeline."},
    {"role": "user", "content": "thx for the help really"},
    {"role": "assistant", "content": " appreciate it!"},
    {"role": "user", "content": "I wanted to let you know that"},
    {
        "role": "assistant",
        "content": " the project is on track and we should be ready for the deadline.",
    },
]


def build_elaboration_messages(text: str, tone_modifier: str = "") -> list[dict]:
    """Build the full message list for an elaboration request."""
    system = ELABORATION_SYSTEM_PROMPT
    if tone_modifier:
        system += f"\n\nTone guidance: {tone_modifier}"

    messages = [{"role": "system", "content": system}]
    messages.extend(ELABORATION_FEW_SHOT)
    messages.append({"role": "user", "content": text})
    return messages
