#!/usr/bin/env bash
# build-fixture.sh — construct a tiny clean-v3 LanceDB for CI fixtures.
#
# Run this once during initial setup or when fixture format needs to change.
# Output: tests/fixtures/corpus/lancedb/nomic-v1/chunks.lance/...
#         tests/fixtures/corpus/corpus-manifest.json

set -euo pipefail

FIXTURE_ROOT="$(cd "$(dirname "$0")" && pwd)"
CORPUS="${FIXTURE_ROOT}/corpus"

# Default venv path: operator repo is at /home/pchouinard/n8n/ on the VM
# dev environment. Override via COMMUNITY_BRAIN_VENV if the operator repo
# lives elsewhere.
DEFAULT_VENV="/home/pchouinard/n8n/community-brain/.venv"
PYTHON="${COMMUNITY_BRAIN_VENV:-$DEFAULT_VENV}/bin/python"

if [[ ! -x "$PYTHON" ]]; then
    echo "ERROR: python venv not found at $(dirname "$PYTHON")" >&2
    echo "  Either set COMMUNITY_BRAIN_VENV pointing at a venv that has the" >&2
    echo "  community-brain package installed, or ensure the operator repo" >&2
    echo "  is checked out at /home/pchouinard/n8n/." >&2
    echo "  Expected: $DEFAULT_VENV/bin/python" >&2
    exit 2
fi

rm -rf "$CORPUS"
mkdir -p "$CORPUS/lancedb/nomic-v1"

"$PYTHON" - <<PYEOF
import json, pathlib
import lancedb

# Reuse the REAL pyarrow schema so every column /sessions reads
# (session_date, session_title, content_type, has_unresolved_question,
# session_themes) and every field the server expects (e.g. \`embedding\`,
# not \`vector\`) is present. Anything less makes _load_all_session_rows()
# return empty and verify-install.sh fails on count-mismatch.
from community_brain.ingestion.schema import pyarrow_table_schema, SCHEMA_VERSION

DB_PATH = "${CORPUS}/lancedb/nomic-v1"
db = lancedb.connect(DB_PATH)
schema = pyarrow_table_schema()
table = db.create_table("chunks", schema=schema, mode="overwrite")

# Build a minimal row that satisfies every NOT-NULL column in the
# real schema. The pyarrow_table_schema() function is authoritative;
# we synthesize values from its field names rather than hand-coding.
import datetime as _dt
import pyarrow.types as _pat

pa_types_is_string = _pat.is_string
pa_types_is_floating = _pat.is_floating
pa_types_is_integer = _pat.is_integer
pa_types_is_boolean = _pat.is_boolean
pa_types_is_timestamp = _pat.is_timestamp
pa_types_is_date = _pat.is_date
pa_types_is_fixed_size_list = _pat.is_fixed_size_list
pa_types_is_list = _pat.is_list
pa_types_is_struct = _pat.is_struct


def _default_for_field(field):
    """Best-effort default value matching a pyarrow field type."""
    t = field.type
    if pa_types_is_string(t):
        if field.name in ("session_id", "chunk_id", "bm25_text",
                          "session_title", "content_type", "extraction_status"):
            return f"fixture-{field.name}"
        return ""
    if pa_types_is_floating(t):
        return 0.0
    if pa_types_is_integer(t):
        return 0
    if pa_types_is_boolean(t):
        return False
    if pa_types_is_timestamp(t) or pa_types_is_date(t):
        return _dt.datetime(2026, 5, 10, 0, 0, 0, tzinfo=_dt.timezone.utc)
    if pa_types_is_fixed_size_list(t):
        return [0.0] * t.list_size  # 768-dim zero embedding
    if pa_types_is_list(t):
        return []
    if pa_types_is_struct(t):
        return None
    return None


def _make_row(session_id, chunk_id, bm25_text):
    row = {f.name: _default_for_field(f) for f in schema}
    row["session_id"] = session_id
    row["chunk_id"] = chunk_id
    row["bm25_text"] = bm25_text
    if "extraction_status" in row:
        row["extraction_status"] = "success"
    if "session_date" in row:
        row["session_date"] = _dt.datetime(2026, 1, 1, tzinfo=_dt.timezone.utc)
    if "session_title" in row:
        row["session_title"] = f"Fixture session {session_id}"
    if "content_type" in row:
        row["content_type"] = "prepared_transcript"
    if "has_unresolved_question" in row:
        row["has_unresolved_question"] = False
    return row


rows = [
    _make_row("fixture-001", "fixture-001:c0", "hello fixture corpus"),
    _make_row("fixture-001", "fixture-001:c1", "second chunk of fixture-001"),
    _make_row("fixture-002", "fixture-002:c0", "another fixture session"),
]
table.add(rows)
table.create_fts_index("bm25_text", replace=True)

manifest = {
    "corpus_version": "v0.0.0-fixture",
    "schema_version": SCHEMA_VERSION,
    "embedding_model": "nomic-embed-text",
    "session_count": 2,
    "chunk_count": 3,
    "generation_timestamp_utc": "2026-05-10T00:00:00Z",
}
pathlib.Path("${CORPUS}/corpus-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"fixture built at ${CORPUS} (schema_version={SCHEMA_VERSION})")
PYEOF
