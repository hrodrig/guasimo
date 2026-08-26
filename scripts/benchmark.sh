#!/usr/bin/env bash
# scripts/benchmark.sh — measure prompt-eval and generation tokens/second.
#
# Usage: scripts/benchmark.sh [model-name]
#
# Defaults to "primary" if no argument. Loads the model, sends a fixed
# prompt, and reports the numbers Ollama returns from /api/generate.
# Exit code 0 if a model is loaded and responds; 1 if the API is down.

set -euo pipefail

NAME="${1:-primary}"

# Map nicknames → registered Ollama tags (mirrors pull-models.sh).
# `thinking` resolves to the same base as `secondary`; the system prompt
# difference lives in config/ollama/Modelfile.qwen3-27b-thinking.
declare -A MODELS=(
  # primary is a local alias created by install-aliases.sh from
  # config/ollama/Modelfile.ornith-9b (manual GGUF drop, not an
  # `ollama pull` tag). Ornith-1.5-9B Q6_K — see the Ornith section of
  # docs/04-models.md for the Q6_K vs AD trade-off.
  [primary]="ornith-9b"
  # secondary is Qwen3.8-27B-Instruct, kept for deep agentic work.
  [secondary]="qwen3.8:27b"
  [thinking]="qwen3.8:27b"
  [gemma]="gemma4:12b"
  [gemma4]="gemma4:12b"
  [deepseek]="deepseek-coder-v2:lite"
  [deepseek-lite]="deepseek-coder-v2:lite"
)

if [ -n "${MODELS[$NAME]+x}" ]; then
  TARGET="${MODELS[$NAME]}"
else
  TARGET="${NAME}"
fi

if ! curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "ollama unreachable" >&2
  exit 1
fi

# Fixed prompt: ~150 tokens prompt, 200 tokens generation. Deterministic
# sampling so the run is reproducible. Adjust n_predict up/down if the
# box is too fast/slow to get a stable average.
PROMPT='Write a Go function called ParseLogLine that takes a string in
the Common Log Format (host ident authuser date request status bytes)
and returns a struct with those fields plus an error. The function must
handle malformed lines by returning a typed error. Include a small
table-driven test that covers: well-formed line, missing bytes field,
and ISO date with a timezone offset. Output only Go code, no prose.'

# Use --verbose to get eval_count / eval_duration / total_duration back in
# the JSON response. Stream is off so we get a single summary object.
RESP=$(curl -fsS http://127.0.0.1:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d "$(jq -n \
        --arg m  "${TARGET}" \
        --arg p  "${PROMPT}" \
        '{model:$m, prompt:$p, stream:false,
          options:{num_predict:200, temperature:0.2,
                   num_ctx:4096, repeat_penalty:1.05}}')")

# Pull the timings out of the response. Ollama reports durations in ns.
# Use jq @tsv to emit one tab-separated line; `read` then captures the
# five fields by name. This avoids the brittle here-doc + interpolation
# pattern that breaks under set -u.
read -r PROMPT_TOK GEN_TOK EVAL_TPS GEN_TPS NS_TOTAL < <(
  echo "${RESP}" | jq -r '
    [
      (.prompt_eval_count    // 0),
      (.eval_count           // 0),
      (if (.prompt_eval_duration // 0) > 0
        then ((.prompt_eval_count // 0) / ((.prompt_eval_duration // 0) / 1e9)) | floor
        else 0 end),
      (if (.eval_duration // 0) > 0
        then ((.eval_count // 0) / ((.eval_duration // 0) / 1e9)) | floor
        else 0 end),
      (.total_duration // 0)
    ] | @tsv'
)

printf "model:        %s\n"        "${TARGET}"
printf "prompt tok:   %s\n"        "${PROMPT_TOK}"
printf "gen tok:      %s\n"        "${GEN_TOK}"
printf "prompt t/s:   %s\n"        "${EVAL_TPS}"
printf "gen    t/s:   %s\n"        "${GEN_TPS}"
printf "total ms:     %s\n"        "$((NS_TOTAL / 1000000))"

# Annotate the result against expected ranges for this box. Numbers are
# rule-of-thumb; flag obviously bad results.
if [ "${GEN_TPS}" -lt 10 ]; then
  echo "WARN: gen t/s is below 10. Likely on CPU or wrong SIMD build." >&2
fi
if [ "${GEN_TPS}" -gt 200 ]; then
  echo "WARN: gen t/s above 200. Suspicious; check you are not getting cached output." >&2
fi