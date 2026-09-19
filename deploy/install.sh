#!/usr/bin/env bash
# deploy/install.sh — install the local LLM stack on Ubuntu 26.04.
#
# Idempotent. Run as root (or with sudo). Honours the contract in
# docs/05-deployment.md. All decisions are logged.

set -euo pipefail

# Non-interactive apt. Without this, debconf prompts (e.g. the legacy
# grub-pc "install_devices" question that fires on boxes that moved from
# grub-pc to grub-efi) block a headless `sudo -n`/screen run forever.
export DEBIAN_FRONTEND=noninteractive

# Force debconf into non-interactive mode at the debconf level and silence
# every question to critical priority. DEBIAN_FRONTEND alone is not enough:
# the grub-pc reconfigure dialog opens a pty on /dev/ptmx regardless. Telling
# debconf itself to answer nothing below critical stops it, and non-critical
# questions then take their debconf default instead of hanging.
debconf_set() { command -v debconf-set-selections >/dev/null 2>&1 && echo "$1" | debconf-set-selections; }
debconf_set "debconf debconf/frontend select Noninteractive"
debconf_set "debconf debconf/priority select critical"
# Answer the specific grub-pc questions that trigger on BIOS/EFI migration.
# `install_devices_empty=true` keeps the legacy grub-pc from touching any
# disk on EFI boxes; on a genuine BIOS box the operator pre-seeds the real
# device before running this script.
debconf_set "grub-pc grub-pc/install_devices multiselect"
debconf_set "grub-pc grub-pc/install_devices_empty boolean true"
debconf_set "grub-pc grub-pc/install_devices_failed_upgrade boolean false"

# ---------------------------------------------------------------------------
# Pinned versions
# ---------------------------------------------------------------------------
LLAMA_CPP_REF="${LLAMA_CPP_REF:-b10630}"             # llama.cpp git SHA / tag.
# b10630 (commit d222767) is pinned because it is the first ref validated
# on the reference box that ships `--cpu-moe` (MoE expert CPU offload,
# PR #15077, Aug 2025) — the flag `scripts/serve-35b.sh` depends on for
# the Ornith-1.5-35B quality path. The previous pin b4568 predates it.
# This ref also carries the `<cstdint>` fix (#11796), so the GCC-15
# header patch in docs/08-troubleshooting.md is no longer needed for
# fresh builds.
# Opt-in: also build the PrismML llama.cpp fork for Ternary Bonsai 2
# (scripts/build-bonsai-llama.sh → /opt/guasimo/llama-server-bonsai).
# Default off so a normal install stays lean. Set INSTALL_BONSAI=1 to
# build during phase 3, or run the script later.
INSTALL_BONSAI="${INSTALL_BONSAI:-0}"
# Ollama: minimum 0.32.12 to support qwen3.8:27b (Aug 2026 multimodal /
# thinking generation). 0.32.14 adds WebP image transcoding for
# llama-server and a Qwen renderer fix; the install script tries apt
# first, then the upstream script as a fallback. The string here is the
# minimum acceptable line — a newer 0.32.x in apt satisfies it.
OLLAMA_VERSION="${OLLAMA_VERSION:-0.32.14}"
# Open WebUI requires Python >=3.11,<3.13 (no 3.13+ yet). Ubuntu 26.04's
# default python3 is too new, so we venv with python3.12 (see phase 5).
OPEN_WEBUI_VERSION="${OPEN_WEBUI_VERSION:-0.6.43}"   # open-webui python pkg
REQUIRED_UBUNTU_MAJOR=26
WEBUI_PYTHON_MAX=12                                 # major.minor: 3.WEBUI_PYTHON_MAX

# Repo location after install
INSTALL_ROOT="/opt/guasimo"
LLAMA_SRC_DIR="${INSTALL_ROOT}/llama.cpp"

# Service user
SERVICE_USER="guasimo"

# Logging
LOG_DIR="/var/log/guasimo"
mkdir -p "${LOG_DIR}"
INSTALL_LOG="${LOG_DIR}/install.log"
exec > >(tee -a "${INSTALL_LOG}") 2>&1

banner() { printf "\n\033[1;36m[%s] %s\033[0m\n" "$(date +%H:%M:%S)" "$*"; }
warn()   { printf "\033[1;33mWARN: %s\033[0m\n" "$*" >&2; }
die()    { printf "\033[1;31mFATAL: %s\033[0m\n" "$*" >&2; exit 1; }

# Ubuntu archive ships unversioned NVIDIA packages (nvidia-firmware,
# libnvidia-cfg1, libnvidia-egl-wayland21, …). The NVIDIA CUDA repo ships
# versioned siblings (nvidia-firmware-610-*, libnvidia-cfg1-610, …) that
# install the SAME files. Mixing both schemes leaves apt stuck:
#   dpkg: trying to overwrite '.../gsp_ga10x.bin', which is also in package
#   nvidia-firmware
# Prefer the versioned scheme (what nvidia-driver-NNN from the CUDA repo
# depends on). Purge the unversioned leftovers so apt-get -f can proceed.
# No-op when the unversioned packages are not installed.
purge_unversioned_nvidia_conflict() {
  local pkgs=()
  local cand
  for cand in nvidia-firmware libnvidia-cfg1 libnvidia-egl-wayland21 \
              libnvidia-egl-xcb1 libnvidia-egl-xlib1 libnvidia-gpucomp \
              nvidia-modprobe; do
    if dpkg-query -W -f='${Status}' "${cand}" 2>/dev/null \
         | grep -q 'install ok installed'; then
      pkgs+=("${cand}")
    fi
  done
  if [ "${#pkgs[@]}" -eq 0 ]; then
    return 1
  fi
  echo "  purging unversioned NVIDIA leftovers that conflict with"
  echo "  versioned nvidia-*-NNN packages: ${pkgs[*]}"
  # Must use dpkg directly — apt-get remove refuses while the dependency
  # graph is already broken ("You might want to run apt --fix-broken").
  # --force-depends lets us drop the conflicting unversioned packages
  # without satisfying nvidia-driver-NNN first; apt-get -f then installs
  # the versioned replacements.
  dpkg --purge --force-depends "${pkgs[@]}" || return 1
  return 0
}

# Repair a half-configured dpkg database AND a broken apt dependency graph
# before any apt install. Two distinct failure modes need two distinct checks:
#
#   - dpkg --audit  : catches packages in "half-installed"/"unpacked"/
#     "half-configured" state (interrupted unpack, power loss, Ctrl-C).
#     Fix: dpkg --configure -a.
#   - apt-get check : catches a broken dependency graph that dpkg --audit
#     misses — e.g. nvidia-driver-610 marked "installed" by dpkg but its
#     deps (nvidia-firmware-610, libnvidia-gl-610, ...) unmet, so apt's
#     resolver refuses to proceed with "Unmet dependencies" /
#     "it is not going to be installed". Fix: apt-get -f install.
#
# If apt-get -f install still fails, try the known mixed-repo NVIDIA
# conflict (unversioned Ubuntu packages vs versioned CUDA-repo packages),
# then retry. Never abort the whole install here — caller decides whether
# to fall back to CPU.
#
# Both are no-ops when the system is clean.
recover_dpkg() {
  if [ -n "$(dpkg --audit 2>/dev/null || true)" ]; then
    echo "  repairing half-configured packages (dpkg --configure -a)"
    dpkg --configure -a || warn "dpkg --configure -a failed; continuing"
  fi
  if apt-get check >/dev/null 2>&1; then
    return 0
  fi
  echo "  repairing broken apt dependencies (apt-get -f install)"
  if apt-get -f install -y; then
    return 0
  fi
  warn "apt-get -f install failed; checking for mixed NVIDIA packaging"
  if purge_unversioned_nvidia_conflict; then
    echo "  retrying apt-get -f install after NVIDIA conflict purge"
    if apt-get -f install -y; then
      return 0
    fi
  fi
  warn "could not fully repair apt dependencies; see docs/08-troubleshooting.md"
  return 1
}

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0"

# ---------------------------------------------------------------------------
# Phase 1 — Probe
# ---------------------------------------------------------------------------
banner "phase 1/5  probe"

. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "expected Ubuntu, got: ${ID:-unknown}"
MAJOR="${VERSION_ID%%.*}"
[ "${MAJOR}" -ge "${REQUIRED_UBUNTU_MAJOR}" ] \
  || die "Ubuntu ${REQUIRED_UBUNTU_MAJOR}.xx required; got ${VERSION_ID}"

# CPU features
CPU_FLAGS=$(grep -m1 -oE 'flags[[:space:]]*:.*' /proc/cpuinfo | sed 's/.*://')
HAS_AVX2=$(echo "${CPU_FLAGS}" | grep -qw avx2 && echo y || echo n)
HAS_AVX512=$(echo "${CPU_FLAGS}" | grep -qw avx512f && echo y || echo n)
HAS_FMA=$(echo "${CPU_FLAGS}" | grep -qw fma && echo y || echo n)

# GPU detection.
# Three backends are supported, selected automatically at probe time:
#   - CUDA   : NVIDIA discrete GPU (RTX 3060 / GA106) with driver + nvcc.
#   - Vulkan : AMD Radeon iGPU (Phoenix / RDNA3, e.g. Radeon 760M) with the
#              Mesa radv/aco Vulkan drivers. No proprietary driver needed.
#   - CPU    : fallback when no accelerator is usable.
# Phase A (hardware): lspci works without the proprietary driver loaded.
# Phase B (runtime): nvidia-smi works only after the driver module is loaded.
HAS_NVIDIA_HW=n
HAS_NVIDIA_RT=n
HAS_AMD_HW=n
if command -v lspci >/dev/null 2>&1; then
  if lspci 2>/dev/null | grep -qi 'nvidia'; then
    HAS_NVIDIA_HW=y
  fi
  # AMD APU / GPU. The Radeon 760M reports as "[AMD/ATI] Phoenix1" on a
  # "VGA compatible controller" line. Match ONLY the VGA/display class so
  # that AMD audio controllers (e.g. "Radeon High Definition Audio") don't
  # false-positive the Vulkan backend. The lspci output is captured first so
  # the pipeline never trips `set -o pipefail` when a header class is absent.
  LSPCI_OUT=$(lspci 2>/dev/null || true)
  AMD_GFX=$(printf '%s\n' "${LSPCI_OUT}" | grep -iE 'vga compatible|display controller|3d controller' | grep -i 'amd' || true)
  [ -n "${AMD_GFX}" ] && HAS_AMD_HW=y
fi
if command -v nvidia-smi >/dev/null 2>&1; then
  if nvidia-smi -L >/dev/null 2>&1; then
    HAS_NVIDIA_RT=y
  fi
fi

# Placeholders for the driver/CUDA package names. They are populated in
# phase 2 after `apt-get update` so apt-cache sees fresh metadata.
# Ubuntu releases ship different driver versions (24.04: 560, 26.04: 570+),
# so we never hardcode a number here.
DRIVER_PKG=""
CUDA_PKG=""

# Disk
DATA_DISK="/data"
BULK_DISK="/bulk"
mkdir -p "${DATA_DISK}" "${BULK_DISK}" 2>/dev/null || true

echo "  ubuntu         ${VERSION_ID}"
echo "  CPU features   AVX2=${HAS_AVX2}  AVX512=${HAS_AVX512}  FMA=${HAS_FMA}"
echo "  NVIDIA GPU     hardware=${HAS_NVIDIA_HW}  runtime=${HAS_NVIDIA_RT}"
echo "  AMD GPU        hardware=${HAS_AMD_HW}"
echo "  driver pkg     <detected in phase 2>"
echo "  cuda pkg       <detected in phase 2>"
echo "  data mount     ${DATA_DISK} (created if missing)"
echo "  bulk mount     ${BULK_DISK} (created if missing)"

# Pin CUDA archs for the known GPU on this box. The board has an RTX 3060
# (GA106, SM 86). Hard-coding the arch — instead of using "native" — keeps
# the build reproducible and avoids embedding whatever the build host happens
# to expose. Extend here if a future box has different silicon.
CUDA_ARCHS="86"

# ---------------------------------------------------------------------------
# Phase 2 — Packages
# ---------------------------------------------------------------------------
banner "phase 2/5  packages"

export DEBIAN_FRONTEND=noninteractive

# Repair dpkg before touching apt. If a previous run died mid-install (most
# commonly during the NVIDIA driver unpack), apt is unusable until this runs.
recover_dpkg

PKGS=(build-essential cmake git curl wget jq python3 python3-venv
      python3-pip nginx sqlite3 uuid-runtime ca-certificates
      libssl-dev pkg-config lm-sensors nvme-cli smartmontools)

# Add the detected NVIDIA driver + CUDA toolkit if hardware is present.
# If detection failed (DRIVER_PKG empty), we keep going on CPU and let
# the operator install the driver manually — the runtime check in phase 3
# will still defer the CUDA build correctly.
if [ "${HAS_NVIDIA_HW}" = y ] && [ -n "${DRIVER_PKG}" ]; then
  PKGS+=("${DRIVER_PKG}")
  if [ -n "${CUDA_PKG}" ]; then
    PKGS+=("${CUDA_PKG}")
  fi
fi

# Vulkan runtime AND headers for the AMD path. The Radeon 760M (RDNA3) is
# driven by Mesa's radv/aco Vulkan driver — no proprietary driver, no ROCm.
# llama.cpp's GGML_VULKAN backend needs the Vulkan headers to COMPILE and
# the loader + radv to RUN, so this installs:
#   libvulkan1           loader (runtime)
#   libvulkan-dev        vulkan/vulkan.h headers (build-time)
#   mesa-vulkan-drivers  radv/aco ICD (runtime)
#   vulkan-tools         vulkaninfo, used by probe/healthcheck
#   glslc                GLSL→SPIR-V compiler (llama.cpp's Vulkan backend
#                        fails CMake configure without the glslc binary;
#                        on Ubuntu this is its OWN package, NOT glslang-tools)
#   spirv-headers        SPIRV-Headers cmake package (find_package fails
#                        without it — provides SPIRV-HeadersConfig.cmake)
#   spirv-tools          spirv-opt/dis (used by ggml-vulkan shader pipeline)
if [ "${HAS_AMD_HW}" = y ] && [ "${HAS_NVIDIA_HW}" != y ]; then
  PKGS+=(libvulkan1 libvulkan-dev mesa-vulkan-drivers vulkan-tools glslc spirv-headers spirv-tools)
fi

if ! dpkg -s "${PKGS[@]}" >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends "${PKGS[@]}"
else
  echo "  all required apt packages already present"
fi

# After apt-get update the package cache is fresh. Detect the NVIDIA
# driver/CUDA package names available for THIS Ubuntu release.
# This used to be pinned to nvidia-driver-555; that broke on Ubuntu 26.04.
if [ "${HAS_NVIDIA_HW}" = y ] && [ -z "${DRIVER_PKG}" ]; then
  # Prefer the latest numbered nvidia-driver-* (sort -V picks highest version).
  DRIVER_PKG=$(apt-cache search '^nvidia-driver-[0-9]+$' 2>/dev/null \
                | awk '{print $1}' | sort -V | tail -1 || true)
  # Fallback: metapackage.
  if [ -z "${DRIVER_PKG}" ] \
     && apt-cache show nvidia-driver >/dev/null 2>&1; then
    DRIVER_PKG="nvidia-driver"
  fi
  # CUDA toolkit: prefer numbered, else metapackage.
  CUDA_PKG=$(apt-cache search '^nvidia-cuda-toolkit-[0-9]+$' 2>/dev/null \
              | awk '{print $1}' | sort -V | tail -1 || true)
  if [ -z "${CUDA_PKG}" ] \
     && apt-cache show nvidia-cuda-toolkit >/dev/null 2>&1; then
    CUDA_PKG="nvidia-cuda-toolkit"
  fi
  # Ubuntu 26.04 (resolute) does not ship nvidia-driver-* in the main
  # archive; the package comes from the NVIDIA CUDA repo at
  # developer.download.nvidia.com. If apt-cache returned nothing but
  # that repo is present, query it explicitly.
  if [ -z "${DRIVER_PKG}" ] \
     && ls /etc/apt/sources.list.d/ 2>/dev/null \
        | grep -qi 'nvidia\|cuda'; then
    DRIVER_PKG=$(apt-cache search '^nvidia-driver-[0-9]+$' 2>/dev/null \
                  | awk '{print $1}' | sort -V | tail -1 || true)
  fi
  # If we found a driver now, install it (apt-get was a no-op above because
  # we hadn't decided yet). Use apt-get install -y directly. This is the
  # step most likely to fail: the NVIDIA driver unpack can hit conflicts
  # with leftover packages from a previous driver version, broken dpkg
  # state, or Secure Boot / MOK issues. Per docs/05-deployment.md the
  # contract is "warn and continue on CPU" — so we do not let this kill
  # the whole install. The operator fixes the driver and re-runs.
  if [ -n "${DRIVER_PKG}" ]; then
    echo "  detected NVIDIA packages: ${DRIVER_PKG}${CUDA_PKG:+ $CUDA_PKG}"
    if apt-get install -y --no-install-recommends "${DRIVER_PKG}" ${CUDA_PKG:+"${CUDA_PKG}"}; then
      :
    else
      warn "NVIDIA driver install failed (dpkg error). Attempting to repair dpkg state."
      recover_dpkg
      warn "the NVIDIA driver could not be installed. Falling back to CPU"
      warn "for this run. See docs/08-troubleshooting.md (NVIDIA driver"
      warn "installation). After fixing the driver, re-run $0 to enable CUDA."
      # Treat the box as CPU-only for this run so phase 3 builds a working
      # CPU binary instead of deferring and leaving nothing built.
      HAS_NVIDIA_HW=n
      HAS_NVIDIA_RT=n
      DRIVER_PKG=""
      CUDA_PKG=""
    fi
  else
    warn "no nvidia-driver-* package found in apt; install the driver manually"
    warn "see docs/08-troubleshooting.md (NVIDIA driver installation)"
  fi
fi

# Service user (idempotent)
if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --shell /usr/sbin/nologin --home-dir "${INSTALL_ROOT}" \
          --comment "guasimo services" "${SERVICE_USER}"
fi

# Vulkan on AMD needs access to the DRM render node /dev/dri/renderD128,
# which is root:render (crw-rw----). Without `render` membership the Mesa
# radv ICD silently fails to enumerate and Vulkan falls back to llvmpipe
# (software rasterizer) — the build is fine, but every GPU inference then
# runs on CPU and shows the same token/s as a no-GPU box. This is the
# classic "Vulkan compiled but 0 layers offload" failure that is invisible
# until you benchmark. Put the service user in `render`+`video` so
# llama-server (run as SERVICE_USER) can open the device. The ollama
# daemon user is handled in phase 4 once that user exists.
usermod_render_group() {
  local u="$1"
  if id -u "$u" >/dev/null 2>&1; then
    usermod -aG render,video "$u" >/dev/null 2>&1 || \
      warn "could not add $u to render,video (see docs/05-deployment.md)"
  fi
}
if [ "${HAS_AMD_HW}" = y ]; then
  usermod_render_group "${SERVICE_USER}"
  echo "  AMD render access: ${SERVICE_USER} → groups render,video"
fi

mkdir -p "${INSTALL_ROOT}" "${LOG_DIR}" "${DATA_DISK}/models" \
         "${BULK_DISK}/models" "${DATA_DISK}/open-webui"
# Parents must stay world-traversable (o+x). Do NOT chown all of /data to
# guasimo — the Ollama daemon runs as user `ollama` and needs to own
# OLLAMA_MODELS (/data/models). WebUI data stays with SERVICE_USER.
chmod 755 "${DATA_DISK}" "${BULK_DISK}" "${DATA_DISK}/models" \
          "${BULK_DISK}/models" 2>/dev/null || true
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_ROOT}" "${LOG_DIR}" \
         "${DATA_DISK}/open-webui"

# ---------------------------------------------------------------------------
# Phase 3 — llama.cpp
# ---------------------------------------------------------------------------
banner "phase 3/5  llama.cpp"

# Build flag matrix (mirrors docs/02-hardware-decisions.md).
#
# Backend selection order:
#   - CUDA   : NVIDIA runtime working + nvcc present → SM 86 (RTX 3060).
#   - Vulkan : AMD iGPU present → GGML_VULKAN, offload as many layers as
#              fit in the APU's shared VRAM carve-out. The Radeon 760M is
#              RDNA3, driven by Mesa radv/aco (no ROCm needed).
#   - CPU    : fallback, -march=native (AVX2/AVX-512 auto-selected).
CMAKE_FLAGS=()
USE_CUDA=n
USE_VULKAN=n
if [ "${HAS_NVIDIA_RT}" = y ] && [ "${HAS_NVIDIA_HW}" = y ] \
   && command -v nvcc >/dev/null 2>&1; then
  USE_CUDA=y
  CMAKE_FLAGS+=("-DGGML_CUDA=ON" "-DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHS}")
  CMAKE_FLAGS+=("-DGGML_NATIVE=OFF")
elif [ "${HAS_AMD_HW}" = y ]; then
  # Prefer a working AMD/Vulkan path over waiting on an unloaded NVIDIA
  # driver. Hybrid boxes (dead NVIDIA + live AMD APU) still get a GPU build.
  USE_VULKAN=y
  CMAKE_FLAGS+=("-DGGML_VULKAN=ON" "-DGGML_NATIVE=ON")
  if [ "${HAS_NVIDIA_HW}" = y ] && [ "${HAS_NVIDIA_RT}" = n ]; then
    warn "NVIDIA hardware present but nvidia-smi is not working; building"
    warn "Vulkan (AMD) for this run. Reboot + re-run $0 for CUDA later."
  fi
elif [ "${HAS_NVIDIA_HW}" = y ] && [ "${HAS_NVIDIA_RT}" = n ]; then
  warn "NVIDIA hardware detected but nvidia-smi is not working."
  warn "Driver package was installed in phase 2; a reboot is required"
  warn "to load the kernel module. Skipping CUDA build of llama.cpp this"
  warn "run. Reboot and re-run $0 to finish the CUDA build."
fi

# CPU build is always the fallback path. We use -march=native only when no
# accelerator path is in play (CUDA prefers a pinned arch; Vulkan keeps
# native so the CPU kernels stay tuned for the host).
if [ "${USE_CUDA}" = n ] && [ "${USE_VULKAN}" = n ]; then
  CMAKE_FLAGS+=("-DGGML_NATIVE=ON")
fi

# Cap parallel build jobs at (nproc - 2), floor 1. A bare `--parallel`
# spawns one job per core; on a 12-core box the CUDA compile floods the
# machine (load avg >100, `ptxas`/`cicc` saturating every core) and starves
# nginx + Open WebUI that are already live, so the WebUI stops answering
# while the build runs. Leaving two cores free keeps the frontend
# responsive; CUDA translation units are largely single-threaded per
# `ptxas` invocation, so wall-clock impact is minimal.
BUILD_JOBS="${BUILD_JOBS:-$(( $(nproc) - 2 ))}"
[ "${BUILD_JOBS}" -lt 1 ] && BUILD_JOBS=1

# Root runs this script; phase 2 chowns INSTALL_ROOT to SERVICE_USER, so
# git refuses the tree with "fatal: detected dubious ownership". Mark the
# tree safe for root (covers our git calls AND cmake's build_info target,
# which shells out to git without our -c wrapper).
mark_llama_safe_directory() {
  [ -d "${LLAMA_SRC_DIR}/.git" ] || return 0
  if ! git config --global --get-all safe.directory 2>/dev/null \
       | grep -qx "${LLAMA_SRC_DIR}"; then
    git config --global --add safe.directory "${LLAMA_SRC_DIR}"
  fi
}
mark_llama_safe_directory
git_llama() {
  git -c "safe.directory=${LLAMA_SRC_DIR}" -C "${LLAMA_SRC_DIR}" "$@"
}

# Desired accelerator identity for this run. Written to a stamp after a
# successful build so a later re-run with the same LLAMA_CPP_REF but a
# different backend (e.g. CPU → Vulkan after AMD packages land) forces a
# rebuild instead of silently keeping the old binary.
BACKEND_ID=cpu
[ "${USE_CUDA}" = y ] && BACKEND_ID=cuda
[ "${USE_VULKAN}" = y ] && BACKEND_ID=vulkan
BACKEND_STAMP="${INSTALL_ROOT}/.llama-backend"

# Build if missing or SHA drifted. Accept either the install symlink or
# the cmake output path (operator may have built by hand mid-install).
# Compare resolved commit SHAs — LLAMA_CPP_REF is often a tag (b10630)
# while rev-parse --short HEAD is a commit id (a4417dd); string equality
# on those never matches and forced a rebuild every run.
NEED_BUILD=y
if { [ -x "${INSTALL_ROOT}/llama-server" ] \
     || [ -x "${LLAMA_SRC_DIR}/build/bin/llama-server" ]; } \
   && [ -d "${LLAMA_SRC_DIR}/.git" ]; then
  CURRENT_SHA=$(git_llama rev-parse HEAD 2>/dev/null || echo none)
  PINNED_SHA=$(git_llama rev-parse "${LLAMA_CPP_REF}^{commit}" 2>/dev/null || echo none)
  PREV_BACKEND=none
  [ -f "${BACKEND_STAMP}" ] && PREV_BACKEND=$(cat "${BACKEND_STAMP}" 2>/dev/null || echo none)
  if [ "${CURRENT_SHA}" != none ] && [ "${CURRENT_SHA}" = "${PINNED_SHA}" ] \
     && [ "${PREV_BACKEND}" = "${BACKEND_ID}" ]; then
    NEED_BUILD=n
    echo "  llama.cpp already built at ${LLAMA_CPP_REF} (${CURRENT_SHA:0:7}, ${BACKEND_ID})"
  elif [ "${PREV_BACKEND}" != none ] && [ "${PREV_BACKEND}" != "${BACKEND_ID}" ]; then
    echo "  llama.cpp backend changed (${PREV_BACKEND} → ${BACKEND_ID}); rebuilding"
  fi
fi

if [ "${NEED_BUILD}" = y ] && [ "${USE_CUDA}" = n ] && [ "${USE_VULKAN}" = n ] \
   && [ "${HAS_NVIDIA_HW}" = y ] && [ "${HAS_NVIDIA_RT}" = n ]; then
  # Skip the build to avoid producing a CPU-only binary when a CUDA build
  # will be needed post-reboot. Phase 4 (Ollama) and 5 (WebUI) still proceed
  # so the box is functional on CPU until the reboot happens. Vulkan path
  # above already took over when AMD hw is present.
  echo "  deferring llama.cpp build until after reboot (CUDA path)"
  NEED_BUILD=n
fi

# GCC 15 (Ubuntu 26.04) no longer transitively provides uint32_t via
# <vector>/<memory>. llama.cpp b4568 predates upstream fix #11796
# (add #include <cstdint> to src/llama-mmap.h). The pinned ref now
# carries it, so this is a legacy safety net that no-ops on fresh
# builds; kept for manual rebuilds against older SHAs.
patch_llama_gcc15() {
  local hdr="${LLAMA_SRC_DIR}/src/llama-mmap.h"
  [ -f "${hdr}" ] || return 0
  if grep -q '#include <cstdint>' "${hdr}"; then
    return 0
  fi
  echo "  patching src/llama-mmap.h for GCC 15 (#include <cstdint>)"
  # Insert after #pragma once (or at top if absent).
  if grep -q '#pragma once' "${hdr}"; then
    sed -i '/#pragma once/a\
\
#include <cstdint>' "${hdr}"
  else
    sed -i '1i#include <cstdint>\n' "${hdr}"
  fi
}

if [ "${NEED_BUILD}" = y ]; then
  if [ ! -d "${LLAMA_SRC_DIR}" ]; then
    git clone --depth=1 --branch "${LLAMA_CPP_REF}" \
        https://github.com/ggerganov/llama.cpp "${LLAMA_SRC_DIR}"
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "${LLAMA_SRC_DIR}"
  else
    git_llama fetch --depth=1 origin "${LLAMA_CPP_REF}"
    # A previous run may have left the legacy GCC-15 header patch in the
    # tree (src/llama-mmap.h). `checkout FETCH_HEAD` aborts with "local
    # changes would be overwritten" unless we discard it first. The patch
    # is re-applied below by patch_llama_gcc15 if the ref still needs it
    # (b10630+ does not), so discarding it here is safe.
    git_llama checkout -- .
    git_llama checkout FETCH_HEAD
  fi
  mark_llama_safe_directory
  patch_llama_gcc15
  cmake -S "${LLAMA_SRC_DIR}" -B "${LLAMA_SRC_DIR}/build" \
        -DCMAKE_BUILD_TYPE=Release "${CMAKE_FLAGS[@]}"
  cmake --build "${LLAMA_SRC_DIR}/build" --parallel "${BUILD_JOBS}"
  strip "${LLAMA_SRC_DIR}/build/bin/llama-server" \
        "${LLAMA_SRC_DIR}/build/bin/llama-cli"
  printf '%s\n' "${BACKEND_ID}" > "${BACKEND_STAMP}"
  chown "${SERVICE_USER}:${SERVICE_USER}" "${BACKEND_STAMP}" 2>/dev/null || true
fi

# Always symlink. If we deferred the build, the symlink will point at a
# stale or missing binary; the healthcheck script reports that clearly.
ln -sf "${LLAMA_SRC_DIR}/build/bin/llama-server" "${INSTALL_ROOT}/llama-server"
ln -sf "${LLAMA_SRC_DIR}/build/bin/llama-cli"    "${INSTALL_ROOT}/llama-cli"
chown -h "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_ROOT}/llama-server" \
                                           "${INSTALL_ROOT}/llama-cli"

echo "  build flags: ${CMAKE_FLAGS[*]:-<deferred, see warning above>}"
echo "  cuda build:  ${USE_CUDA}"
echo "  vulkan build: ${USE_VULKAN}"
echo "  backend id:  ${BACKEND_ID}"

# Optional PrismML fork for Ternary Bonsai 2 (parallel binary, not Ollama).
if [ "${INSTALL_BONSAI}" = "1" ] || [ "${INSTALL_BONSAI}" = "y" ]; then
  echo "  INSTALL_BONSAI=${INSTALL_BONSAI} → building PrismML llama.cpp fork"
  # Prefer repo-relative script when install is run from a git checkout;
  # fall back to INSTALL_ROOT copy if an operator re-runs from /opt.
  BONSAI_BUILD=""
  for cand in \
      "$(cd "$(dirname "$0")/.." && pwd)/scripts/build-bonsai-llama.sh" \
      "${INSTALL_ROOT}/scripts/build-bonsai-llama.sh" \
      "./scripts/build-bonsai-llama.sh"; do
    [ -x "${cand}" ] && BONSAI_BUILD="${cand}" && break
  done
  if [ -n "${BONSAI_BUILD}" ]; then
    "${BONSAI_BUILD}"
  else
    warn "INSTALL_BONSAI set but scripts/build-bonsai-llama.sh not found"
  fi
fi

# ---------------------------------------------------------------------------
# Phase 4 — Ollama
# ---------------------------------------------------------------------------
banner "phase 4/5  ollama"

if ! command -v ollama >/dev/null 2>&1; then
  if apt-cache policy ollama 2>/dev/null | grep -q "Candidate:" \
     && [ "$(apt-cache policy ollama | awk '/Candidate:/{print $2}')" != "(none)" ]; then
    apt-get install -y --no-install-recommends ollama
  else
    curl -fsSL https://ollama.com/install.sh | sh
  fi
else
  echo "  ollama already installed: $(ollama --version 2>/dev/null || echo unknown)"
fi

mkdir -p /etc/systemd/system/ollama.service.d
# Backticks in the comment block are backslash-escaped so the heredoc
# does not try to execute them as command substitution. The variables
# \${INSTALL_ROOT} and \${DATA_DISK} are intentionally expanded; the
# escape only affects the backticks.
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_LLAMA_SERVER=${INSTALL_ROOT}/llama-server"
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_MODELS=${DATA_DISK}/models"
Environment="OLLAMA_DEBUG=false"
# Server-side default for how long a model stays loaded after the last
# request. Used to be a Modelfile PARAMETER (\`keep_alive\` 10m) in
# v0.2.x; removed from the supported PARAMETER list in Ollama 0.32.x.
# Per-request override is still available via the API's
# \`keep_alive\` field.
Environment="OLLAMA_KEEP_ALIVE=10m"
EOF

# Ollama's unit runs as User=ollama (upstream default). Give that user
# ownership of the models dir or serve dies with:
#   mkdir /data/models/blobs: permission denied
OLLAMA_USER=$(systemctl show -p User --value ollama.service 2>/dev/null || true)
OLLAMA_USER="${OLLAMA_USER:-ollama}"
if id -u "${OLLAMA_USER}" >/dev/null 2>&1; then
  echo "  chown ${DATA_DISK}/models → ${OLLAMA_USER}:${OLLAMA_USER}"
  chown -R "${OLLAMA_USER}:${OLLAMA_USER}" \
    "${DATA_DISK}/models" "${BULK_DISK}/models"
  # Same DRM render-node requirement as phase 2. Ollama runs as
  # User=ollama; without `render` membership its llama-server (whatever
  # backend) cannot open /dev/dri/renderD128 and Vulkan silently falls
  # back to CPU. Add it here now that the user exists.
  if [ "${HAS_AMD_HW}" = y ]; then
    usermod -aG render,video "${OLLAMA_USER}" >/dev/null 2>&1 || \
      warn "could not add ${OLLAMA_USER} to render,video"
    echo "  AMD render access: ${OLLAMA_USER} → groups render,video"
    # Group membership is resolved at process start. If ollama is already
    # running, restart so the new render/video groups actually apply —
    # otherwise Vulkan silently falls back to llvmpipe/CPU.
    OLLAMA_NEEDS_RESTART=y
  fi
fi

systemctl daemon-reload
systemctl enable --now ollama
if [ "${OLLAMA_NEEDS_RESTART:-n}" = y ]; then
  systemctl restart ollama
  echo "  restarted ollama (pick up render/video group membership)"
fi

# ---------------------------------------------------------------------------
# Phase 5 — Open WebUI + nginx
# ---------------------------------------------------------------------------
banner "phase 5/5  open-webui + nginx"

# Open WebUI wheels require Python >=3.11,<3.13. Ubuntu 26.04 (resolute)
# ships only python3.13+ in the archive — no python3.12 package. Prefer a
# distro 3.11/3.12 if present; otherwise bootstrap CPython 3.12 via uv
# into INSTALL_ROOT (no PPA, no system PATH pollution).
ensure_webui_python() {
  local cand
  for cand in python3.12 python3.11; do
    if command -v "${cand}" >/dev/null 2>&1; then
      WEBUI_PYTHON=$(command -v "${cand}")
      return 0
    fi
  done

  UV_DIR="${INSTALL_ROOT}/uv"
  UV_BIN="${UV_DIR}/uv"
  UV_PYTHON_DIR="${INSTALL_ROOT}/python"
  mkdir -p "${UV_DIR}" "${UV_PYTHON_DIR}"
  if [ ! -x "${UV_BIN}" ]; then
    echo "  bootstrapping uv into ${UV_DIR} (no python3.12 in apt)"
    curl -LsSf https://astral.sh/uv/install.sh \
      | env UV_UNMANAGED_INSTALL="${UV_DIR}" sh
  fi
  [ -x "${UV_BIN}" ] || die "uv bootstrap failed; expected ${UV_BIN}"
  echo "  installing CPython 3.12 via uv into ${UV_PYTHON_DIR}"
  UV_PYTHON_INSTALL_DIR="${UV_PYTHON_DIR}" \
    "${UV_BIN}" python install 3.12
  WEBUI_PYTHON=$(UV_PYTHON_INSTALL_DIR="${UV_PYTHON_DIR}" \
    "${UV_BIN}" python find 3.12)
  [ -n "${WEBUI_PYTHON}" ] && [ -x "${WEBUI_PYTHON}" ] \
    || die "uv python find 3.12 returned nothing"
}

WEBUI_PYTHON=""
ensure_webui_python
WEBUI_PY_MINOR=$("${WEBUI_PYTHON}" -c 'import sys; print(sys.version_info.minor)')
if [ "${WEBUI_PY_MINOR}" -lt 11 ] || [ "${WEBUI_PY_MINOR}" -gt "${WEBUI_PYTHON_MAX}" ]; then
  die "Open WebUI needs Python 3.11–3.12; got ${WEBUI_PYTHON} (3.${WEBUI_PY_MINOR})"
fi
echo "  Open WebUI venv python: ${WEBUI_PYTHON} (3.${WEBUI_PY_MINOR})"

WEBUI_VENV="${INSTALL_ROOT}/webui-venv"
# Recreate the venv if missing or built with an unsupported interpreter
# (e.g. a previous run used system python3.13 and left an empty/broken venv).
NEED_VENV=y
if [ -x "${WEBUI_VENV}/bin/python" ]; then
  VENV_MINOR=$("${WEBUI_VENV}/bin/python" -c \
    'import sys; print(sys.version_info.minor)' 2>/dev/null || echo 99)
  if [ "${VENV_MINOR}" -ge 11 ] && [ "${VENV_MINOR}" -le "${WEBUI_PYTHON_MAX}" ]; then
    NEED_VENV=n
  else
    echo "  recreating venv (was Python 3.${VENV_MINOR}; need 3.11–3.12)"
    rm -rf "${WEBUI_VENV}"
  fi
fi
if [ "${NEED_VENV}" = y ]; then
  "${WEBUI_PYTHON}" -m venv "${WEBUI_VENV}"
fi
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${WEBUI_VENV}" \
  "${INSTALL_ROOT}/uv" "${INSTALL_ROOT}/python" 2>/dev/null || true
"${WEBUI_VENV}/bin/pip" install --upgrade pip wheel >/dev/null
# Open WebUI pulls torch (RAG / Whisper / embeddings). Default torch
# wheels drag nvidia-*-cu13 pip packages (~1 GB+) that duplicate the
# host driver and are unused — Ollama + our llama.cpp own the GPU.
# Pin CPU torch first so the resolver does not fetch CUDA wheels.
echo "  installing CPU-only torch (avoid pip nvidia/CUDA wheels)"
"${WEBUI_VENV}/bin/pip" install \
  --index-url https://download.pytorch.org/whl/cpu \
  torch
echo "  installing open-webui==${OPEN_WEBUI_VERSION} (large; RAG stack)"
"${WEBUI_VENV}/bin/pip" install \
  "open-webui==${OPEN_WEBUI_VERSION}" "httpx" "uvicorn"

# Install ops scripts under INSTALL_ROOT (logrotate timer, thermal, etc.).
mkdir -p "${INSTALL_ROOT}/scripts"
cp scripts/rotate-logs.sh "${INSTALL_ROOT}/scripts/rotate-logs.sh"
chmod 755 "${INSTALL_ROOT}/scripts/rotate-logs.sh"
# Thermal helpers: guard is one-shot (called by serve-35b / operators);
# monitor is the long-lived systemd daemon. Always install both so AMD
# boxes and operators on CUDA boxes share the same paths.
cp scripts/thermal-guard.sh "${INSTALL_ROOT}/scripts/thermal-guard.sh"
cp scripts/thermal-monitor.sh "${INSTALL_ROOT}/scripts/thermal-monitor.sh"
# Bonsai quality path (optional; binary built only with INSTALL_BONSAI=1).
cp scripts/build-bonsai-llama.sh "${INSTALL_ROOT}/scripts/build-bonsai-llama.sh"
cp scripts/serve-bonsai.sh "${INSTALL_ROOT}/scripts/serve-bonsai.sh"
chmod 755 "${INSTALL_ROOT}/scripts/thermal-guard.sh" \
          "${INSTALL_ROOT}/scripts/thermal-monitor.sh" \
          "${INSTALL_ROOT}/scripts/build-bonsai-llama.sh" \
          "${INSTALL_ROOT}/scripts/serve-bonsai.sh"
chown "${SERVICE_USER}:${SERVICE_USER}" \
  "${INSTALL_ROOT}/scripts/thermal-guard.sh" \
  "${INSTALL_ROOT}/scripts/thermal-monitor.sh" \
  "${INSTALL_ROOT}/scripts/build-bonsai-llama.sh" \
  "${INSTALL_ROOT}/scripts/serve-bonsai.sh"

cp deploy/systemd/open-webui.service /etc/systemd/system/open-webui.service
cp deploy/systemd/guasimo.target       /etc/systemd/system/guasimo.target
cp deploy/systemd/guasimo-logrotate.service \
   /etc/systemd/system/guasimo-logrotate.service
cp deploy/systemd/guasimo-logrotate.timer \
   /etc/systemd/system/guasimo-logrotate.timer
cp deploy/systemd/guasimo-thermal.service \
   /etc/systemd/system/guasimo-thermal.service
systemctl daemon-reload
systemctl enable --now open-webui.service guasimo.target
systemctl enable --now guasimo-logrotate.timer
# Thermal monitor is the always-on signal for the AMD mini-PC capacitor
# burn-out failure mode. Enable only when AMD hw is present; CUDA boxes
# keep nvidia-smi / their own thermal path and do not need this unit.
if [ "${HAS_AMD_HW}" = y ]; then
  systemctl enable --now guasimo-thermal.service
  echo "  enabled guasimo-thermal.service (AMD SoC/GPU junction)"
else
  systemctl disable --now guasimo-thermal.service 2>/dev/null || true
fi

# Self-signed cert BEFORE nginx -t — the vhost references these paths
# and `nginx -t` fails hard if they are missing on first install.
HOSTNAME_FQDN=$(hostname -f 2>/dev/null || hostname)
CERT_DIR="/etc/nginx/ssl/guasimo"
mkdir -p "${CERT_DIR}"
if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
  echo "  generating self-signed TLS cert for ${HOSTNAME_FQDN}"
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=${HOSTNAME_FQDN}" \
    -keyout "${CERT_DIR}/privkey.pem" \
    -out    "${CERT_DIR}/fullchain.pem" >/dev/null
  chmod 600 "${CERT_DIR}/privkey.pem"
fi

# nginx — drop legacy ia-lab vhost if present from a pre-rebrand install
rm -f /etc/nginx/sites-enabled/ia-lab.conf \
      /etc/nginx/sites-available/ia-lab.conf
cp deploy/nginx/sites-available/guasimo.conf /etc/nginx/sites-available/guasimo.conf
ln -sf /etc/nginx/sites-available/guasimo.conf /etc/nginx/sites-enabled/guasimo.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
banner "done"
cat <<EOF

URLs:
  chat   https://${HOSTNAME_FQDN}/      (accept self-signed cert)
  API    http://127.0.0.1:11434/v1/chat/completions

Next steps:
  ./scripts/pull-models.sh primary
  ./scripts/benchmark.sh   primary
  ./scripts/healthcheck.sh
  # optional dense-intelligence path (Prism ML Bonsai 2):
  #   INSTALL_BONSAI=1  (already built if you set it) or
  #   sudo ./scripts/build-bonsai-llama.sh
  #   ./scripts/pull-models.sh bonsai   # prints GGUF drop instructions
  #   ./scripts/serve-bonsai.sh         # :8083 OpenAI-compat

Install log: ${INSTALL_LOG}
EOF