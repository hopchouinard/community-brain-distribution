# Troubleshooting

Issues are grouped by which install step they typically surface in.

## Step 1: Docker / Ollama install

**"docker: command not found"**
Install Docker Desktop (Mac/Win) or `curl -fsSL https://get.docker.com | sh` (Linux). Add yourself to the `docker` group on Linux and log out/in.

**"docker compose: 'compose' is not a docker command"**
You have legacy `docker-compose` v1. Install Docker Desktop or the v2 plugin: `sudo apt install docker-compose-plugin`.

**Ollama installed but `ollama list` returns nothing**
Ollama service isn't running. macOS: open the Ollama app. Linux: `ollama serve` in a separate terminal. Then re-run `ollama pull nomic-embed-text`.

## Step 6: Corpus download

**"gh: command not found"**
Install GitHub CLI: `brew install gh` (Mac), `sudo apt install gh` (Linux/WSL).

**"release not found"**
The pinned `CORPUS_VERSION` in `download-corpus.sh` doesn't match a published release. Pull the latest distribution-repo commits: `git pull`.

**SHA-256 mismatch**
The downloaded tarball doesn't match the expected hash. Re-run `./download-corpus.sh` — likely a transient download corruption. If it persists, file an issue.

## Step 7: Stack startup

**"WEBUI_SECRET_KEY must be set in .env"**
You missed Step 5. `openssl rand -hex 32`, paste into `.env`.

**retrieval-server exits with "CorpusInvalidError"**
The corpus is missing the FTS index. Re-run `./download-corpus.sh`. If it still fails, file an issue with the docker logs output: `docker compose logs retrieval-server`.

**retrieval-server starts but `/health` is unreachable**
Check ports aren't taken: `lsof -iTCP:8999 -sTCP:LISTEN`. If a stale process holds the port, kill it.

**`/health.embedding_model` doesn't match manifest**
Your `.env` has a `COMMUNITY_BRAIN_EMBED_MODEL` override that disagrees with the corpus's embedding model. Comment out the override (or set it to match the manifest's value).

## Step 8: Open WebUI configuration

**The community-brain filter doesn't appear after upload**
Refresh the page. Then re-check Workspace → Functions; the filter should be in the list with a toggle. Some OWUI versions cache aggressively.

**Filter is uploaded but responses don't show `[corpus summary: ...]` header**
The filter isn't attached to the active model. Either toggle it on globally (Workspace → Functions → toggle the filter) or attach it explicitly to the community-brain model (Workspace → Models → community-brain → Functions tab).

**Inference connection missing in Settings → Connections**
Your `.env` block for the chosen mode isn't uncommented. Re-edit `.env`, then `docker compose restart open-webui`.

## Update path

**Git pull conflicts on `docker-compose.yml`**
You edited `docker-compose.yml` locally — possibly to expose a port to LAN, change OWUI version, etc. The release pipeline assumes the file is unmodified. Resolve by stashing your changes, pulling, and re-applying. If you want a permanent customization, document it in your own fork or in a side note.
