#!/usr/bin/env bash
# scripts/build-bonsai-llama.sh — build the PrismML llama.cpp fork for
# Ternary Bonsai 2 (PTQ1_0 / PQ2_0 GGUF). Stock llama.cpp cannot load
# these files; this binary lives *beside* the main /opt/guasimo/llama-server
# and is only used by scripts/serve-bonsai.sh.
#
# Does NOT replace Ollama's llama-server. Opt-in from install with:
#   INSTALL_BONSAI=1 sudo ./deploy/install.sh
# or run this script alone (as root) after the main stack is up.
#
# Pin: PrismML-Eng/llama.cpp @ prism-b10687-5d80cff (2026-09-17).
# Upstream: https://github.com/PrismML-Eng/llama.cpp
# Model:    https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf
#
# Env overrides:
#   PRISM_LLAMA_CPP_REF   git tag/SHA (default prism-b10687-5d80cff)
#   INSTALL_ROOT          default /opt/guasimo
#   BUILD_JOBS            parallel cmake jobs (default nproc-2)

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

PRISM_LLAMA_CPP_REF="${PRISM_LLAMA_CPP_REF:-prism-b10687-5d80cff}"
PRISM_LLAMA_REPO="${PRISM_LLAMA_REPO:-https://github.com/PrismML-Eng/llama.cpp}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/guasimo}"
SRC_DIR="${INSTALL_ROOT}/llama.cpp-bonsai"
SERVICE_USER="${SERVICE_USER:-guasimo}"
CUDA_ARCHS="${CUDA_ARCHS:-86}"
BUILD_JOBS="${BUILD_JOBS:-$(( $(nproc) - 2 ))}"
[ "${BUILD_JOBS}" -lt 1 ] && BUILD_JOBS=1

mkdir -p "${INSTALL_ROOT}"

# Backend probe — same priority as deploy/install.sh (CUDA → Vulkan → CPU).
HAS_NVIDIA_HW=n
HAS_NVIDIA_RT=n
HAS_AMD_HW=n
if command -v lspci >/dev/null 2>&1; then
  lspci 2>/dev/null | grep -qi nvidia && HAS_NVIDIA_HW=y
  LSPCI_OUT=$(lspci 2>/dev/null || true)
  AMD_GFX=$(printf '%s\n' "${LSPCI_OUT}" \
    | grep -iE 'vga compatible|display controller|3d controller' \
    | grep -i 'amd' || true)
  [ -n "${AMD_GFX}" ] && HAS_AMD_HW=y
fi
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  HAS_NVIDIA_RT=y
fi

CMAKE_FLAGS=()
BACKEND_ID=cpu
if [ "${HAS_NVIDIA_RT}" = y ] && [ "${HAS_NVIDIA_HW}" = y ] \
   && command -v nvcc >/dev/null 2>&1; then
  BACKEND_ID=cuda
  CMAKE_FLAGS+=("-DGGML_CUDA=ON" "-DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHS}")
  CMAKE_FLAGS+=("-DGGML_NATIVE=OFF")
elif [ "${HAS_AMD_HW}" = y ]; then
  BACKEND_ID=vulkan
  CMAKE_FLAGS+=("-DGGML_VULKAN=ON" "-DGGML_NATIVE=ON")
else
  CMAKE_FLAGS+=("-DGGML_NATIVE=ON")
fi

STAMP="${INSTALL_ROOT}/.llama-bonsai-backend"
NEED_BUILD=y
if [ -x "${SRC_DIR}/build/bin/llama-server" ] && [ -d "${SRC_DIR}/.git" ]; then
  CURRENT=$(git -C "${SRC_DIR}" rev-parse HEAD 2>/dev/null || echo none)
  PINNED=$(git -C "${SRC_DIR}" rev-parse "${PRISM_LLAMA_CPP_REF}^{commit}" 2>/dev/null || echo none)
  PREV=none
  [ -f "${STAMP}" ] && PREV=$(cat "${STAMP}" 2>/dev/null || echo none)
  if [ "${CURRENT}" != none ] && [ "${CURRENT}" = "${PINNED}" ] \
     && [ "${PREV}" = "${BACKEND_ID}" ]; then
    NEED_BUILD=n
    echo "  PrismML llama.cpp already at ${PRISM_LLAMA_CPP_REF} (${BACKEND_ID})"
  fi
fi

if [ "${NEED_BUILD}" = y ]; then
  echo ">>> building PrismML llama.cpp (${PRISM_LLAMA_CPP_REF}, ${BACKEND_ID})"
  if [ ! -d "${SRC_DIR}/.git" ]; then
    rm -rf "${SRC_DIR}"
    git clone --depth=1 --branch "${PRISM_LLAMA_CPP_REF}" \
      "${PRISM_LLAMA_REPO}" "${SRC_DIR}"
  else
    git -C "${SRC_DIR}" fetch --depth=1 origin "${PRISM_LLAMA_CPP_REF}"
    git -C "${SRC_DIR}" checkout -- .
    git -C "${SRC_DIR}" checkout FETCH_HEAD
  fi
  if id -u "${SERVICE_USER}" >/dev/null 2>&1; then
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "${SRC_DIR}"
  fi
  cmake -S "${SRC_DIR}" -B "${SRC_DIR}/build" \
        -DCMAKE_BUILD_TYPE=Release "${CMAKE_FLAGS[@]}"
  cmake --build "${SRC_DIR}/build" --parallel "${BUILD_JOBS}"
  strip "${SRC_DIR}/build/bin/llama-server" \
        "${SRC_DIR}/build/bin/llama-cli" 2>/dev/null || true
  printf '%s\n' "${BACKEND_ID}" > "${STAMP}"
fi

ln -sf "${SRC_DIR}/build/bin/llama-server" "${INSTALL_ROOT}/llama-server-bonsai"
ln -sf "${SRC_DIR}/build/bin/llama-cli"    "${INSTALL_ROOT}/llama-cli-bonsai"
if id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  chown -h "${SERVICE_USER}:${SERVICE_USER}" \
    "${INSTALL_ROOT}/llama-server-bonsai" "${INSTALL_ROOT}/llama-cli-bonsai" \
    2>/dev/null || true
  chown "${SERVICE_USER}:${SERVICE_USER}" "${STAMP}" 2>/dev/null || true
fi

echo "  backend: ${BACKEND_ID}"
echo "  server:  ${INSTALL_ROOT}/llama-server-bonsai"
echo "  next:    place Ternary-Bonsai-2-27B-PQ2_0.gguf in /bulk/models/"
echo "           then: ./scripts/serve-bonsai.sh"
