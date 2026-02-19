"""Ghostwriter MLX LLM Server — FastAPI app for grammar correction and text elaboration."""

import logging
import re
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from prompts import build_correction_messages, build_elaboration_messages

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] %(levelname)s: %(message)s")
logger = logging.getLogger("ghostwriter")

# ---------------------------------------------------------------------------
# Model loading
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


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load the model eagerly at startup so first request is fast."""
    logger.info("Server starting — loading model...")
    get_model()
    logger.info("Model ready. Server accepting requests.")
    yield
    logger.info("Server shutting down.")


# ---------------------------------------------------------------------------
# Post-processing: rule-based fixes the LLM might miss
# ---------------------------------------------------------------------------
def post_process(text: str) -> str:
    """Apply deterministic grammar rules that small models often miss."""
    # --- Subject-verb agreement fixes ---
    # "is you" → "are you"
    text = re.sub(r'\bIs you\b', 'Are you', text)
    text = re.sub(r'\bis you\b', 'are you', text)
    # "is we" → "are we"
    text = re.sub(r'\bIs we\b', 'Are we', text)
    text = re.sub(r'\bis we\b', 'are we', text)
    # "is they" → "are they"
    text = re.sub(r'\bIs they\b', 'Are they', text)
    text = re.sub(r'\bis they\b', 'are they', text)
    # "was you" → "were you"
    text = re.sub(r'\bwas you\b', 'were you', text)
    text = re.sub(r'\bWas you\b', 'Were you', text)
    # "was we" → "were we"
    text = re.sub(r'\bwas we\b', 'were we', text)
    text = re.sub(r'\bWas we\b', 'Were we', text)
    # "was they" → "were they"
    text = re.sub(r'\bwas they\b', 'were they', text)
    text = re.sub(r'\bWas they\b', 'Were they', text)
    # "he/she/it don't" → "he/she/it doesn't"
    text = re.sub(r'\b(he|she|it) don\'t\b', r"\1 doesn't", text, flags=re.IGNORECASE)
    # "I/you/we/they doesn't" → "I/you/we/they don't"
    text = re.sub(r'\b(I|you|we|they) doesn\'t\b', r"\1 don't", text, flags=re.IGNORECASE)

    # --- Capitalization ---
    # Capitalize after sentence-ending punctuation (. ! ?)
    text = re.sub(
        r'([.!?])\s+([a-z])',
        lambda m: m.group(1) + " " + m.group(2).upper(),
        text,
    )

    # Capitalize first character
    if text and text[0].islower():
        text = text[0].upper() + text[1:]

    # Standalone "i" → "I"
    text = re.sub(r"(?<![a-zA-Z])i(?![a-zA-Z'])", "I", text)
    # "i'm" → "I'm", "i'll" → "I'll", "i've" → "I've", "i'd" → "I'd"
    text = re.sub(r"(?<![a-zA-Z])i('m|'ll|'ve|'d|'ve)\b", lambda m: "I" + m.group(1), text)

    # Add period at end if missing punctuation
    stripped = text.rstrip()
    if stripped and stripped[-1] not in ".!?,:;…":
        text = stripped + "."

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

    prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    response = mlx_generate(
        model,
        tokenizer,
        prompt=prompt,
        max_tokens=max_tokens,
        verbose=False,
    )
    return response.strip()


def _split_sentences(text: str) -> list[str]:
    """Split text into sentences, preserving the delimiters."""
    parts = re.split(r'(?<=[.!?])\s+', text.strip())
    return [p for p in parts if p.strip()]


def correct_with_fallback(text: str, tone_modifier: str) -> str:
    """Correct text, falling back to per-sentence correction if the model drops content."""
    # Try full-text correction first
    messages = build_correction_messages(text, tone_modifier=tone_modifier)
    result = generate(messages, max_tokens=len(text) * 2)
    result = post_process(result)

    # Validate: if model dropped sentences, fall back to per-sentence correction
    input_sentences = _split_sentences(text)
    output_sentences = _split_sentences(result)

    if len(input_sentences) > 1 and len(output_sentences) < len(input_sentences):
        logger.warning(
            f"Model dropped sentences ({len(input_sentences)} → {len(output_sentences)}). "
            "Falling back to per-sentence correction."
        )
        corrected_parts = []
        for sentence in input_sentences:
            msgs = build_correction_messages(sentence, tone_modifier=tone_modifier)
            corrected = generate(msgs, max_tokens=len(sentence) * 2)
            corrected = post_process(corrected)
            corrected_parts.append(corrected)
        result = " ".join(corrected_parts)

    return result


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_NAME, "model_loaded": _model is not None}


@app.get("/ready")
def ready():
    """Returns 200 only when the model is loaded and ready for inference."""
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")
    return {"status": "ready", "model": MODEL_NAME}


@app.post("/v1/correct", response_model=LLMResponse)
def correct(req: CorrectionRequest):
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")

    logger.info(f"Correction request: {len(req.text)} chars")
    start = time.monotonic()

    result = correct_with_fallback(req.text, tone_modifier=req.tone)

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

    uvicorn.run(app, host="127.0.0.1", port=9274, log_level="info")
