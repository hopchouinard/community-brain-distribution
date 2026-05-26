# Tour

A quick orientation to what you just installed.

## The stack

```
┌──────────────────────────────────────────────────────┐
│  Open WebUI  (http://127.0.0.1:3000)                 │
│    - Chat interface                                  │
│    - The community-brain custom model                │
│    - The community-brain filter (injects retrieval)  │
│         │                                            │
│         ▼ /query                                     │
│  retrieval-server (http://127.0.0.1:8999)            │
│    - FastAPI, distribution mode (read-only)          │
│    - Hybrid retrieval (vector + BM25)                │
│    - LanceDB at ./corpus/lancedb/                    │
│         │                                            │
│         ▼ embedding lookup                           │
│  Ollama (http://localhost:11434)                     │
│    - nomic-embed-text (mandatory, ~250 MB)           │
│    - gpt-oss:20b (optional, local-LLM mode)          │
└──────────────────────────────────────────────────────┘
```

## What you can ask

The corpus contains coaching-call transcripts plus structured artifacts (extracted signal, community posts). Try questions like:

- "Find a quote from <speaker name> about <topic>"
- "What did we discuss about <topic> in <month>?"
- "Summarize recent discussions of <theme>"
- "Show me unresolved questions from <speaker>"

The filter injects retrieved chunks above your question and tells the LLM how to cite them. The trust contract (in the system prompt) instructs the LLM to:

- Quote only from `ground_truth` content (verbatim transcript text)
- Treat `derived_metadata` (LLM-extracted flags like `has_question`, `references_prior`) as provisional and re-derive as needed
- Always include session-ID citations

## Where things live

- `docker-compose.yml` — stack definition (image SHAs pinned)
- `.env.example` / `.env` — your local config (don't commit `.env`)
- `corpus/` — the LanceDB blob (don't commit)
- `community_brain_filter.py` — uploaded to Open WebUI in Step 8
- `inference-guidelines.md` — system prompt for the custom model
- `verify-install.sh` — run anytime to check stack health
- `download-corpus.sh` — fetch / update the corpus blob

## Updating

See the bottom of `INSTALL.md`.

## Loom walkthrough

[Placeholder for operator-recorded video; link to be added after first release.]
