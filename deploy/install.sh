#!/usr/bin/env bash
# deploy/install.sh — install the local LLM stack on Ubuntu 26.04.
#
# Idempotent. Run as root (or with sudo). Honours the contract in
# docs/05-deployment.md. All decisions are logged.

set -euo pipefail

# ---------------------------------------------------------------------------
# Pinned versions
# ---------------------------------------------------------------------------
LLAMA_CPP_REF="${LLAMA_CPP_REF:-b4568}"              # llama.cpp git SHA / tag
OLLAMA_VERSION="${OLLAMA_VERSION:-0.5.7}"            # fallback if apt < this
OPEN_WEBUI_VERSION="${OPEN_WEBUI_VERSION:-0.3.21}"   # open-webui python pkg
REQUIRED_UBUNTU_MAJOR=26

# Repo location after install
INSTALL_ROOT="/opt/ia-lab"
LLAMA_SRC_DIR="${INSTALL_ROOT}/llama.cpp"

# Service user
SERVICE_USER="ia-lab"

# Logging
LOG_DIR="/var/log/ia-lab"
mkdir -p "${LOG_DIR}"
INSTALL_LOG="${LOG_DIR}/install.log"
exec > >(tee -a "${INSTALL_LOG}") 2>&1

banner() { printf "\n\033[1;36m[%s] %s\033[0m\n" "$(date +%H:%M:%S)" "$*"; }
warn()   { printf "\033[1;33mWARN: %s\033[0m\n" "$*" >&2; }
die()    { printf "\033[1;31mFATAL: %s\033[0m\n" "$*" >&2; exit 1; }

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
# Both are no-ops when the system is clean.
recover_dpkg() {
  if [ -n "$(dpkg --audit 2>/dev/null || true)" ]; then
    echo "  repairing half-configured packages (dpkg --configure -a)"
    dpkg --configure -a
  fi
  if ! apt-get check >/dev/null 2>&1; then
    echo "  repairing broken apt dependencies (apt-get -f install)"
    apt-get -f install -y
  fi
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
# Phase A (hardware): lspci works without the proprietary driver loaded.
# Phase B (runtime): nvidia-smi works only after the driver module is loaded.
HAS_NVIDIA_HW=n
HAS_NVIDIA_RT=n
if command -v lspci >/dev/null 2>&1; then
  if lspci 2>/dev/null | grep -qi 'nvidia'; then
    HAS_NVIDIA_HW=y
  fi
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
          --comment "ia-lab services" "${SERVICE_USER}"
fi

mkdir -p "${INSTALL_ROOT}" "${LOG_DIR}" "${DATA_DISK}/models" \
         "${BULK_DISK}/models" "${DATA_DISK}/open-webui"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_ROOT}" "${LOG_DIR}" \
         "${DATA_DISK}" "${BULK_DISK}"

# ---------------------------------------------------------------------------
# Phase 3 — llama.cpp
# ---------------------------------------------------------------------------
banner "phase 3/5  llama.cpp"

# Build flag matrix (mirrors docs/02-hardware-decisions.md).
#
# - GPU runtime working + CUDA toolkit installed → CUDA build, SM 86 arch.
# - GPU hardware present but driver not yet loaded (first install, pre-reboot)
#   → skip the CUDA build this run, log a clear "reboot + rerun" message.
# - No NVIDIA at all → CPU build with -march=native on this i5.
CMAKE_FLAGS=()
USE_CUDA=n
if [ "${HAS_NVIDIA_RT}" = y ] && [ "${HAS_NVIDIA_HW}" = y ] \
   && command -v nvcc >/dev/null 2>&1; then
  USE_CUDA=y
  CMAKE_FLAGS+=("-DGGML_CUDA=ON" "-DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHS}")
  CMAKE_FLAGS+=("-DGGML_NATIVE=OFF")
elif [ "${HAS_NVIDIA_HW}" = y ] && [ "${HAS_NVIDIA_RT}" = n ]; then
  warn "NVIDIA hardware detected but nvidia-smi is not working."
  warn "Driver package was installed in phase 2; a reboot is required"
  warn "to load the kernel module. Skipping CUDA build of llama.cpp this"
  warn "run. Reboot and re-run $0 to finish the CUDA build."
fi

# CPU build is always built — it is the fallback path. We use -march=native
# only when no CUDA path is in play to keep AVX2/AVX-512 selection automatic.
if [ "${USE_CUDA}" = n ]; then
  CMAKE_FLAGS+=("-DGGML_NATIVE=ON")
fi

# Build if missing or SHA drifted
NEED_BUILD=y
if [ -x "${INSTALL_ROOT}/llama-server" ] && [ -d "${LLAMA_SRC_DIR}/.git" ]; then
  CURRENT_SHA=$(git -C "${LLAMA_SRC_DIR}" rev-parse --short HEAD 2>/dev/null || echo none)
  if [ "${CURRENT_SHA}" = "${LLAMA_CPP_REF}" ]; then
    NEED_BUILD=n
    echo "  llama.cpp already built at ${LLAMA_CPP_REF}"
  fi
fi

if [ "${NEED_BUILD}" = y ] && [ "${USE_CUDA}" = n ] \
   && [ "${HAS_NVIDIA_HW}" = y ] && [ "${HAS_NVIDIA_RT}" = n ]; then
  # Skip the build to avoid producing a CPU-only binary when a CUDA build
  # will be needed post-reboot. Phase 4 (Ollama) and 5 (WebUI) still proceed
  # so the box is functional on CPU until the reboot happens.
  echo "  deferring llama.cpp build until after reboot (CUDA path)"
  NEED_BUILD=n
fi

if [ "${NEED_BUILD}" = y ]; then
  if [ ! -d "${LLAMA_SRC_DIR}" ]; then
    git clone --depth=1 --branch "${LLAMA_CPP_REF}" \
        https://github.com/ggerganov/llama.cpp "${LLAMA_SRC_DIR}"
  else
    git -C "${LLAMA_SRC_DIR}" fetch --depth=1 origin "${LLAMA_CPP_REF}"
    git -C "${LLAMA_SRC_DIR}" checkout FETCH_HEAD
  fi
  cmake -S "${LLAMA_SRC_DIR}" -B "${LLAMA_SRC_DIR}/build" \
        -DCMAKE_BUILD_TYPE=Release "${CMAKE_FLAGS[@]}"
  cmake --build "${LLAMA_SRC_DIR}/build" --parallel
  strip "${LLAMA_SRC_DIR}/build/bin/llama-server" \
        "${LLAMA_SRC_DIR}/build/bin/llama-cli"
fi

# Always symlink. If we deferred the build, the symlink will point at a
# stale or missing binary; the healthcheck script reports that clearly.
ln -sf "${LLAMA_SRC_DIR}/build/bin/llama-server" "${INSTALL_ROOT}/llama-server"
ln -sf "${LLAMA_SRC_DIR}/build/bin/llama-cli"    "${INSTALL_ROOT}/llama-cli"
chown -h "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_ROOT}/llama-server" \
                                           "${INSTALL_ROOT}/llama-cli"

echo "  build flags: ${CMAKE_FLAGS[*]:-<deferred, see warning above>}"
echo "  cuda build:  ${USE_CUDA}"

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
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_LLAMA_SERVER=${INSTALL_ROOT}/llama-server"
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_MODELS=${DATA_DISK}/models"
Environment="OLLAMA_DEBUG=false"
EOF

systemctl daemon-reload
systemctl enable --now ollama

# ---------------------------------------------------------------------------
# Phase 5 — Open WebUI + nginx
# ---------------------------------------------------------------------------
banner "phase 5/5  open-webui + nginx"

WEBUI_VENV="${INSTALL_ROOT}/webui-venv"
if [ ! -d "${WEBUI_VENV}" ]; then
  python3 -m venv "${WEBUI_VENV}"
fi
"${WEBUI_VENV}/bin/pip" install --upgrade pip wheel >/dev/null
"${WEBUI_VENV}/bin/pip" install \
  "open-webui==${OPEN_WEBUI_VERSION}" "httpx" "uvicorn"

cp deploy/systemd/open-webui.service /etc/systemd/system/open-webui.service
cp deploy/systemd/ia-lab.target       /etc/systemd/system/ia-lab.target
systemctl daemon-reload
systemctl enable --now open-webui.service ia-lab.target

# nginx
cp deploy/nginx/sites-available/ia-lab.conf /etc/nginx/sites-available/ia-lab.conf
ln -sf /etc/nginx/sites-available/ia-lab.conf /etc/nginx/sites-enabled/ia-lab.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx

# Self-signed cert for first run
HOSTNAME_FQDN=$(hostname -f 2>/dev/null || hostname)
CERT_DIR="/etc/nginx/ssl/ia-lab"
mkdir -p "${CERT_DIR}"
if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=${HOSTNAME_FQDN}" \
    -keyout "${CERT_DIR}/privkey.pem" \
    -out    "${CERT_DIR}/fullchain.pem" >/dev/null
  chmod 600 "${CERT_DIR}/privkey.pem"
fi

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

Install log: ${INSTALL_LOG}
EOF