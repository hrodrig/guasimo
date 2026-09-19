#!/usr/bin/env bash
# scripts/serve-bonsai.sh — run Prism ML Ternary Bonsai 2 27B as a local
# llama-server (dense-intelligence / reasoning path).
#
# Parallel to scripts/serve-35b.sh. Default bind :8083 so it does not
# collide with the AMD lab layout (Ornith 9B :8081, Ornith 35B :8082 on
# 192.168.10.10). Needs the *PrismML* llama.cpp fork built by
# scripts/build-bonsai-llama.sh — stock /opt/guasimo/llama-server cannot
# load PTQ1_0 / PQ2_0 GGUFs (rejects them or silently produces garbage
# on plain Q2_0).
#
# Why Bonsai 2: ~5.9–7.2 GB on disk for a 27B-class reasoning model
# (~98 % of FP16 on Prism's bench suite). Fits the AMD mini-PC RAM budget
# with huge headroom vs Ornith-35B Q4 (~20 GB). Trade-off: separate binary
# fork, not on the Ollama path.
#
# Usage:
#   sudo ./scripts/build-bonsai-llama.sh   # once
#   # drop Ternary-Bonsai-2-27B-PQ2_0.gguf into /bulk/models/
#   ./scripts/serve-bonsai.sh
#
# Env:
#   MODEL / LLAMA_ALIAS / LLAMA_CTX / LLAMA_NGPU / LLAMA_PORT / MMPROJ
#   BONSAI_PACK=PQ2_0|PTQ1_0  (default PQ2_0 — faster PP; PTQ1_0 smaller)
#   LLAMA_NO_REPACK=1|0       (default 1 — pass --no-repack; see note below)
#
# Why --no-repack by default: ggml CPU weight repack rewrites tensors into a
# SIMD-friendly layout in *fresh* RAM (not mmap). On the AMD lab the Prism
# fork SIGSEGV'd in ggml_backend_cpu_repack_buffer_set_tensor while loading
# Ternary PQ2_0. Same class of failure llama.cpp hits when a MoE >> RAM
# tries to allocate a full repack buffer — the escape hatch is --no-repack
# (-nr). Set LLAMA_NO_REPACK=0 only if you want stock repack behaviour.
#
# Open WebUI: Admin → Connections → OpenAI API →
#   Base URL http://127.0.0.1:8083/v1  Model bonsai-2-27b
#
# Refs: https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf
#       https://github.com/PrismML-Eng/Bonsai-demo

set -euo pipefail

LLAMA_SERVER="${LLAMA_SERVER:-/opt/guasimo/llama-server-bonsai}"
PACK="${BONSAI_PACK:-PQ2_0}"
case "${PACK}" in
  PQ2_0|PTQ1_0) ;;
  *) echo "BONSAI_PACK must be PQ2_0 or PTQ1_0 (got ${PACK})" >&2; exit 1 ;;
esac
MODEL="${MODEL:-/bulk/models/Ternary-Bonsai-2-27B-${PACK}.gguf}"
MMPROJ="${MMPROJ:-}"   # optional; set to mmproj path for vision
ALIAS="${LLAMA_ALIAS:-bonsai-2-27b}"
CTX="${LLAMA_CTX:-32768}"          # 32K default; model supports up to 262K
NGPU="${LLAMA_NGPU:-99}"
PORT="${LLAMA_PORT:-8083}"
N_PREDICT="${LLAMA_N_PREDICT:--1}"
NO_REPACK="${LLAMA_NO_REPACK:-1}"  # 1 = --no-repack (safe default for ternary)

if [ ! -x "${LLAMA_SERVER}" ]; then
  echo "PrismML llama-server not found at ${LLAMA_SERVER}" >&2
  echo "  run: sudo ./scripts/build-bonsai-llama.sh" >&2
  exit 2
fi

if [ ! -f "${MODEL}" ]; then
  echo "GGUF not present: ${MODEL}" >&2
  echo "  hf download prism-ml/Ternary-Bonsai-2-27B-gguf \\" >&2
  echo "    Ternary-Bonsai-2-27B-${PACK}.gguf --local-dir /bulk/models/" >&2
  echo "  (stock ollama pull cannot fetch these ternary packs)" >&2
  exit 3
fi

# Sanity: refuse if someone pointed LLAMA_SERVER at the stock binary.
# Prism builds advertise PTQ1_0 / PQ2_0 in --help or accept the type;
# stock rejects unknown type names. Probe help text first.
HELP=$("${LLAMA_SERVER}" --help 2>&1 || true)
if ! printf '%s\n' "${HELP}" | grep -qiE 'ptq1_0|pq2_0|prism|bonsai'; then
  # Help may not list quant names. Soft warn only — fork still required.
  if [ "${LLAMA_SERVER}" = "/opt/guasimo/llama-server" ]; then
    echo "refusing: LLAMA_SERVER points at stock llama-server" >&2
    echo "  Bonsai 2 needs /opt/guasimo/llama-server-bonsai (PrismML fork)" >&2
    exit 4
  fi
fi

THERMAL_GUARD="${THERMAL_GUARD:-$(dirname "$0")/thermal-guard.sh}"
if [ ! -x "${THERMAL_GUARD}" ]; then
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

# Thinking-mode sampling from Prism's model card (bench defaults).
ARGS=(
  --model "${MODEL}"
  --alias "${ALIAS}"
  --port "${PORT}"
  --host 127.0.0.1
  --n-gpu-layers "${NGPU}"
  --ctx-size "${CTX}"
  --predict "${N_PREDICT}"
  --flash-attn on
  --temperature 1.0
  --top-p 0.95
  --top-k 20
  --repeat-penalty 1.0
)

case "${NO_REPACK}" in
  1|true|TRUE|yes|YES|on|ON)
    ARGS+=(--no-repack)
    ;;
  0|false|FALSE|no|NO|off|OFF)
    ;;
  *)
    echo "LLAMA_NO_REPACK must be 0 or 1 (got ${NO_REPACK})" >&2
    exit 1
    ;;
esac

if [ -n "${MMPROJ}" ]; then
  if [ ! -f "${MMPROJ}" ]; then
    echo "MMPROJ set but missing: ${MMPROJ}" >&2
    exit 3
  fi
  ARGS+=(--mmproj "${MMPROJ}")
fi

echo ">>> serving Bonsai 2 27B (${PACK}) on :${PORT} as '${ALIAS}' (ctx ${CTX})"
echo "    binary ${LLAMA_SERVER}  no-repack=${NO_REPACK}"
exec "${LLAMA_SERVER}" "${ARGS[@]}"
