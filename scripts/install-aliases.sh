#!/usr/bin/env bash
# scripts/install-aliases.sh — create Ollama Modelfile aliases from
# config/ollama/Modelfile.* recipes.
#
# Reads every Modelfile in config/ollama/, extracts its FROM (the base
# model tag), verifies that the base family is present in the local
# Ollama library, and runs `ollama create <alias> -f <file>` for each.
# Closes the gap where Modelfile recipes are checked in but never
# applied to the running Ollama — see the v0.3.0 audit notes.
#
# Idempotent. `ollama create` overwrites an existing alias with the new
# Modelfile, so re-running after a Modelfile edit is safe.
#
# Usage:
#   scripts/install-aliases.sh                 # all Modelfiles, skip if base missing
#   scripts/install-aliases.sh qwen3.8         # only Modelfiles whose FROM contains this
#
# The optional argument is a substring filter on the FROM tag. Use it
# after a partial pull to silence warnings on bases you haven't pulled.

set -euo pipefail

# Resolve repo root: this script lives in <repo>/scripts/.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELDIR="${REPO_ROOT}/config/ollama"

FILTER="${1:-}"

if ! curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "ollama is not reachable at 127.0.0.1:11434" >&2
  echo "  systemctl status ollama  /  journalctl -u ollama -n 50" >&2
  exit 2
fi

# Build the set of base tags already present in the local Ollama library.
# One tag per line, used for substring match against the Modelfile's FROM.
LOCAL_BASES=$(curl -fsS http://127.0.0.1:11434/api/tags \
  | jq -r '.models[].name // empty' 2>/dev/null || true)

if [ -z "${LOCAL_BASES}" ]; then
  echo "warning: no models registered with Ollama yet; nothing to alias" >&2
  echo "  run scripts/pull-models.sh first" >&2
  exit 0
fi

CREATED=0
SKIPPED=0
FAIL=0

shopt -s nullglob
for mf in "${MODELDIR}"/Modelfile.*; do
  # Extract the FROM tag. First line whose first token is "from" (case-insensitive).
  base=$(awk 'tolower($1)=="from" {print $2; exit}' "${mf}")
  if [ -z "${base}" ]; then
    echo "  skip ${mf##*/} (no FROM line)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Apply optional substring filter on the FROM tag.
  if [ -n "${FILTER}" ] && [[ "${base}" != *"${FILTER}"* ]]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Derive the alias name from the Modelfile basename:
  #   Modelfile.qwen3-27b        -> qwen3-27b
  #   Modelfile.qwen3-27b-thinking -> qwen3-27b-thinking
  alias_name="${mf##*/Modelfile.}"

  # Two FROM shapes are supported:
  #   1. A library tag (`qwen3.8:27b`) — check the base family is pulled.
  #   2. A local GGUF path (`/bulk/models/Foo.gguf`) — a manual drop; the
  #      blob must already be imported into Ollama (its content hash is the
  #      model identity, not the path). Check the file exists on disk and
  #      let `ollama create` resolve the import.
  if [[ "${base}" == /* ]]; then
    # Local GGUF path. Ollama needs the file present; `ollama create`
    # imports the blob and links it into /data/models on first use.
    if [ ! -f "${base}" ]; then
      echo "  skip ${alias_name} (GGUF not present: ${base})"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  else
    # Library tag. Match on family, not exact tag, so a Modelfile pinned to
    # `qwen3.8:27b` still works when the local base is `qwen3.8:latest`.
    base_family="${base%%:*}"
    if ! grep -qF "${base_family}" <<<"${LOCAL_BASES}"; then
      echo "  skip ${alias_name} (base family ${base_family} not pulled yet)"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi

  echo "  creating alias: ${alias_name}  (FROM ${base})"
  # Run from the repo root so the Modelfile's relative path to
  # PROMPT.coding.md (`config/ollama/PROMPT.coding.md`) resolves.
  if (cd "${REPO_ROOT}" && ollama create "${alias_name}" -f "${mf}" >/dev/null); then
    CREATED=$((CREATED + 1))
  else
    echo "  FAIL creating ${alias_name}" >&2
    FAIL=$((FAIL + 1))
  fi
done

echo
echo "aliases: created=${CREATED}  skipped=${SKIPPED}  failed=${FAIL}"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
