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

    messages = build_correction_messages(req.text, tone_modifier=req.tone)
    result = generate(messages, max_tokens=len(req.text) * 2)

    # Apply rule-based post-processing to catch what the model misses
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

    uvicorn.run(app, host="127.0.0.1", port=9274, log_level="info")
