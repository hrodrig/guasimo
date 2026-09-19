#!/usr/bin/env bash
# scripts/eval-go-ornith.sh — qualitative Go gate for Ornith (or any
# OpenAI-compat llama-server). Sends the appendix assertiveness prompt,
# extracts the Go, and runs go test / go vet in a scratch module.
#
# Usage:
#   ./scripts/eval-go-ornith.sh
#   ORNITH_BASE=http://192.168.10.10:8081/v1 ./scripts/eval-go-ornith.sh
#   ORNITH_MODEL=ornith-35b ORNITH_BASE=http://127.0.0.1:8082/v1 ./scripts/eval-go-ornith.sh
#
# Env:
#   ORNITH_BASE   default http://127.0.0.1:8081/v1
#   ORNITH_MODEL  default ornith-9b
#   ORNITH_KEEP=1 keep scratch dir on success (always kept on failure)
#
# Exit: 0 if go test + go vet pass; 1 API/extract fail; 2 compile/test fail.
#
# Prompt + method: docs/appendix-code-review-assertiveness.md

set -euo pipefail

BASE="${ORNITH_BASE:-http://127.0.0.1:8081/v1}"
MODEL="${ORNITH_MODEL:-ornith-9b}"
MAX_TOKENS="${ORNITH_MAX_TOKENS:-1200}"
KEEP="${ORNITH_KEEP:-0}"

PROMPT='Write a Go function that reads a JSON file containing a list of users (name, email, age) and returns the average age of users over 30, handling missing or malformed files gracefully. Output only the Go code, no explanation.'

need() { command -v "$1" >/dev/null || { echo "need $1" >&2; exit 1; }; }
need curl
need jq
need go
need python3

echo ">>> API  ${BASE}"
echo ">>> model ${MODEL}"

if ! curl -fsS --max-time 5 "${BASE}/models" >/dev/null; then
  echo "API unreachable at ${BASE}/models" >&2
  exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ornith-go-eval.XXXXXX")
trap 'if [ "${KEEP}" = 1 ] || [ "${_EVAL_FAIL:-0}" = 1 ]; then
        echo ">>> scratch ${TMP}"
      else
        rm -rf "${TMP}"
      fi' EXIT

echo ">>> generate…"
HTTP_CODE=$(curl -sS --max-time 300 -o "${TMP}/resp.json" -w '%{http_code}' \
  "${BASE}/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n \
        --arg m "${MODEL}" \
        --arg p "${PROMPT}" \
        --argjson n "${MAX_TOKENS}" \
        '{model:$m, messages:[{role:"user",content:$p}],
          max_tokens:$n, temperature:0.2, stream:false}')")

if [ "${HTTP_CODE}" != "200" ]; then
  echo "chat/completions HTTP ${HTTP_CODE}" >&2
  head -c 400 "${TMP}/resp.json" >&2 || true
  echo >&2
  _EVAL_FAIL=1
  exit 1
fi

# Prefer message.content; Ornith often fills reasoning_content instead.
python3 - "${TMP}/resp.json" "${TMP}/raw.txt" <<'PY'
import json, re, sys
path_in, path_out = sys.argv[1], sys.argv[2]
j = json.load(open(path_in))
msg = j["choices"][0]["message"]
text = (msg.get("content") or "") or (msg.get("reasoning_content") or "")
open(path_out, "w").write(text)
usage = j.get("usage") or {}
timings = j.get("timings") or {}
print(f">>> tokens prompt={usage.get('prompt_tokens')} completion={usage.get('completion_tokens')}")
if timings:
    print(f">>> timings prompt_ms={timings.get('prompt_ms')} predicted_ms={timings.get('predicted_ms')} "
          f"gen_tps={timings.get('predicted_per_second')}")
if not text.strip():
    sys.exit(3)
PY
_EXTRACT=$?
if [ "${_EXTRACT}" -eq 3 ]; then
  echo "empty content and reasoning_content" >&2
  _EVAL_FAIL=1
  exit 1
fi

# Strip markdown fences / prose; keep from first package/import/func.
python3 - "${TMP}/raw.txt" "${TMP}/extracted.go" <<'PY'
import re, sys
raw = open(sys.argv[1]).read()
# fenced blocks first
blocks = re.findall(r"```(?:go|golang)?\s*\n(.*?)```", raw, flags=re.S | re.I)
body = max(blocks, key=len) if blocks else raw
# drop leading prose
m = re.search(r"(?m)^(package\s+\w+|import\s+\(|func\s+\w+)", body)
if m:
    body = body[m.start():]
open(sys.argv[2], "w").write(body.strip() + "\n")
print(f">>> extracted {len(body)} bytes -> {sys.argv[2]}")
PY

MOD="${TMP}/mod"
mkdir -p "${MOD}"
cd "${MOD}"
go mod init ornith_eval >/dev/null

# Model often emits package main + main(). Our harness is package ornith_eval.
python3 - "${TMP}/extracted.go" average.go <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r"(?m)^package\s+\w+", "package ornith_eval", src, count=1)
# drop main() so go test links cleanly
src = re.sub(r"(?ms)^func\s+main\s*\([^)]*\)\s*\{.*?\n\}", "", src)
open(sys.argv[2], "w").write(src)
# require the expected symbol
if "AverageAgeOver30" not in src:
    print("WARN: AverageAgeOver30 not found — tests will fail", file=sys.stderr)
PY

cat > average_test.go <<'EOF'
package ornith_eval

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeJSON(t *testing.T, name, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestAverageAgeOver30_ok(t *testing.T) {
	p := writeJSON(t, "u.json", `[
	  {"name":"a","email":"a@x","age":25},
	  {"name":"b","email":"b@x","age":40},
	  {"name":"c","email":"c@x","age":50}
	]`)
	avg, err := AverageAgeOver30(p)
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if avg < 44.9 || avg > 45.1 {
		t.Fatalf("avg=%v want 45", avg)
	}
}

func TestAverageAgeOver30_missingFile(t *testing.T) {
	_, err := AverageAgeOver30(filepath.Join(t.TempDir(), "nope.json"))
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestAverageAgeOver30_malformed(t *testing.T) {
	p := writeJSON(t, "bad.json", `{not json`)
	_, err := AverageAgeOver30(p)
	if err == nil {
		t.Fatal("expected parse error")
	}
}

func TestAverageAgeOver30_noMatches(t *testing.T) {
	p := writeJSON(t, "young.json", `[{"name":"a","email":"a@x","age":20}]`)
	avg, err := AverageAgeOver30(p)
	// Both (0,nil) and error are defendable; accept either.
	if err != nil {
		if avg != 0 {
			t.Fatalf("on error avg should be 0, got %v", avg)
		}
		return
	}
	if avg != 0 {
		t.Fatalf("avg=%v want 0", avg)
	}
}

func TestAverageAgeOver30_trailingJunk(t *testing.T) {
	// Assertiveness probe: single Decode ignores trailing data.
	p := writeJSON(t, "junk.json", `[{"name":"a","email":"a@x","age":40}] junk`)
	_, err := AverageAgeOver30(p)
	if err == nil {
		t.Log("NOTE: trailing junk accepted (common Weakness — see appendix Decoder/EOF)")
		t.Skip("soft fail: model did not reject trailing data")
	}
	if !strings.Contains(strings.ToLower(err.Error()), "json") &&
		!strings.Contains(strings.ToLower(err.Error()), "parse") &&
		!strings.Contains(strings.ToLower(err.Error()), "trailing") &&
		!strings.Contains(strings.ToLower(err.Error()), "extra") {
		t.Logf("got error (ok): %v", err)
	}
}
EOF

echo ">>> go vet"
if ! go vet ./...; then
  _EVAL_FAIL=1
  echo "FAIL go vet" >&2
  exit 2
fi

echo ">>> go test"
if ! go test -count=1 ./...; then
  _EVAL_FAIL=1
  echo "FAIL go test" >&2
  echo ">>> generated average.go (head):"
  head -n 40 average.go
  exit 2
fi

echo ">>> PASS — Ornith Go gate green"
echo "    (trailing-junk is soft/skip unless model rejects it)"
