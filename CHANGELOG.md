# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

Versions are tagged on the `main` branch only. The `develop` branch
accumulates unreleased work; the `Unreleased` section below tracks it.

## [Unreleased]

### Added
- `docs/05-deployment.md`: documented the pre-flight step for adding the
  NVIDIA CUDA repo on Ubuntu 26.04, where the driver does not ship in
  the main archive.
- `docs/08-troubleshooting.md`: documented the mixed NVIDIA packaging
  collision (`nvidia-firmware` vs `nvidia-firmware-610-*`) validated on
  Ubuntu 26.04 — root cause, symptoms, failed recovery paths
  (`apt-get remove` / bare `apt-get -f install`), and the working fix
  (`dpkg --purge --force-depends` then `apt-get -f install`).
- `docs/05-deployment.md`: warning not to mix Ubuntu-archive and CUDA-repo
  NVIDIA packages on the same box.

### Changed
- Runtime paths and service identity renamed from `ia-lab` to `guasimo`:
  `/opt/guasimo`, user `guasimo`, `/var/log/guasimo`, systemd
  `guasimo.target`, nginx `guasimo.conf`, health `GET /guasimo-health`.
  `uninstall.sh` also removes leftover `/opt/ia-lab` artefacts from
  pre-rebrand installs.
- Open WebUI pin `0.3.21` → `0.6.43`. The venv is created with
  `python3.12` (package installed if missing) because Ubuntu 26.04's
  default `python3` is 3.13+ and Open WebUI still requires
  `Requires-Python >=3.11,<3.13`.

### Fixed
- `deploy/install.sh`: mark `/opt/guasimo/llama.cpp` as a git
  `safe.directory` for root (global) so cmake's `build_info` target
  stops spamming "dubious ownership". Compare llama.cpp pin via
  resolved commit SHA (tag `b4568` ≠ short SHA `a4417dd`), so a
  finished CUDA build is not rebuilt on every re-run. Treat
  `build/bin/llama-server` as already-built, not only the install
  symlink.
- `deploy/install.sh`: after cloning llama.cpp `b4568`, patch
  `src/llama-mmap.h` to `#include <cstdint>` when missing. GCC 15 on
  Ubuntu 26.04 no longer provides `uint32_t` via transitive headers;
  without the patch the build dies with `‘uint32_t’ does not name a
  type` (upstream fix is ggml-org/llama.cpp#11796, post-`b4568`).
- `deploy/install.sh`: stopped pinning `nvidia-driver-555`. The package
  name is now detected from `apt-cache` (highest `nvidia-driver-*` for
  the current Ubuntu release), with a fallback to the `nvidia-driver`
  metapackage. Fixes the "Unable to locate package nvidia-driver-555"
  error on Ubuntu 26.04, where the version in the archive is different.
- `deploy/install.sh`: also re-queries `apt-cache` if the first attempt
  returns nothing but a `nvidia`/`cuda` sources.list file is present
  (covers the case where the NVIDIA CUDA repo is configured but the
  driver detection needs an extra nudge).
- `deploy/install.sh`: added `recover_dpkg()` and call it at the start of
  phase 2 before any `apt-get` operation. It covers two distinct failure
  modes that previously left the box stuck and every re-run failing the
  same way:
  (a) a half-configured dpkg database (interrupted unpack, power loss,
  Ctrl-C) — repaired with `dpkg --configure -a`, gated on `dpkg --audit`;
  (b) a broken apt dependency graph that `dpkg --audit` misses — e.g.
  `nvidia-driver-610` marked "installed" by dpkg but its deps
  (`nvidia-firmware-610`, `libnvidia-gl-610`, `libnvidia-cfg1-610`)
  unmet, so apt's resolver refuses with "Unmet dependencies" /
  "it is not going to be installed" — repaired with `apt-get -f install`,
  gated on `apt-get check`. Both are no-ops when the system is clean.
- `deploy/install.sh`: the NVIDIA driver install is no longer fatal.
  `set -e` previously killed the whole install when the driver unpack
  failed (e.g. `nvidia-firmware-610`, `libnvidia-cfg1-610`,
  `libnvidia-gl-610` failing to unpack), leaving the box with no
  `llama-server` built. The script now catches the failure, runs
  `recover_dpkg` to clean up, downgrades the box to CPU-only for that
  run, and proceeds to build a working CPU `llama.cpp`. The operator
  fixes the driver and re-runs to enable CUDA. This aligns the script
  with the `docs/05-deployment.md` contract ("warn and continue on CPU").
- `deploy/install.sh`: when `apt-get -f install` fails because unversioned
  Ubuntu NVIDIA packages (`nvidia-firmware`, `libnvidia-cfg1`,
  `libnvidia-egl-wayland21`, …) collide with versioned CUDA-repo
  siblings (`nvidia-firmware-610-*`, `libnvidia-cfg1-610`, …) that own
  the same files, purge the unversioned leftovers and retry. Also makes
  `recover_dpkg` non-fatal under `set -e` so a stuck apt graph cannot
  abort the whole install before the CPU fallback path runs.

### Removed
- (none yet)

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

[Unreleased]: https://github.com/hrodrig/guasimo/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/hrodrig/guasimo/releases/tag/v0.1.0