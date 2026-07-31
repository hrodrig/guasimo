#!/usr/bin/env bash
# tests/smoke.sh — end-to-end smoke test for the ia-lab stack.
#
# Verifies, in order, that:
#   1. nginx accepts HTTPS connections.
#   2. The Open WebUI HTTP endpoint answers.
#   3. The Ollama API answers and lists at least one model.
#   4. The Ollama API can complete a short prompt and stream tokens back.
#   5. llama-server binary is present and executable.
#
# Exit code 0 on full success, 1 on first failure. Designed to run from
# CI on a clean VM after `deploy/install.sh` and `scripts/pull-models.sh`.

set -uo pipefail

FAIL=0
say() { printf '%s\n' "$*"; }
ok()  { say "  ok  | $*"; }
bad() { say "  FAIL| $*"; FAIL=$((FAIL + 1)); }

# Configurable: where the stack lives. Defaults match docs/01-architecture.md.
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
WEBUI_URL="${WEBUI_URL:-http://127.0.0.1:8080}"
NGINX_HTTPS="${NGINX_HTTPS:-https://127.0.0.1}"

# Pick a model. If none registered, smoke fails gracefully.
MODEL=$(curl -fsS --max-time 3 "${OLLAMA_URL}/api/tags" 2>/dev/null \
        | jq -r '.models[0].name // empty')

# 1. nginx HTTPS reachable (self-signed; ignore cert errors with -k).
if curl -ksS --max-time 3 -o /dev/null -w '%{http_code}' \
     "${NGINX_HTTPS}/" 2>/dev/null | grep -qE '^(200|301|302)$'; then
  ok "nginx https reachable"
else
  bad "nginx https unreachable"
fi

# 2. Open WebUI HTTP
if curl -fsS --max-time 3 -o /dev/null -w '%{http_code}' \
     "${WEBUI_URL}/" 2>/dev/null | grep -q '^200$'; then
  ok "open-webui http reachable"
else
  bad "open-webui http unreachable"
fi

# 3. Ollama lists models
if [ -n "${MODEL}" ]; then
  ok "ollama has model: ${MODEL}"
else
  bad "ollama has no models (run scripts/pull-models.sh)"
fi

# 4. Ollama completes a short prompt
if [ -n "${MODEL}" ]; then
  RESP=$(curl -fsS --max-time 30 "${OLLAMA_URL}/api/generate" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n \
          --arg m "${MODEL}" \
          '{model:$m, prompt:"Reply with the single word ok.",
            stream:false, options:{num_predict:8, temperature:0}}')")
  OUT=$(echo "${RESP}" | jq -r '.response // ""' | tr -d '\r\n ' | tr '[:upper:]' '[:lower:]')
  if [ "${OUT}" = "ok" ] || [ "${OUT}" = "okay" ]; then
    ok "ollama completion returned: ${OUT}"
  else
    bad "ollama completion unexpected: '${OUT}'"
  fi
fi

# 5. llama-server binary
if [ -x /opt/ia-lab/llama-server ]; then
  ok "llama-server present and executable"
else
  bad "llama-server missing or not executable"
fi

echo
if [ "${FAIL}" -eq 0 ]; then
  echo "smoke: PASS"
  exit 0
else
  echo "smoke: FAIL (${FAIL} check(s))"
  exit 1
fi