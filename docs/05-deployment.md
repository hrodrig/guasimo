# 05 — Deployment

This document is the contract that `deploy/install.sh` honours. Anything the
script does must be explained here; anything explained here must be reflected
in the script.

## Top-level goal

Make a freshly-installed Ubuntu 26.04 machine into a working LLM workstation
by running **one command**, and make the result **idempotent on re-run**.

## The one command

    sudo ./deploy/install.sh

It must:

- Run as root (or via `sudo`) because it touches `/etc`, `/opt`, and creates
  system users.
- Be re-runnable. Second run must be a no-op for already-installed parts
  and an update for changed parts.
- Emit a final summary that includes the resolved build flags, the resolved
  model list, and the URLs the user should open.

## Phases

The script has five phases, in this order. Each phase logs a banner so the
operator can see progress.

### Phase 1 — Probe

Detects:

- Distribution (must be Ubuntu ≥ 24.04; refuses otherwise with a clear
  error).
- CPU features (`/proc/cpuinfo` flags).
- GPU presence (`nvidia-smi`, `lspci`).
- Disk layout (whether NVMe vs SSD vs both are mounted).
- Whether re-running on an already-installed box.

Exits non-zero on Ubuntu version mismatch.

### Phase 2 — Packages

Installs via `apt`:

- build-essential, cmake, git, curl, jq, python3-pip, nginx, sqlite3,
  uuid-runtime, ca-certificates, libssl-dev.
- `nvidia-driver-<ver>` and `nvidia-cuda-toolkit-<ver>` only if NVIDIA GPU
  detected. The version number is **not** pinned; the script queries
  `apt-cache` for the latest `nvidia-driver-*` available in the current
  Ubuntu release. If none is found, the script warns and continues on
  CPU.
- `linux-tools-$(uname -r)` and `powertop` for benchmarking.

Uses `apt-mark hold` only when we have a known-good pinned version.

### Phase 3 — llama.cpp

- Clones https://github.com/ggerganov/llama.cpp into `/opt/guasimo/llama.cpp/`
  at the SHA pinned in `deploy/install.sh`.
- Configures with the flag matrix from `docs/02-hardware-decisions.md`.
- Builds with `cmake --build build --parallel`.
- Strips the binary.
- Symlinks `/opt/guasimo/llama-server` and `/opt/guasimo/llama-cli`.
- Skips clone if the directory exists and matches the pinned SHA.

### Phase 4 — Ollama

- Installs Ollama (Ubuntu `.deb` if recent enough; upstream script otherwise).
- Overrides `OLLAMA_LLAMA_SERVER` to our locally-built binary.
- Writes `/etc/systemd/system/ollama.service.d/override.conf`.
- Symlinks model store from `/data/models` if present, else `/root/.ollama`.
- Reloads systemd.

### Phase 5 — Open WebUI + nginx

- Creates a Python 3.12 venv at `/opt/guasimo/webui-venv` (Open WebUI
  requires `>=3.11,<3.13`). Ubuntu 26.04 has no `python3.12` apt package,
  so the script bootstraps `uv` under `/opt/guasimo/uv` and installs
  CPython 3.12 into `/opt/guasimo/python` when needed.
- `pip install` CPU-only `torch`, then `open-webui==0.6.43` (pin in
  `deploy/install.sh`). CPU torch avoids pip pulling a second CUDA
  stack; inference stays on host Ollama/llama.cpp.
- Drops the systemd unit from `deploy/systemd/open-webui.service`.
- Generates a self-signed TLS cert under `/etc/nginx/ssl/guasimo/`
  **before** `nginx -t` (the vhost references those paths; testing
  without them fails). Real Let's Encrypt is an operator decision; see
  `docs/06-networking-and-security.md`.
- Drops the nginx vhost from `deploy/nginx/sites-available/guasimo.conf`
  and symlinks it into `sites-enabled`, then `nginx -t` + enable.

## Idempotency

Re-running the script must:

- Skip package install if all `apt` packages are already present.
- Skip llama.cpp build if the binary already exists and the source SHA
  matches.
- Re-write systemd unit overrides (they're cheap and the diff is visible).
- Re-run `nginx -t` and `systemctl reload nginx` if the vhost changed.

It must NOT:

- Re-pull models (that's `scripts/pull-models.sh`).
- Restart running services unnecessarily (`systemctl try-reload-or-restart`
  is fine; restart-on-no-change is not).

## What the script refuses to do

- Run as non-root without `sudo`.
- Touch `/var/lib/docker` or any container runtime. v1 is host-native.
- Pull models automatically. The operator chooses which models to download.
- Open ports on the firewall. That is `scripts/open-firewall.sh`, run
  separately, so the operator stays in control of network exposure.

## Pre-flight on a fresh Ubuntu 26.04 machine

On Ubuntu 24.04 the NVIDIA driver ships in the main archive and
`apt-cache search '^nvidia-driver-[0-9]+$'` returns the latest version
directly. On Ubuntu 26.04 (`resolute`) the driver is **not** in the main
archive — it ships from the NVIDIA CUDA repo at
`https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64`.

If the install runs on a fresh box where that repo is not yet configured,
the driver detection in `install.sh` returns nothing and the script logs
`no nvidia-driver-* package found in apt`. The operator must add the
repo manually before re-running:

    distribution=$(. /etc/os-release; echo "${ID}${VERSION_ID//./}")
    architecture=$(dpkg --print-architecture)
    curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/${distribution}/${architecture}/cuda-keyring_1.1-1_all.deb" \
      -o /tmp/cuda-keyring.deb
    dpkg -i /tmp/cuda-keyring.deb
    apt-get update

After that, `install.sh` detects the driver and continues normally.

**Do not mix driver sources.** The Ubuntu archive and the NVIDIA CUDA
repo ship overlapping NVIDIA files under different package names
(unversioned `nvidia-firmware` / `libnvidia-cfg1` vs versioned
`nvidia-firmware-610-*` / `libnvidia-cfg1-610`). Installing both leaves
apt stuck on `trying to overwrite` / unmet Depends. Prefer the CUDA
repo on 26.04. If the box is already wedged, see
`docs/08-troubleshooting.md` (`trying to overwrite` between
`nvidia-firmware` and `nvidia-firmware-610`).

## Output of a successful install

Shape (real run on Ubuntu 26.04 + RTX 3060, v0.3.0):

```
[phase 1/5] probe ............... NVIDIA hardware=y runtime=y
[phase 2/5] packages ............ nvidia-driver-610 + toolkit already present
[phase 3/5] llama.cpp ........... already built at b4568 (…); cuda build: y
[phase 4/5] ollama .............. already installed
[phase 5/5] open-webui + nginx .. uv → CPython 3.12 → open-webui; TLS; nginx -t ok

URLs:
  chat   https://<hostname>/      (accept self-signed cert)
  API    http://127.0.0.1:11434/v1/chat/completions

Next steps:
  ./scripts/healthcheck.sh
  ./scripts/pull-models.sh primary      # qwen3.8:27b (~18 GB, partial offload on 3060)
  ./scripts/pull-models.sh thinking     # same base, alias with reasoning on
  ./scripts/benchmark.sh   primary
```

Chat URL is **HTTPS on nginx :443**, not bare `:8080` (Open WebUI binds
loopback only). The exact hostname comes from `hostname -f`.

The v0.3.0 primary (`qwen3.8:27b`, ~18 GB) does not fit in the RTX 3060's
12 GB VRAM; Ollama will keep the layers that fit and offload the rest
to CPU/RAM. Expect ~3-5 gen tok/s in steady state vs the ~18 tok/s
the v0.2.x 14B primary achieved when it fit fully in VRAM. This is
the documented cost of gaining agentic coding, multimodal input, and
256K context on the same single-user box. The pull step is also
heavier (~18 GB vs ~9 GB); `scripts/pull-models.sh` checks free disk
before it starts. See `docs/04-models.md` for the full tradeoff and
`docs/08-troubleshooting.md` for tuning tips.

## Rollback

`deploy/uninstall.sh` removes every artefact created by `install.sh`. It
**keeps** downloaded model blobs in `/data/models` and `/bulk/models` so a
re-install does not re-download.