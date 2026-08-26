#!/usr/bin/env bash
# scripts/pull-models.sh — pull named models into /bulk and link to /data.
#
# Usage: scripts/pull-models.sh {primary|secondary|thinking|gemma|deepseek|all|<name>}
#
# - primary   : Ornith-1.5-9B (ornith-9b, Q6_K, ~7.4 GB), the daily driver.
#               hybrid-attention 9B, plain prompt template, flat across
#               8K→64K context (0.0 % drop), full VRAM on the RTX 3060.
#               MANUAL GGUF DROP (see config/ollama/Modelfile.ornith-9b):
#               place Ornith-1.5-9B-Q6_K.gguf in /bulk/models/ first —
#               this script does not `ollama pull` it from any library.
# - secondary : Qwen3.8-27B-Instruct (qwen3.8:27b, ~18 GB), agentic depth.
#               Dense 27B, vision-language, 256K ctx; partial offload on
#               the RTX 3060. Kept for deep 64K+ review/refactor where
#               quality beats latency (was the v0.3.x primary).
# - thinking  : same qwen3.8:27b base as secondary, with thinking forced
#               on via Modelfile (config/ollama/Modelfile.qwen3-27b-thinking).
# - gemma     : Gemma 4 12B (Ollama gemma4:12b) — agents / tools
# - deepseek  : DeepSeek-Coder-V2-Lite (deepseek-coder-v2:lite) — backup coder
# - all       : primary + secondary
# - <name>    : any name known to Ollama's registry
#
# Writes land in /bulk/models (cold) and are linked into /data/models (hot)
# so Ollama's OLLAMA_MODELS directory stays on the fast NVMe.

set -euo pipefail

DATA_DIR="/data/models"
BULK_DIR="/bulk/models"
# Prefer the service log dir when writable (root / guasimo); otherwise a
# per-user cache path so an unprivileged operator can run this script.
LOG_DIR="/var/log/guasimo"
PULL_LOG=""
if mkdir -p "${LOG_DIR}" 2>/dev/null && touch "${LOG_DIR}/.write-test" 2>/dev/null; then
  rm -f "${LOG_DIR}/.write-test"
  PULL_LOG="${LOG_DIR}/pull.log"
else
  LOG_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/guasimo"
  mkdir -p "${LOG_DIR}"
  PULL_LOG="${LOG_DIR}/pull.log"
fi
mkdir -p "${DATA_DIR}" "${BULK_DIR}" 2>/dev/null || true
# Daemon writes as User=ollama — never chown these trees to guasimo.
chown -R ollama:ollama "${DATA_DIR}" "${BULK_DIR}" 2>/dev/null || true

WHAT="${1:-primary}"

# Manifest: nickname → ollama pull name. Add new entries here, not in the body.
declare -A MODELS=(
  # primary is a MANUAL GGUF drop. The manifest value is the local alias
  # that install-aliases.sh creates from config/ollama/Modelfile.ornith-9b
  # after the GGUF is present in /bulk/models/. Not an `ollama pull` tag.
  [primary]="ornith-9b"
  [secondary]="qwen3.8:27b"
  # thinking reuses the secondary base; it is the same GGUF, just a different
  # Modelfile alias (see config/ollama/Modelfile.qwen3-27b-thinking). Listed
  # in the manifest so the case branch and benchmark can resolve it.
  [thinking]="qwen3.8:27b"
  [gemma]="gemma4:12b"
  [deepseek]="deepseek-coder-v2:lite"
)

# Resolve which names to pull.
TARGETS=()
case "${WHAT}" in
  primary)   TARGETS=("${MODELS[primary]}") ;;
  secondary) TARGETS=("${MODELS[secondary]}") ;;
  thinking)  TARGETS=("${MODELS[thinking]}") ;;
  gemma|gemma4) TARGETS=("${MODELS[gemma]}") ;;
  deepseek|deepseek-lite) TARGETS=("${MODELS[deepseek]}") ;;
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

# Pre-flight: disk budget. Each model is roughly its real Q4_K_M
# weight, in GB. Conservative defaults for unknown tags.
EST_GB=0
for t in "${TARGETS[@]}"; do
  case "$t" in
    *ornith-9b*|*ornith*9b*)                         EST_GB=$((EST_GB + 8))  ;;  # Ornith-1.5-9B Q6_K (manual drop)
    *qwen3.8*|*qwen3-8*)                             EST_GB=$((EST_GB + 18)) ;;  # qwen3.8:27b Q4_K_M
    *14b*)                                           EST_GB=$((EST_GB + 9))  ;;  # legacy Qwen2.5-Coder-14B
    *7b*)                                            EST_GB=$((EST_GB + 5))  ;;  # Qwen2.5-Coder-7B
    *32b*)                                           EST_GB=$((EST_GB + 20)) ;;  # legacy Qwen2.5-Coder-32B
    *gemma4*|*12b*)                                  EST_GB=$((EST_GB + 8))  ;;  # Gemma 4 12B
    *deepseek*)                                      EST_GB=$((EST_GB + 9))  ;;  # DeepSeek-Coder-V2-Lite
    *)                                               EST_GB=$((EST_GB + 10)) ;;  # unknown tag, conservative
  esac
done
FREE_GB=$(df -BG --output=avail "${BULK_DIR}" | tail -1 | tr -dc '0-9')
if [ "${FREE_GB}" -lt $((EST_GB + 5)) ]; then
  echo "insufficient disk: need ~${EST_GB} GB, have ${FREE_GB} GB on ${BULK_DIR}" >&2
  exit 3
fi

# ollama CLI is a client; the daemon (systemd) owns OLLAMA_MODELS writes.
# Run as the invoking user — no need for sudo -u guasimo on the client.
run_ollama() {
  ollama "$@"
}

echo "  pull log: ${PULL_LOG}"
for t in "${TARGETS[@]}"; do
  if [ "${t}" = "ornith-9b" ]; then
    # `primary` is a MANUAL GGUF drop, not an Ollama library tag. There is
    # nothing to `ollama pull`; the alias is created by install-aliases.sh
    # from config/ollama/Modelfile.ornith-9b once the GGUF is in /bulk/models/.
    echo
    echo ">>> primary (ornith-9b) is a manual GGUF drop — skipping ollama pull"
    echo "    place Ornith-1.5-9B-Q6_K.gguf in ${BULK_DIR}/ and re-run install-aliases.sh"
    continue
  fi
  echo
  echo ">>> pulling ${t}"
  if ! run_ollama pull "${t}" 2>&1 | tee -a "${PULL_LOG}"; then
    echo "pull failed for ${t}; see ${PULL_LOG}" >&2
    exit 1
  fi
done

echo
echo "models now visible to Ollama:"
run_ollama list

# Create the Modelfile aliases (qwen3-27b, qwen3-27b-thinking, ...) that
# match the bases we just pulled. Closes the v0.3.0 gap where recipes
# were checked in but never applied. `install-aliases.sh` is a no-op
# for bases that aren't pulled yet.
echo
echo ">>> creating Modelfile aliases (config/ollama/Modelfile.*)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! "${SCRIPT_DIR}/install-aliases.sh"; then
  echo "warning: alias creation failed; the base models are pulled but" >&2
  echo "         the named recipes are not. Re-run scripts/install-aliases.sh" >&2
  echo "         later once the issue is resolved." >&2
fi

echo
echo "next step: scripts/benchmark.sh ${WHAT}"