# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

Versions are tagged on the `main` branch only. The `develop` branch
accumulates unreleased work; the `Unreleased` section below tracks it.

## [Unreleased]

### Added
- Docs: Hermes Agent + LAN clients — SSH tunnel to
  `http://127.0.0.1:11434/v1`, and how to clear Hermes’ **64K context**
  floor without changing model (`OLLAMA_CONTEXT_LENGTH=64000` +
  `model.context_length` in `~/.hermes/config.yaml`). See
  `docs/06-networking-and-security.md`, `docs/08-troubleshooting.md`.

### Changed
- (none yet)

### Fixed
- (none yet)

### Removed
- (none yet)

## [0.2.1] - 2026-08-01

v0.2 exit criterion closed on the reference box. Fix post-reboot Ollama
crash-loop when model dir ownership was wrong.

### Added
- `docs/assets/ollama-pull-qwen25-coder-14b-ok.png`: evidence that
  `./scripts/pull-models.sh primary` completed on the Ubuntu 26.04 +
  RTX 3060 box (linked from `docs/04-models.md`, `docs/09-roadmap.md`).
- `docs/assets/open-webui-lan-192-168-10-69.png`: LAN browser chat UI
  at `https://192.168.10.69/` with primary model selected.

### Changed
- `docs/09-roadmap.md` / `SPECIFICATIONS.md` / `docs/04-models.md` /
  `docs/06-networking-and-security.md`: v0.2 exit criterion met —
  primary pull, healthcheck 8/0, ~18 gen tok/s, LAN UI (2026-08-01).

### Fixed
- `deploy/install.sh`: chown `/data/models` to the Ollama service user
  (`ollama`), not `guasimo`. Prevents crash-loop
  `mkdir /data/models/blobs: permission denied` after reboot / power loss.

## [0.2.0] - 2026-07-31

Minimum viable install path, validated on real Ubuntu 26.04 + RTX 3060
hardware. `sudo ./deploy/install.sh` reaches a running stack (CUDA
llama.cpp, Ollama, Open WebUI, nginx TLS). Operator still runs
`pull-models.sh` / `benchmark.sh` after install.

### Added
- `docs/05-deployment.md`: pre-flight for the NVIDIA CUDA apt repo on
  Ubuntu 26.04 (driver not in the main archive).
- `docs/08-troubleshooting.md`: mixed NVIDIA packaging collision
  (`nvidia-firmware` vs `nvidia-firmware-610-*`), GCC 15 /
  `uint32_t`, Open WebUI Python 3.12 via uv, CPU-only torch, TLS-before-
  `nginx -t`, and related recovery paths — with real console excerpts.
- `docs/05-deployment.md`: warning not to mix Ubuntu-archive and
  CUDA-repo NVIDIA packages on the same box.

### Changed
- Runtime paths and service identity renamed from `ia-lab` to `guasimo`:
  `/opt/guasimo`, user `guasimo`, `/var/log/guasimo`, systemd
  `guasimo.target`, nginx `guasimo.conf`, health `GET /guasimo-health`.
  `uninstall.sh` also removes leftover `/opt/ia-lab` artefacts.
- Open WebUI pin `0.3.21` → `0.6.43`. Venv uses Python 3.12 (Ubuntu
  26.04 has no `python3.12` apt package) via [uv](https://github.com/astral-sh/uv)
  under `/opt/guasimo/uv` + CPython under `/opt/guasimo/python`.
- Before `pip install open-webui`, install **CPU-only** `torch` so pip
  does not fetch unused `nvidia-*-cu13` wheels (~1 GB+).
- `scripts/pull-models.sh`: writable pull log fallback
  (`~/.cache/guasimo/`); ollama CLI as invoking user.
- `scripts/healthcheck.sh`: non-root-friendly nginx check; accept WebUI
  HTTP 302.

### Fixed
- TLS cert generated **before** `nginx -t` on first install.
- Git `safe.directory` for `/opt/guasimo/llama.cpp` under root; pin
  compare via resolved commit SHA (tag `b4568` ≠ short SHA).
- llama.cpp `b4568` patched for GCC 15 (`#include <cstdint>` in
  `llama-mmap.h`; upstream #11796).
- NVIDIA driver package detected from `apt-cache` (no hard-coded 555).
- `recover_dpkg()` + non-fatal NVIDIA driver install; purge unversioned
  NVIDIA leftovers that collide with versioned CUDA-repo packages.

### Known limitations
- Let's Encrypt and firewall open remain manual / separate scripts.

## [0.1.0] - 2026-07-30

Initial scaffolding. A new operator can read `SPECIFICATIONS.md` and
`docs/` and understand the system without running anything.

### Added
- **Stack**: llama.cpp (CUDA build with SM 86 pinning for RTX 3060) +
  Ollama + Open WebUI behind nginx. llama.cpp is built locally so the
  binary matches the host CPU; Ollama is pointed at the local build via
  `OLLAMA_LLAMA_SERVER`.
- **Models**: Ollama Modelfiles for Qwen2.5-Coder at 14B (primary),
  7B (secondary), and 32B (optional, partial offload). Shared system
  prompt at `config/ollama/PROMPT.coding.md`.
- **Deployment**: `deploy/install.sh` (idempotent, dual-phase GPU
  detection so the script handles the "reboot after driver install"
  case), `deploy/uninstall.sh`, systemd units, nginx vhost with
  self-signed TLS.
- **Operations**: `scripts/pull-models.sh`, `scripts/benchmark.sh`,
  `scripts/healthcheck.sh`, `scripts/rotate-logs.sh`,
  `scripts/open-firewall.sh`, `scripts/backup-webui-db.sh`.
- **Tests**: `tests/smoke.sh` (end-to-end) and per-language prompt
  suites for Go, C#, and DevOps (nginx, Helm, GitHub Actions) with
  explicit acceptance checklists.
- **Documentation**: nine docs under `docs/` covering architecture,
  hardware decisions, stack rationale, model selection, deployment,
  networking and security, operations, troubleshooting, and roadmap.
- **Whitelist-style `.gitignore`**: defaults to ignoring everything;
  only the project tree is re-allowed.

### Known limitations
- Driver install + CUDA build is a two-step flow (install, reboot,
  re-run `install.sh`). Documented in `docs/05-deployment.md`.
- No Let's Encrypt integration. Operator must swap the self-signed cert
  manually if exposing the box beyond the LAN.
- Model benchmarks are not part of CI; `tests/smoke.sh` validates only
  that the stack answers HTTP, not that responses are correct.

### Security
- All inference services bind to `127.0.0.1`. Only nginx listens on the
  LAN (`443/tcp`, `80/tcp` only as a 301 redirect).
- Open WebUI service runs as the unprivileged `guasimo` user with
  systemd hardening (`NoNewPrivileges`, `ProtectSystem=strict`,
  `PrivateTmp`, `ProtectHome`, etc.).
- Firewall is **not** opened automatically. `scripts/open-firewall.sh`
  is the explicit, audited path.

[Unreleased]: https://github.com/hrodrig/guasimo/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/hrodrig/guasimo/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/hrodrig/guasimo/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/hrodrig/guasimo/releases/tag/v0.1.0