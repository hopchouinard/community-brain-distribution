#!/usr/bin/env bash
# verify-install.sh — verification harness for Tier B install.
#
# Run after each major install step, or end-to-end after Step 9.
# Idempotent. Per spec §7.
#
# Usage:
#   ./verify-install.sh                          # all checks
#   ./verify-install.sh --step N                 # checks for step N (1-9)
#   ./verify-install.sh --post-install           # end-to-end smoke
#   ./verify-install.sh --check-required-env     # warn if required .env keys
#                                                # (active in .env.example) are
#                                                # missing from local .env.
#                                                # Does NOT compare commented-out
#                                                # optional keys; those are
#                                                # opt-in by design.

set -uo pipefail   # NOT -e: we want to keep running after a single check fails

PASS_COUNT=0
FAIL_COUNT=0
declare -a FAILURES=()

# Color codes; degrade gracefully if not a TTY.
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; NC=''
fi

ok()  { PASS_COUNT=$((PASS_COUNT+1)); printf "${GREEN}[✓]${NC} %s\n" "$1"; }
bad() {
    FAIL_COUNT=$((FAIL_COUNT+1))
    FAILURES+=("$1")
    printf "${RED}[✗]${NC} %s\n" "$1"
    [[ -n "${2:-}" ]] && printf "    ${YELLOW}→${NC} %s\n" "$2"
}

# Detect SHA256 tool (macOS uses shasum -a 256; Linux uses sha256sum).
sha256_cmd() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        return 2
    fi
}

# === Individual checks ===

check_docker() {
    if command -v docker >/dev/null 2>&1; then
        ok "docker installed ($(docker --version 2>&1 | head -1))"
    else
        bad "docker not installed" "install Docker Desktop or docker-ce"
    fi

    if docker compose version >/dev/null 2>&1; then
        ok "docker compose v2 ($(docker compose version --short 2>&1))"
    else
        bad "docker compose v2 missing" \
            "v1 'docker-compose' is unsupported; upgrade to v2 plugin"
    fi
}

check_ollama() {
    local url="${OLLAMA_BASE_URL:-http://host.docker.internal:11434}"
    # Convert host.docker.internal to localhost for direct testing from
    # the recipient's shell (not from inside a container).
    local probe_url="${url/host.docker.internal/localhost}"
    if curl -sf "${probe_url}/api/tags" >/dev/null 2>&1; then
        ok "Ollama reachable at ${probe_url}"
        if curl -s "${probe_url}/api/tags" | grep -q '"name":\s*"nomic-embed-text'; then
            ok "nomic-embed-text model is pulled"
        else
            bad "nomic-embed-text model not in Ollama" \
                "run: ollama pull nomic-embed-text"
        fi
    else
        bad "Ollama not reachable at ${probe_url}" \
            "start Ollama (mac/win: open Ollama app; linux: ollama serve)"
    fi
}

check_env_file() {
    if [[ ! -f .env ]]; then
        bad ".env does not exist" "run: cp .env.example .env  and fill in the required values"
        return
    fi
    ok ".env exists"

    # WEBUI_SECRET_KEY must be set and non-empty.
    if grep -qE '^WEBUI_SECRET_KEY=.+' .env; then
        ok "WEBUI_SECRET_KEY is set"
    else
        bad "WEBUI_SECRET_KEY is empty" \
            "generate one: openssl rand -hex 32 and paste into .env"
    fi

    # Exactly one inference block uncommented.
    local local_set=0 cloud_set=0
    grep -qE '^INFERENCE_LOCAL_MODEL=' .env && local_set=1
    grep -qE '^OPENAI_API_BASE_URL=' .env && cloud_set=1
    if (( local_set + cloud_set == 0 )); then
        bad "no inference mode configured" \
            "uncomment EXACTLY ONE block in .env (Option A or Option B)"
    elif (( local_set + cloud_set == 2 )); then
        bad "both inference modes configured" \
            "uncomment EXACTLY ONE block in .env, not both"
    else
        ok "exactly one inference mode configured"
    fi
}

check_corpus() {
    if [[ ! -d ./corpus ]]; then
        bad "./corpus directory missing" "run: ./download-corpus.sh"
        return
    fi
    if [[ ! -d ./corpus/lancedb/nomic-v1/chunks.lance ]]; then
        bad "./corpus/lancedb/nomic-v1/chunks.lance missing" \
            "run: ./download-corpus.sh (your corpus is incomplete)"
        return
    fi
    ok "corpus directory present"

    if [[ ! -f ./corpus/corpus-manifest.json ]]; then
        bad "./corpus/corpus-manifest.json missing" \
            "run: ./download-corpus.sh"
        return
    fi
    ok "corpus-manifest.json present"
}

check_stack_running() {
    if ! docker compose ps --status running 2>/dev/null | grep -q retrieval-server; then
        bad "retrieval-server container is not running" \
            "run: docker compose up -d"
        return
    fi
    ok "retrieval-server container running"

    if ! docker compose ps --status running 2>/dev/null | grep -q open-webui; then
        bad "open-webui container is not running" \
            "run: docker compose up -d"
        return
    fi
    ok "open-webui container running"

    # Check 127.0.0.1 binding (not 0.0.0.0).
    local rs_binding
    rs_binding=$(docker compose port retrieval-server 8999 2>/dev/null || echo "")
    if [[ "$rs_binding" == *"127.0.0.1"* ]]; then
        ok "retrieval-server bound to 127.0.0.1"
    else
        bad "retrieval-server binding looks wrong: ${rs_binding}" \
            "compose.yml ports: should be \"127.0.0.1:8999:8999\""
    fi
}

check_health_and_manifest_match() {
    local health_json
    health_json=$(curl -sf http://127.0.0.1:8999/health 2>/dev/null || echo "")
    if [[ -z "$health_json" ]]; then
        bad "/health unreachable on 127.0.0.1:8999" \
            "check: docker compose logs retrieval-server"
        return
    fi
    ok "/health returns 200"

    if ! command -v jq >/dev/null 2>&1; then
        bad "jq not installed" "install jq (brew install jq or apt install jq)"
        return
    fi

    local server_schema server_embed server_dm
    server_schema=$(echo "$health_json" | jq -r '.schema_version')
    server_embed=$(echo "$health_json" | jq -r '.embedding_model')
    server_dm=$(echo "$health_json" | jq -r '.distribution_mode')

    if [[ "$server_dm" != "true" ]]; then
        bad "/health.distribution_mode is not true: ${server_dm}" \
            "image was built without COMMUNITY_BRAIN_DISTRIBUTION_MODE=true in compose"
    else
        ok "/health.distribution_mode is true"
    fi

    if [[ ! -f ./corpus/corpus-manifest.json ]]; then
        return  # already reported by check_corpus
    fi
    local manifest_schema manifest_embed
    manifest_schema=$(jq -r '.schema_version' ./corpus/corpus-manifest.json)
    manifest_embed=$(jq -r '.embedding_model' ./corpus/corpus-manifest.json)

    if [[ "$server_schema" == "$manifest_schema" ]]; then
        ok "schema_version matches (${server_schema})"
    else
        bad "schema_version mismatch: server=${server_schema} corpus=${manifest_schema}" \
            "re-fetch corpus: ./download-corpus.sh"
    fi
    if [[ "$server_embed" == "$manifest_embed" ]]; then
        ok "embedding_model matches (${server_embed})"
    else
        bad "embedding_model mismatch: server=${server_embed} corpus=${manifest_embed}" \
            "your server and corpus were embedded by different models"
    fi
}

check_sessions_count_matches_manifest() {
    if [[ ! -f ./corpus/corpus-manifest.json ]]; then return; fi
    if ! command -v jq >/dev/null 2>&1; then return; fi
    local expected actual
    expected=$(jq -r '.session_count' ./corpus/corpus-manifest.json)
    actual=$(curl -sf http://127.0.0.1:8999/sessions 2>/dev/null \
             | jq -r '.sessions | length' 2>/dev/null || echo "")
    if [[ -z "$actual" ]]; then
        bad "/sessions unreachable or malformed" \
            "check: docker compose logs retrieval-server"
        return
    fi
    if [[ "$expected" == "$actual" ]]; then
        ok "/sessions count matches manifest (${expected})"
    else
        bad "/sessions count mismatch: server=${actual} manifest=${expected}" \
            "corpus mount may be wrong; check docker compose config"
    fi
}

check_owui_reachable() {
    if curl -sf http://127.0.0.1:3000 -o /dev/null; then
        ok "Open WebUI reachable on 127.0.0.1:3000"
    else
        bad "Open WebUI not reachable on 127.0.0.1:3000" \
            "check: docker compose logs open-webui"
    fi
}

# === Step dispatchers ===

run_step_1() { check_docker; }
run_step_2() { check_ollama; }
run_step_4() { [[ -d .git ]] && ok "in a git checkout" || bad "not a git checkout" "git clone the distribution repo, then cd in"; }
run_step_5() { check_env_file; }
run_step_6() { check_corpus; }
run_step_7() { check_stack_running; check_health_and_manifest_match; }

run_post_install() {
    check_docker
    check_ollama
    check_env_file
    check_corpus
    check_stack_running
    check_health_and_manifest_match
    check_sessions_count_matches_manifest
    check_owui_reachable
}

run_all() { run_post_install; }

# === Main ===

MODE="all"
STEP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --step) MODE="step"; STEP="$2"; shift 2 ;;
        --post-install) MODE="post"; shift ;;
        --check-required-env) MODE="required-env-drift"; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Load .env if present so OLLAMA_BASE_URL etc. are visible to checks.
if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

case "$MODE" in
    all)        run_all ;;
    post)       run_post_install ;;
    step)
        case "$STEP" in
            1) run_step_1 ;;
            2) run_step_2 ;;
            4) run_step_4 ;;
            5) run_step_5 ;;
            6) run_step_6 ;;
            7) run_step_7 ;;
            *) echo "Unknown step: $STEP (valid: 1, 2, 4, 5, 6, 7)" >&2; exit 2 ;;
        esac ;;
    required-env-drift)
        # Compare only ACTIVE (uncommented) keys in .env.example to keys in
        # the recipient's .env. Commented optional keys are intentionally
        # opt-in and not flagged as missing.
        if [[ ! -f .env ]]; then
            bad ".env missing" "cp .env.example .env"
        else
            required_keys=$(grep -oE '^[A-Z_]+=' .env.example | sort -u)
            actual_keys=$(grep -oE '^[A-Z_]+=' .env | sort -u)
            missing=$(comm -23 <(echo "$required_keys") <(echo "$actual_keys"))
            if [[ -n "$missing" ]]; then
                bad "missing required keys in .env vs .env.example:" "$(echo "$missing" | tr '\n' ' ')"
            else
                ok ".env has all required keys from .env.example"
            fi
        fi ;;
esac

echo
if (( FAIL_COUNT == 0 )); then
    printf "${GREEN}All checks passed${NC} (%d)\n" "$PASS_COUNT"
    exit 0
else
    printf "${RED}%d failed${NC} (%d passed)\n" "$FAIL_COUNT" "$PASS_COUNT"
    exit 1
fi
