#!/usr/bin/env bash
# scripts/serve-35b.sh — run the Ornith-1.5-35B-A3B MoE as a local
# llama.cpp server via --cpu-moe (quality path, 0 % context drop).
#
# This is the EXPLICIT alternative to the `ornith-9b` primary. It is not
# wired into Open WebUI or the Ollama OpenAI-compat API — it exposes its
# own OpenAI-compatible endpoint on :8081, directly from llama-server.
# Use it when output quality matters more than raw throughput: the 35B
# produces the best idiomatic Go/C# (doc comments, %w-wrapped errors) but
# runs ~23.5 gen tok/s flat, vs ~38 tok/s for the 9B primary.
#
# Why --cpu-moe: the 35B is a mixture-of-experts (256 experts, 8 active
# per token). Pinning the experts in RAM (--cpu-moe) and offloading the
# dense layers + attention to VRAM keeps a 64K KV cache on-GPU, so the
# generation rate is 0.0 % flat from 8K to 64K context. The default
# Ollama offload is faster at 8K (31.2 t/s) but sheds to 29.2 t/s at 64K
# because the KV cache no longer fits 12 GB VRAM.
#
# Measured on the reference box (2026-08-25): 23.5 gen t/s @ 8K and @ 64K.
#
# Usage:
#   scripts/serve-35b.sh                  # foreground server on :8081
#   LLAMA_CTX=32768 scripts/serve-35b.sh  # smaller cache = lower RAM
#
# Depends on:
#   - deploy/install.sh phase 3 (builds llama.cpp, symlinks /opt/guasimo/llama-server)
#     — requires a llama.cpp >= the --cpu-moe PR (#15077, Aug 2025); the
#     pinned LLAMA_CPP_REF must be recent (b10630+), not b4568.
#   - the GGUF drop /bulk/models/Ornith-1.5-35B-Q4_K_M.gguf
#     (20.2 GB; see ornith-ai/Ornith-1.5-35B-A3B-GGUF on HF Hub)
#
# See docs/04-models.md → "How to switch the model" for the full map.

set -euo pipefail

LLAMA_SERVER="${LLAMA_SERVER:-/opt/guasimo/llama-server}"
MODEL="${MODEL:-/bulk/models/Ornith-1.5-35B-Q4_K_M.gguf}"
ALIAS="${LLAMA_ALIAS:-ornith-35b}"   # name exposed on the OpenAI-compat API
CTX="${LLAMA_CTX:-65536}"            # 64K — matches the box's agentic floor
NGPU="${LLAMA_NGPU:-99}"             # offload every dense/attention layer to GPU
PORT="${LLAMA_PORT:-8081}"
N_PREDICT="${LLAMA_N_PREDICT:--1}"   # -1 = infinity, server decides

if [ ! -x "${LLAMA_SERVER}" ]; then
  echo "llama-server not found at ${LLAMA_SERVER}" >&2
  echo "  run deploy/install.sh (phase 3) to build llama.cpp first" >&2
  exit 2
fi

if [ ! -f "${MODEL}" ]; then
  echo "GGUF not present: ${MODEL}" >&2
  echo "  place Ornith-1.5-35B-Q4_K_M.gguf in /bulk/models/ first" >&2
  exit 3
fi

# Guard: --cpu-moe only exists on llama.cpp builds >= PR #15077. Fail fast
# with a clear message rather than erroring mid-load on an old pin.
if ! "${LLAMA_SERVER}" --help 2>&1 | grep -q -- "--cpu-moe"; then
  echo "this llama-server build predates --cpu-moe (PR #15077, Aug 2025)" >&2
  echo "  bump LLAMA_CPP_REF in deploy/install.sh to b10630+ and rebuild" >&2
  exit 4
fi

# Pre-flight thermal check. The 35B MoE is the most thermally demanding
# model: refuse to start if the SoC/iGPU is already over the soft cap so a
# hot box does not get pushed further. The cap is conservative (80 C) on a
# 95 C Tjmax part, set after a burst capacitor burned out under sustained
# load. Bypass with THERMAL_MAX_C=<higher> if you understand the trade-off.
THERMAL_GUARD="${THERMAL_GUARD:-$(dirname "$0")/thermal-guard.sh}"
if [ ! -x "${THERMAL_GUARD}" ]; then
  # Prefer the install-root copy when running from a different cwd/path.
  [ -x /opt/guasimo/scripts/thermal-guard.sh ] \
    && THERMAL_GUARD=/opt/guasimo/scripts/thermal-guard.sh
fi
if [ -x "${THERMAL_GUARD}" ]; then
  "${THERMAL_GUARD}" 1 || {
    echo "refusing to start: box is thermally hot — let it cool first" >&2
    exit 5
  }
else
  echo "warning: thermal-guard.sh not found/executable — starting without thermal gate" >&2
fi

echo ">>> serving Ornith-1.5-35B-A3B (--cpu-moe) on :${PORT} as '${ALIAS}' (ctx ${CTX})"
exec "${LLAMA_SERVER}" \
  --model "${MODEL}" \
  --alias "${ALIAS}" \
  --port "${PORT}" \
  --host 127.0.0.1 \
  --cpu-moe \
  --n-gpu-layers "${NGPU}" \
  --ctx-size "${CTX}" \
  --predict "${N_PREDICT}" \
  --temperature 0.2 \
  --top-p 0.95 \
  --top-k 40 \
  --repeat-penalty 1.05
