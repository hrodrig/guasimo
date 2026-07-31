# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

Versions are tagged on the `main` branch only. The `develop` branch
accumulates unreleased work; the `Unreleased` section below tracks it.

## [Unreleased]

### Added
- (none yet)

### Changed
- (none yet)

### Fixed
- `deploy/install.sh`: stopped pinning `nvidia-driver-555`. The package
  name is now detected from `apt-cache` (highest `nvidia-driver-*` for
  the current Ubuntu release), with a fallback to the `nvidia-driver`
  metapackage. Fixes the "Unable to locate package nvidia-driver-555"
  error on Ubuntu 26.04, where the version in the archive is different.

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
- Open WebUI service runs as the unprivileged `ia-lab` user with
  systemd hardening (`NoNewPrivileges`, `ProtectSystem=strict`,
  `PrivateTmp`, `ProtectHome`, etc.).
- Firewall is **not** opened automatically. `scripts/open-firewall.sh`
  is the explicit, audited path.

[Unreleased]: https://github.com/hrodrig/guasimo/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/hrodrig/guasimo/releases/tag/v0.1.0