#!/usr/bin/env bash
# scripts/healthcheck.sh — table-form health report for the ia-lab stack.
#
# Designed for cron / status pages. Exits 0 if all checks pass, 1 otherwise.
# The check definitions mirror docs/07-operations.md.

set -uo pipefail

PASS=0
FAIL=0
RESULTS=()

check() {
  local name="$1"; shift
  local expect="$1"; shift
  local cmd="$*"
  local out rc
  out=$(${cmd} 2>&1) || rc=$?
  rc=${rc:-0}
  if [ "${rc}" -eq "${expect}" ]; then
    RESULTS+=("ok  | ${name}")
    PASS=$((PASS + 1))
  else
    RESULTS+=("FAIL| ${name} (rc=${rc}, expect=${expect})")
    FAIL=$((FAIL + 1))
  fi
}

# --- nginx config syntax -----------------------------------------------------
if nginx -t >/dev/null 2>&1; then
  RESULTS+=("ok  | nginx config (-t)"); PASS=$((PASS + 1))
else
  RESULTS+=("FAIL| nginx config (-t)"); FAIL=$((FAIL + 1))
fi

# --- Open WebUI HTTP 200 -----------------------------------------------------
if curl -fsS --max-time 3 -o /dev/null -w '%{http_code}' \
     http://127.0.0.1:8080/ 2>/dev/null | grep -q '^200$'; then
  RESULTS+=("ok  | open-webui HTTP 200 on :8080"); PASS=$((PASS + 1))
else
  RESULTS+=("FAIL| open-webui HTTP 200 on :8080"); FAIL=$((FAIL + 1))
fi

# --- Ollama API reachable ----------------------------------------------------
if curl -fsS --max-time 3 -o /dev/null -w '%{http_code}' \
     http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q '^200$'; then
  RESULTS+=("ok  | ollama HTTP 200 on :11434"); PASS=$((PASS + 1))
else
  RESULTS+=("FAIL| ollama HTTP 200 on :11434"); FAIL=$((FAIL + 1))
fi

# --- Ollama has at least one model -------------------------------------------
MODEL_COUNT=$(curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags 2>/dev/null \
              | jq '.models | length' 2>/dev/null || echo 0)
if [ "${MODEL_COUNT}" -gt 0 ]; then
  RESULTS+=("ok  | ollama has ${MODEL_COUNT} model(s) loaded"); PASS=$((PASS + 1))
else
  RESULTS+=("FAIL| ollama has zero models (run scripts/pull-models.sh)"); FAIL=$((FAIL + 1))
fi

# --- llama-server binary present --------------------------------------------
if [ -x /opt/ia-lab/llama-server ]; then
  RESULTS+=("ok  | llama-server present and executable"); PASS=$((PASS + 1))
else
  RESULTS+=("FAIL| llama-server missing or not executable"); FAIL=$((FAIL + 1))
fi

# --- NVIDIA driver loaded if hardware present --------------------------------
if lspci 2>/dev/null | grep -qi nvidia; then
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    RESULTS+=("ok  | nvidia driver loaded (nvidia-smi works)"); PASS=$((PASS + 1))
  else
    RESULTS+=("WARN| nvidia hw present but driver not loaded (reboot?)"); FAIL=$((FAIL + 1))
  fi
else
  RESULTS+=("ok  | no nvidia hw (CPU-only mode)"); PASS=$((PASS + 1))
fi

# --- /data free space --------------------------------------------------------
FREE_GB=$(df -BG --output=avail /data 2>/dev/null | tail -1 | tr -dc '0-9')
if [ "${FREE_GB:-0}" -ge 5 ]; then
  RESULTS+=("ok  | /data free: ${FREE_GB} GB"); PASS=$((PASS + 1))
else
  RESULTS+=("FAIL| /data free: ${FREE_GB:-0} GB (need >= 5)"); FAIL=$((FAIL + 1))
fi

# --- RAM free ----------------------------------------------------------------
FREE_RAM_GB=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if [ "${FREE_RAM_GB:-0}" -ge 4 ]; then
  RESULTS+=("ok  | RAM available: ${FREE_RAM_GB} GB"); PASS=$((PASS + 1))
else
  RESULTS+=("FAIL| RAM available: ${FREE_RAM_GB:-0} GB (need >= 4)"); FAIL=$((FAIL + 1))
fi

# --- Render ------------------------------------------------------------------
printf '%-6s| %s\n' "st" "check"
printf '%-6s+-%s\n' "------" "----------------------------------------------"
for r in "${RESULTS[@]}"; do
  printf '%s\n' "${r}"
done
printf '\nsummary: %d ok / %d fail\n' "${PASS}" "${FAIL}"

[ "${FAIL}" -eq 0 ]