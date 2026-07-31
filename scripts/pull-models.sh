#!/usr/bin/env bash
# scripts/pull-models.sh — pull named models into /bulk and link to /data.
#
# Usage: scripts/pull-models.sh {primary|secondary|large|all|<name>}
#
# - primary   : Qwen2.5-Coder-14B-Instruct (Q4_K_M), the daily driver
# - secondary : Qwen2.5-Coder-7B-Instruct  (Q4_K_M), fast path
# - large     : Qwen2.5-Coder-32B-Instruct (Q4_K_M), partial offload
# - all       : primary + secondary
# - <name>    : any name known to Ollama's registry, e.g. "deepseek-coder-v2:lite"
#
# Writes land in /bulk/models (cold) and are linked into /data/models (hot)
# so Ollama's OLLAMA_MODELS directory stays on the fast NVMe.

set -euo pipefail

DATA_DIR="/data/models"
BULK_DIR="/bulk/models"
LOG_DIR="/var/log/ia-lab"
mkdir -p "${DATA_DIR}" "${BULK_DIR}" "${LOG_DIR}"
chown -R ia-lab:ia-lab "${DATA_DIR}" "${BULK_DIR}" 2>/dev/null || true

WHAT="${1:-primary}"

# Manifest: nickname → ollama pull name. Add new entries here, not in the body.
declare -A MODELS=(
  [primary]="qwen2.5-coder:14b-instruct-q4_K_M"
  [secondary]="qwen2.5-coder:7b-instruct-q4_K_M"
  [large]="qwen2.5-coder:32b-instruct-q4_K_M"
)

# Resolve which names to pull.
TARGETS=()
case "${WHAT}" in
  primary)   TARGETS=("${MODELS[primary]}") ;;
  secondary) TARGETS=("${MODELS[secondary]}") ;;
  large)     TARGETS=("${MODELS[large]}") ;;
  all)       TARGETS=("${MODELS[primary]}" "${MODELS[secondary]}") ;;
  *)
    # Treat the arg as a literal ollama name; useful for ad-hoc pulls.
    TARGETS=("${WHAT}")
    ;;
esac

# Pre-flight: confirm ollama is up.
if ! curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "ollama is not reachable at 127.0.0.1:11434" >&2
  echo "  systemctl status ollama  /  journalctl -u ollama -n 50" >&2
  exit 2
fi

# Pre-flight: disk budget. Each model is roughly (params_in_B) GB on disk.
EST_GB=0
for t in "${TARGETS[@]}"; do
  case "$t" in
    *14b*) EST_GB=$((EST_GB + 9)) ;;
    *7b*)  EST_GB=$((EST_GB + 5)) ;;
    *32b*) EST_GB=$((EST_GB + 20)) ;;
    *)     EST_GB=$((EST_GB + 10)) ;;
  esac
done
FREE_GB=$(df -BG --output=avail "${BULK_DIR}" | tail -1 | tr -dc '0-9')
if [ "${FREE_GB}" -lt $((EST_GB + 5)) ]; then
  echo "insufficient disk: need ~${EST_GB} GB, have ${FREE_GB} GB on ${BULK_DIR}" >&2
  exit 3
fi

# Pull, as ia-lab user (Ollama writes into OLLAMA_MODELS=/data/models).
run_ollama() {
  sudo -u ia-lab -H ollama "$@"
}

for t in "${TARGETS[@]}"; do
  echo
  echo ">>> pulling ${t}"
  if ! run_ollama pull "${t}" 2>&1 | tee -a "${LOG_DIR}/pull.log"; then
    echo "pull failed for ${t}; see ${LOG_DIR}/pull.log" >&2
    exit 1
  fi
done

echo
echo "models now visible to Ollama:"
run_ollama list

echo
echo "next step: scripts/benchmark.sh ${WHAT}"