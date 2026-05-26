"""Mock Ollama for CI: serves /api/tags and /api/embeddings with canned data.

Vector shape matches nomic-embed-text (768-dim). Returns all-zeros
vectors — retrieval quality is not tested in CI; only route shape,
count consistency, and version metadata.

The fixture corpus (tests/fixtures/corpus/) is also all-zeros, so query-
time embeddings vacuously "match" and /query returns deterministic results.
"""
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

EMBED_DIM = 768
ZERO = [0.0] * EMBED_DIM


@app.get("/api/tags")
def tags():
    """Mimic `ollama list` shape."""
    return {
        "models": [
            {"name": "nomic-embed-text:latest", "model": "nomic-embed-text:latest"},
        ]
    }


class EmbedRequest(BaseModel):
    model: str
    prompt: str | None = None
    input: str | list[str] | None = None


@app.post("/api/embeddings")
def embeddings(req: EmbedRequest):
    """Ollama-compatible embeddings endpoint. Returns zeros."""
    return {"embedding": ZERO}


@app.post("/api/embed")
def embed(req: EmbedRequest):
    """Newer Ollama embed endpoint. Returns zeros."""
    if isinstance(req.input, list):
        return {"embeddings": [ZERO for _ in req.input]}
    return {"embeddings": [ZERO]}
