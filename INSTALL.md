# Community Brain — Install Guide

A retrieval interface over a curated coaching-call corpus. Search the calls you were on; ask questions and get cited answers.

**If you use an AI coding assistant** (Claude Code, Codex, Cursor, Gemini CLI, Aider, etc.):
> Open this file in that assistant and say: "Follow this install guide on my machine. Run `./verify-install.sh` between major steps. If a step fails verification, fix it before continuing. Ask me for confirmation before any installs that need sudo or before pasting anything I would need to authorize."

The rest of this doc is written so an agent can drive it. Humans follow the same instructions by hand.

---

## 0. Before You Start

### Hardware
- **Minimum:** 8 GB RAM, ~5 GB free disk.
- **For local-LLM mode (Option A in Step 5):** 24+ GB unified memory (Apple Silicon) or a beefy GPU (Linux). Cloud mode skips this requirement.

### Software prerequisites (all platforms)
- `git` — any modern version
- `docker` + `docker compose` v2 — Docker Desktop on Mac/Windows, `docker-ce` on Linux
- `ollama` — native installer on Mac/Linux; inside Ubuntu WSL on Windows
- `curl`, `tar`, `jq`, `openssl` — preinstalled on macOS/Linux; `apt install jq` if missing on WSL/Ubuntu
- `gh` (GitHub CLI) — used by `download-corpus.sh`
- SHA-256 tool — `sha256sum` (Linux/WSL) or `shasum -a 256` (macOS); scripts auto-detect

### Windows
Install Docker Desktop with WSL2 backend + Ubuntu, and run every command in this guide from an **Ubuntu WSL2 shell**, not PowerShell or Git Bash. The distribution ships Bash-shaped tooling; native Windows is unsupported in v1.

### Pick your inference mode
- **Option A — Local LLM** (Ollama with gpt-oss:20b). Free to run, requires 24+ GB unified memory.
- **Option B — Cloud LLM** (OpenAI, OpenRouter, Anthropic, Gemini, etc.). You pay per query, no hardware requirement beyond the embedding model.

You can switch between modes later by editing `.env` and restarting the stack.

---

## 1. Install Docker + Ollama

### macOS
```bash
# Docker Desktop or OrbStack: download from their websites.
# Then install Ollama:
brew install --cask ollama
# Or: download from https://ollama.com/download
```

Verify:
```bash
docker --version
docker compose version
ollama --version
```

### Linux
```bash
# Docker:
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for group change to take effect.

# Ollama:
curl -fsSL https://ollama.com/install.sh | sh
```

### Windows (inside Ubuntu WSL2)
```bash
# Docker Desktop is installed on Windows side. Ollama goes inside WSL:
curl -fsSL https://ollama.com/install.sh | sh
```

Verify (in WSL Ubuntu shell):
```bash
docker --version
docker compose version
ollama --version
```

**Verify:** `./verify-install.sh --step 1` (after Step 4 makes the script available).

---

## 2. Pull the embedding model

```bash
ollama pull nomic-embed-text
```

This is ~250 MB and runs CPU-only. Required regardless of which inference mode you pick — query-time embeddings must match the corpus's pre-built vectors.

Verify:
```bash
ollama list | grep nomic-embed-text
```

---

## 3. (Optional, local-LLM mode only) Pull the chat model

Skip this step if you're using Option B (cloud LLM) in Step 5.

```bash
ollama pull gpt-oss:20b
```

This is ~12 GB. Requires the hardware noted in Step 0.

Verify:
```bash
ollama list | grep gpt-oss
```

---

## 4. Clone the distribution repo

```bash
git clone https://github.com/hopchouinard/community-brain-distribution
cd community-brain-distribution
./verify-install.sh --step 4
```

---

## 5. Configure your .env

```bash
cp .env.example .env
```

Open `.env` in your editor. Set the required values:

- `WEBUI_SECRET_KEY`: generate with `openssl rand -hex 32`, paste the output here.
- `OLLAMA_BASE_URL`: leave at `http://host.docker.internal:11434` unless you have a custom Ollama setup.

Then **uncomment exactly one inference block**:

- **Option A — Local Ollama chat**: uncomment the `INFERENCE_LOCAL_MODEL=gpt-oss:20b` line.
- **Option B — Cloud chat**: uncomment all three `OPENAI_API_*` and `INFERENCE_CLOUD_MODEL` lines, and fill in your API base URL, key, and model name.

For OpenRouter (which proxies Anthropic, Gemini, OpenAI, etc.):
- `OPENAI_API_BASE_URL=https://openrouter.ai/api/v1`
- `OPENAI_API_KEY=sk-or-v1-...` (get one at https://openrouter.ai/keys)
- `INFERENCE_CLOUD_MODEL=anthropic/claude-sonnet-4.6` (or another model from https://openrouter.ai/models)

Verify:
```bash
./verify-install.sh --step 5
```

---

## 6. Download the corpus

```bash
./download-corpus.sh
```

This fetches ~600-900 MB and extracts to `./corpus/`. On second run with the same version, it short-circuits to a no-op.

If you ever need to roll back, `./corpus.previous/` keeps the immediately-prior version.

Verify:
```bash
./verify-install.sh --step 6
```

---

## 7. Start the stack

```bash
docker compose up -d
```

This pulls the pinned `retrieval-server` and `open-webui` images (first run only; ~500 MB total) and starts both containers.

Verify:
```bash
./verify-install.sh --step 7
```

This checks:
- Both containers running
- Ports bound to `127.0.0.1` (not LAN-exposed)
- `/health` returns 200 with `distribution_mode: true`
- `/health.schema_version` matches `corpus-manifest.json`
- `/health.embedding_model` matches `corpus-manifest.json`

---

## 8. Configure Open WebUI

Open `http://127.0.0.1:3000` in your browser. First user becomes admin.

### 8a. Verify the inference connection (already auto-configured from .env)

Settings → Connections.

- **Local mode (Option A):** the Ollama section should show your Ollama endpoint populated from `OLLAMA_BASE_URL`. Confirm the connection reports as available.
- **Cloud mode (Option B):** the OpenAI section should show your endpoint and a redacted API key populated from `OPENAI_API_BASE_URL` and `OPENAI_API_KEY`. Confirm the connection reports as available.

**You do NOT paste credentials in the GUI.** They came in via `.env`. If a connection is missing here, return to Step 5 and verify the `.env` block for your chosen mode is uncommented and filled in.

### 8b. Create the custom "community-brain" model

Workspace → Models → New Model.

- **Name:** `community-brain`
- **Base model:** `gpt-oss:20b` (local mode) or your cloud model (e.g. `anthropic/claude-sonnet-4.6`)
- **System prompt:** open `inference-guidelines.md` (in this directory) and paste the entire file content into the system-prompt field.
- Save.

### 8c. Upload + enable the filter

Workspace → Functions → Import Function.

- Select `community_brain_filter.py` from this directory.
- After upload, find the filter in the list and:
  - Toggle it ON globally, OR
  - Attach it to the `community-brain` model from Step 8b.

### 8d. Configure the filter valves

Open the filter's valve settings (the gear icon next to it in Workspace →
Functions).

- `retrieval_url` — defaults to `http://host.docker.internal:8999/query`,
  which is correct for this compose stack. Leave it unless you moved the
  retrieval server.
- `api_key` — leave empty unless you put an authenticating proxy in front of
  the retrieval server.
- `citation_guard` (new in v1.1.0) — `annotate` (default: appends an automated
  "Grounding check" warning when the model cites session dates or sources that
  are not in the retrieved context), `strip` (also redacts those tokens), or
  `off`.

> **Re-uploading the filter resets ALL valves to their defaults.** Re-set
> `retrieval_url`, `api_key`, and `citation_guard` after every upload.

---

## 9. End-to-end validation

### 9a. Server-side checks (deterministic)

```bash
curl -s http://127.0.0.1:8999/sessions | jq '.sessions | length'
```
Expected: matches `session_count` in `./corpus/corpus-manifest.json`.

```bash
curl -s http://127.0.0.1:8999/health | jq '{schema_version, embedding_model}'
jq '{schema_version, embedding_model}' ./corpus/corpus-manifest.json
```
Expected: both fields match between server and manifest.

### 9b. Open WebUI retrieval smoke test (qualitative)

In OWUI chat, select the `community-brain` model. Send a content question you know the corpus can answer, e.g.:

> Summarize a recent discussion about pricing in the coaching calls.

Expected: the response contains a `[corpus summary: of the N retrieved chunks, ...]` line above the answer (rendered by the filter), and citations include session IDs that match values from `/sessions`. Click a citation; it should show a quote that resolves to actual corpus content.

If the response doesn't include the `[corpus summary: ...]` line: the filter is not attached. Re-check Step 8c.

---

## Troubleshooting

See [`docs/troubleshooting.md`](./docs/troubleshooting.md).

---

## Updating to a new release

```bash
git pull
./verify-install.sh --check-required-env  # warn if new required keys appeared in .env.example
./download-corpus.sh                    # no-op if CORPUS_VERSION unchanged
docker compose pull                     # grab new image SHAs from compose.yml
docker compose up -d                    # restart with new images
./verify-install.sh --post-install      # confirm green
```

6. If the release notes say the filter changed, re-upload
   `community_brain_filter.py` in Open WebUI and re-set its valves (Step 8d).
   **v1.1.0 changed the filter** — this step is required when upgrading from
   v1.0.0.
