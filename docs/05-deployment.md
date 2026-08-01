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

- Clones https://github.com/ggerganov/llama.cpp into `/opt/ia-lab/llama.cpp/`
  at the SHA pinned in `deploy/install.sh`.
- Configures with the flag matrix from `docs/02-hardware-decisions.md`.
- Builds with `cmake --build build --parallel`.
- Strips the binary.
- Symlinks `/opt/ia-lab/llama-server` and `/opt/ia-lab/llama-cli`.
- Skips clone if the directory exists and matches the pinned SHA.

### Phase 4 — Ollama

- Installs Ollama (Ubuntu `.deb` if recent enough; upstream script otherwise).
- Overrides `OLLAMA_LLAMA_SERVER` to our locally-built binary.
- Writes `/etc/systemd/system/ollama.service.d/override.conf`.
- Symlinks model store from `/data/models` if present, else `/root/.ollama`.
- Reloads systemd.

### Phase 5 — Open WebUI + nginx

- Creates Python venv at `/opt/ia-lab/webui-venv`.
- `pip install open-webui` pinned to `requirements.txt`.
- Drops the systemd unit from `deploy/systemd/open-webui.service`.
- Drops the nginx vhost from `deploy/nginx/sites-available/ia-lab.conf` and
  symlinks it into `sites-enabled`.
- Self-signed cert is generated for the LAN hostname in this phase (real
  Let's Encrypt cert is an operator decision; see `docs/06-...md`).

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

```
[phase 1/5] probe ............... ok (Ubuntu 26.04, i5-12400, no NVIDIA)
[phase 2/5] packages ............ ok (120 packages, 0 new)
[phase 3/5] llama.cpp ........... ok (built at sha abc123, AVX2, native)
[phase 4/5] ollama .............. ok (Ollama 0.5.x, using local llama.cpp)
[phase 5/5] webui + nginx ....... ok (Open WebUI 0.3.x, nginx 1.26)

URLs:
  chat   https://<hostname>.local/
  API    http://127.0.0.1:11434/v1/chat/completions

Next steps:
  ./scripts/pull-models.sh primary
  ./scripts/benchmark.sh primary
```

The exact hostname and IP detection is left to the script.

## Rollback

`deploy/uninstall.sh` removes every artefact created by `install.sh`. It
**keeps** downloaded model blobs in `/data/models` and `/bulk/models` so a
re-install does not re-download.