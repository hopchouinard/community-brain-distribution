#!/usr/bin/env bash
# download-corpus.sh — fetch + verify + extract the Tier B corpus.
#
# Idempotent: re-running with the same CORPUS_VERSION already-extracted
# exits 0 without re-fetching. Rollback rotation: existing ./corpus/ is
# moved to ./corpus.previous/ (one level kept).
#
# Per spec §5.5.

set -euo pipefail

# === Pinned by operator on each corpus release ===
CORPUS_VERSION="v1.0.0"
EXPECTED_SHA256="4947745526bcaabc4a5a4d84c461d3956c33aa37b493f8f4b7543d747ef1c6d0"
RELEASE_REPO="hopchouinard/community-brain-distribution"
# =================================================

CORPUS_DIR="./corpus"
PREVIOUS_DIR="./corpus.previous"

log() { echo "[download-corpus] $*" >&2; }

# Detect SHA tool.
sha256_of() {
    local f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" | awk '{print $1}'
    else
        log "ERROR: neither sha256sum nor shasum found; install one"
        exit 2
    fi
}

# Idempotency short-circuit: already at target version?
if [[ -f "${CORPUS_DIR}/corpus-manifest.json" ]]; then
    if command -v jq >/dev/null 2>&1; then
        current=$(jq -r '.corpus_version' "${CORPUS_DIR}/corpus-manifest.json" 2>/dev/null || echo "")
        if [[ "$current" == "$CORPUS_VERSION" ]]; then
            log "corpus already at ${CORPUS_VERSION}; nothing to do"
            exit 0
        fi
    fi
fi

# Need gh CLI for release asset downloads (works on public + private alike).
if ! command -v gh >/dev/null 2>&1; then
    log "ERROR: gh CLI is required to download release assets"
    log "  install: https://cli.github.com/"
    exit 2
fi

# Fetch into a tmp dir to avoid touching ./corpus until validated.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

log "fetching corpus ${CORPUS_VERSION} from ${RELEASE_REPO}"
cd "$TMP"
gh release download "${CORPUS_VERSION}" \
    --repo "${RELEASE_REPO}" \
    --pattern "corpus-${CORPUS_VERSION}.tar.gz" \
    --pattern "sha256sum.txt" \
    --pattern "corpus-manifest.json"

# Verify SHA-256.
log "verifying SHA-256"
actual=$(sha256_of "corpus-${CORPUS_VERSION}.tar.gz")
if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
    log "ERROR: SHA-256 mismatch"
    log "  expected: $EXPECTED_SHA256"
    log "  actual:   $actual"
    log "  the download may be corrupt or the EXPECTED_SHA256 constant is stale"
    exit 1
fi
log "SHA-256 verified"

# Rollback rotation.
cd - >/dev/null
if [[ -d "$PREVIOUS_DIR" ]]; then
    log "removing old rollback at ${PREVIOUS_DIR}"
    rm -rf "$PREVIOUS_DIR"
fi
if [[ -d "$CORPUS_DIR" ]]; then
    log "rotating ${CORPUS_DIR} -> ${PREVIOUS_DIR}"
    mv "$CORPUS_DIR" "$PREVIOUS_DIR"
fi

# Extract.
mkdir -p "$CORPUS_DIR"
log "extracting tarball into ${CORPUS_DIR}"
tar -xzf "$TMP/corpus-${CORPUS_VERSION}.tar.gz" -C "$CORPUS_DIR"
cp "$TMP/corpus-manifest.json" "${CORPUS_DIR}/corpus-manifest.json"

log "corpus ${CORPUS_VERSION} ready"
log "  $(ls -lh "${CORPUS_DIR}/corpus-manifest.json" | awk '{print $5, $9}')"
log "  $(du -sh "${CORPUS_DIR}/lancedb" 2>/dev/null || true)"
