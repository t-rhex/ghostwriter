"""Ghostwriter MLX LLM Server — FastAPI app for grammar correction and text elaboration."""

import logging
import re
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from prompts import build_elaboration_messages

logging.basicConfig(
    level=logging.INFO, format="[%(asctime)s] %(levelname)s: %(message)s"
)
logger = logging.getLogger("ghostwriter")

# ---------------------------------------------------------------------------
# Model loading (MLX — used for elaboration only)
# ---------------------------------------------------------------------------
_model = None
_tokenizer = None
MODEL_NAME = "mlx-community/Llama-3.2-3B-Instruct-4bit"


def get_model():
    global _model, _tokenizer
    if _model is None:
        logger.info(f"Loading model: {MODEL_NAME}")
        from mlx_lm import load

        _model, _tokenizer = load(MODEL_NAME)
        logger.info("Model loaded successfully.")
    return _model, _tokenizer


# ---------------------------------------------------------------------------
# LanguageTool loading (used for correction)
# ---------------------------------------------------------------------------
_language_tool = None


def get_language_tool():
    global _language_tool
    if _language_tool is None:
        logger.info("Loading LanguageTool...")
        import language_tool_python

        _language_tool = language_tool_python.LanguageTool("en-US")
        logger.info("LanguageTool loaded successfully.")
    return _language_tool


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load the model and LanguageTool eagerly at startup so first request is fast."""
    logger.info("Server starting — loading model and LanguageTool...")
    get_model()
    get_language_tool()
    logger.info("Model and LanguageTool ready. Server accepting requests.")
    yield
    logger.info("Server shutting down.")
    global _language_tool
    if _language_tool is not None:
        _language_tool.close()
        _language_tool = None
        logger.info("LanguageTool closed.")


# ---------------------------------------------------------------------------
# Tone-aware rule filtering for LanguageTool
# ---------------------------------------------------------------------------
TONE_DISABLED_CATEGORIES: dict[str, set[str]] = {
    "casual": {
        "STYLE",
        "REDUNDANCY",
        "COLLOQUIALISMS",
        "TYPOGRAPHY",
        "COMPOUNDING",
        "REPETITIONS_STYLE",
    },
    "professional": set(),  # max strictness
    "neutral": {"COLLOQUIALISMS", "REPETITIONS_STYLE"},
    "technical": set(),
}

TONE_DISABLED_RULES: dict[str, set[str]] = {
    "casual": {
        "UPPERCASE_SENTENCE_START",
        "EN_UNPAIRED_BRACKETS",
        "COMMA_PARENTHESIS_WHITESPACE",
        "DASH_RULE",
        "SENTENCE_WHITESPACE",
    },
    "professional": set(),
    "neutral": {"UPPERCASE_SENTENCE_START"},
    "technical": set(),
}


def _classify_tone(tone_modifier: str) -> str:
    """Classify the Swift tone string into a tone key for rule filtering."""
    if not tone_modifier:
        return "neutral"
    lower = tone_modifier.lower()
    if "casual" in lower or "friendly" in lower:
        return "casual"
    if "professional" in lower or "polished" in lower or "formal" in lower:
        return "professional"
    if "technical" in lower:
        return "technical"
    return "neutral"


# ---------------------------------------------------------------------------
# LanguageTool correction
# ---------------------------------------------------------------------------
def correct_with_languagetool(text: str, tone_modifier: str) -> str:
    """Correct text using LanguageTool with tone-aware rule filtering."""
    global _language_tool
    tone = _classify_tone(tone_modifier)
    disabled_categories = TONE_DISABLED_CATEGORIES.get(tone, set())
    disabled_rules = TONE_DISABLED_RULES.get(tone, set())

    import language_tool_python

    for attempt in range(2):
        try:
            tool = get_language_tool()
            matches = tool.check(text)

            # Filter matches by tone
            filtered = [
                m
                for m in matches
                if m.rule_id not in disabled_rules
                and m.category not in disabled_categories
            ]

            corrected = language_tool_python.utils.correct(text, filtered)
            return corrected
        except Exception as exc:
            logger.error(f"LanguageTool check failed (attempt {attempt + 1}/2): {exc}")
            # Discard the dead reference so get_language_tool() will reinit
            _language_tool = None
            if attempt == 0:
                logger.info("Reinitializing LanguageTool and retrying...")
                continue  # retry once after reinit
            raise HTTPException(
                status_code=503,
                detail="LanguageTool is temporarily unavailable. Please try again shortly.",
            )


# ---------------------------------------------------------------------------
# Post-processing: rule-based fixes LanguageTool might miss
# ---------------------------------------------------------------------------
def post_process(text: str) -> str:
    """Apply deterministic grammar rules as a safety net."""
    # --- Subject-verb agreement fixes ---
    # "is you" → "are you"
    text = re.sub(r"\bIs you\b", "Are you", text)
    text = re.sub(r"\bis you\b", "are you", text)
    # "is we" → "are we"
    text = re.sub(r"\bIs we\b", "Are we", text)
    text = re.sub(r"\bis we\b", "are we", text)
    # "is they" → "are they"
    text = re.sub(r"\bIs they\b", "Are they", text)
    text = re.sub(r"\bis they\b", "are they", text)
    # "was you" → "were you"
    text = re.sub(r"\bwas you\b", "were you", text)
    text = re.sub(r"\bWas you\b", "Were you", text)
    # "was we" → "were we"
    text = re.sub(r"\bwas we\b", "were we", text)
    text = re.sub(r"\bWas we\b", "Were we", text)
    # "was they" → "were they"
    text = re.sub(r"\bwas they\b", "were they", text)
    text = re.sub(r"\bWas they\b", "Were they", text)
    # "he/she/it don't" → "he/she/it doesn't"
    text = re.sub(r"\b(he|she|it) don\'t\b", r"\1 doesn't", text, flags=re.IGNORECASE)
    # "I/you/we/they doesn't" → "I/you/we/they don't"
    text = re.sub(
        r"\b(I|you|we|they) doesn\'t\b", r"\1 don't", text, flags=re.IGNORECASE
    )

    # --- Capitalization ---
    # Capitalize after sentence-ending punctuation (. ! ?)
    text = re.sub(
        r"([.!?])\s+([a-z])",
        lambda m: m.group(1) + " " + m.group(2).upper(),
        text,
    )

    # Capitalize first character
    if text and text[0].islower():
        text = text[0].upper() + text[1:]

    # Standalone "i" → "I"
    text = re.sub(r"(?<![a-zA-Z])i(?![a-zA-Z'])", "I", text)
    # "i'm" → "I'm", "i'll" → "I'll", "i've" → "I've", "i'd" → "I'd"
    text = re.sub(
        r"(?<![a-zA-Z])i('m|'ll|'ve|'d|'ve)\b", lambda m: "I" + m.group(1), text
    )

    # Remove space before punctuation (e.g., "it ?" → "it?")
    text = re.sub(r"\s+([.!?,;:])", r"\1", text)

    return text


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
app = FastAPI(title="Ghostwriter LLM Server", version="1.0.0", lifespan=lifespan)


class CorrectionRequest(BaseModel):
    text: str = Field(..., max_length=2000, description="Text to correct")
    tone: str = Field(default="", description="Tone modifier for correction style")


class ElaborationRequest(BaseModel):
    text: str = Field(..., max_length=2000, description="Text to elaborate")
    tone: str = Field(default="", description="Tone modifier for elaboration style")


class LLMResponse(BaseModel):
    result: str
    elapsed_ms: float


def generate(messages: list[dict], max_tokens: int = 512) -> str:
    """Generate a response from the MLX model."""
    from mlx_lm import generate as mlx_generate

    model, tokenizer = get_model()

    prompt = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    response = mlx_generate(
        model,
        tokenizer,
        prompt=prompt,
        max_tokens=max_tokens,
        verbose=False,
    )
    return response.strip()


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": MODEL_NAME,
        "model_loaded": _model is not None,
        "languagetool_loaded": _language_tool is not None,
    }


@app.get("/ready")
def ready():
    """Returns 200 only when the model and LanguageTool are loaded and ready."""
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")
    if _language_tool is None:
        raise HTTPException(status_code=503, detail="LanguageTool not loaded yet")
    return {"status": "ready", "model": MODEL_NAME, "languagetool": True}


@app.post("/v1/correct", response_model=LLMResponse)
def correct(req: CorrectionRequest):
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    logger.info(f"Correction request: {len(req.text)} chars")
    start = time.monotonic()

    result = correct_with_languagetool(req.text, tone_modifier=req.tone)
    result = post_process(result)

    elapsed = (time.monotonic() - start) * 1000
    logger.info(f"Correction done in {elapsed:.0f}ms")

    return LLMResponse(result=result, elapsed_ms=round(elapsed, 1))


@app.post("/v1/elaborate", response_model=LLMResponse)
def elaborate(req: ElaborationRequest):
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    logger.info(f"Elaboration request: {len(req.text)} chars")
    start = time.monotonic()

    messages = build_elaboration_messages(req.text, tone_modifier=req.tone)
    result = generate(messages, max_tokens=512)

    elapsed = (time.monotonic() - start) * 1000
    logger.info(f"Elaboration done in {elapsed:.0f}ms")

    return LLMResponse(result=result, elapsed_ms=round(elapsed, 1))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=9274, log_level="info", workers=2)
