# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

Versions are tagged on the `main` branch only. The `develop` branch
accumulates unreleased work; the `Unreleased` section below tracks it.

## [Unreleased]

### Added
- `DEFAULT_MODELS` in `deploy/systemd/open-webui.service` — the Open
  WebUI chat model picker is now pre-selected, closing the "wire model
  picker into the per-conversation default" v0.4 gap. Settled on
  `coder-14b` (see Changed below): the fast secondary alias is the
  right default for day-to-day coding, while the primary `qwen3-27b`
  stays one explicit selection away for deep/long-context work.
  Activated on re-run of `deploy/install.sh`; the aliases are created
  by `install-aliases.sh` after `pull-models.sh`.

### Changed
- `DEFAULT_MODELS` switched `qwen3-27b` → `coder-14b` after measuring
  throughput on the reference box: `coder-14b` runs 33 gen t/s @ 8K ctx
  (full VRAM) vs `qwen3-27b` at 4 t/s @ 64K. The KV cache is the
  differentiator, not the model size — `coder-14b` collapses to 7 t/s
  at 64K ctx. Added a measured-throughput table to `docs/04-models.md`.
- `docs/04-models.md`, `docs/08-troubleshooting.md`,
  `docs/02-hardware-decisions.md`, `config/ollama/Modelfile.qwen3-27b`:
  corrected the primary's steady-state generation rate to **~4 gen
  tok/s @ 64K `num_ctx`** (prompt eval ~35 tok/s), as measured on the
  reference box 2026-08-23. The earlier "~5 t/s @ 64K" / "3-5 tok/s"
  figures were optimistic; the re-measured 64K number is what Hermes
  Agent's 64K context floor actually sees.

### Fixed
- Reference box validation closed (2026-08-23): `pull-models.sh
  primary` completed, `qwen3-27b` alias answers in Open WebUI,
  `benchmark.sh primary` reports 4 gen tok/s @ 64K, `healthcheck.sh`
  8/0. Only the manual screenshots
  (`docs/assets/ollama-pull-qwen38-27b-ok.png` and the refreshed
  `open-webui-lan-192-168-10-69.png`) remain as a follow-up.

### Removed
- (none yet)

## [0.3.1] - 2026-08-23

Hotfix: `qwen3.8:27b` requires Ollama v0.32.12 or newer (the model
landed the same day the 0.32.x line shipped, 2026-08-14). Fresh
installs from v0.3.0 hit HTTP 412 on the first pull because the
v0.2.x-era `OLLAMA_VERSION=0.5.7` pin was too old.

### Fixed
- `deploy/install.sh`: bumped `OLLAMA_VERSION` from `0.5.7` to
  `0.32.14`. The install now requires Ollama 0.32.12+ from apt
  (or the upstream install script as a fallback). Comment block
  explains why the line is 0.32.14 and not the 0.32.12 minimum.
- `config/ollama/Modelfile.*` (all five: `coder-14b`, `coder-7b`,
  `coder-32b`, `qwen3-27b`, `qwen3-27b-thinking`): removed
  `PARAMETER keep_alive 10m` / `5m`. Ollama 0.32.x dropped
  `keep_alive` from the supported Modelfile PARAMETER list, so
  `ollama create -f …` now rejects the recipe with
  `Error: unknown parameter 'keep_alive'`. The retention timeout
  is now a server-side setting: `OLLAMA_KEEP_ALIVE=10m` in
  `/etc/systemd/system/ollama.service.d/override.conf` (set by
  `deploy/install.sh`). Per-request override is still available via
  the API's `keep_alive` field. The Modelfiles carry a comment
  block in place of the removed line so the rationale is grep-able.
- `docs/08-troubleshooting.md`: new section "Symptom: `Error:
  unknown parameter 'keep_alive'`" with the fix; the existing
  "Symptom: pull model manifest: 412" entry was corrected to point
  at the new `.tar.zst` install path (Ollama no longer publishes a
  `.deb`).

### Upgrade path for existing boxes (not in the install script)

The upstream install script is the supported upgrade path (Ollama
publishes a `.tar.zst` of the binary, not a `.deb`):

    ollama --version
    sudo systemctl stop ollama
    sudo rm -rf /usr/lib/ollama               # cleanup recommended by Ollama docs
    curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION=0.32.14 sh
    sudo systemctl start ollama
    ollama --version    # should be 0.32.14 (or newer)
    ./scripts/pull-models.sh primary
    ./scripts/benchmark.sh primary

After the upgrade, re-run the guasimo install so the override.conf
gets the new `OLLAMA_KEEP_ALIVE` line, then re-create the Modelfile
aliases (which will now succeed because the recipes no longer carry
the rejected `PARAMETER keep_alive`):

    sudo ./deploy/install.sh                  # idempotent, updates override.conf
    ./scripts/install-aliases.sh             # creates coder-14b, qwen3-27b, …

The install script preserves
`/etc/systemd/system/ollama.service.d/override.conf` (guasimo's drop-in
for `OLLAMA_LLAMA_SERVER`, `OLLAMA_HOST`, `OLLAMA_MODELS`, `OLLAMA_DEBUG`,
`OLLAMA_KEEP_ALIVE`). Models in `/data/models` are not affected by
the binary upgrade; the Modelfile alias `qwen3-27b` is created
automatically by `scripts/install-aliases.sh`.
## [0.3.0] - 2026-08-23

Qwen 3.8 generation. New default primary
`qwen3.8:27b` (Qwen3.8-27B-Instruct, Apache 2.0, dense 27B,
vision-language, 256K context, thinking on by default). Partial
offload on the RTX 3060 (12 GB VRAM); see `docs/04-models.md` and
`docs/08-troubleshooting.md` for the speed/quality trade-off vs the
v0.2.x 14B primary that ran at ~18 gen tok/s full-VRAM. The
`scripts/install-aliases.sh` script closes the v0.2.x gap where the
checked-in Modelfile recipes were never auto-applied to the running
Ollama.

### Added
- `config/ollama/Modelfile.qwen3-27b` — default primary recipe
  (`qwen3-27b` alias), inherits the shared `PROMPT.coding.md` system
  prompt, conservative sampling, `num_ctx 65536` (64K), `keep_alive 10m`.
- `config/ollama/Modelfile.qwen3-27b-thinking` — same Qwen3.8-27B
  base, reasoning on, `qwen3-27b-thinking` alias.
- `scripts/install-aliases.sh` — scans `config/ollama/Modelfile.*`,
  matches each FROM against the local Ollama library, and runs
  `ollama create` for every match. Idempotent. Auto-invoked at the
  end of `pull-models.sh`; callable standalone with an optional
  substring filter on the FROM tag.
- "Thinking on by default" documented in `docs/04-models.md`,
  `docs/08-troubleshooting.md` (low-tok/s section), and
  `docs/06-networking-and-security.md` (Hermes section).

### Changed
- `scripts/pull-models.sh` — `primary` now resolves to
  `qwen3.8:27b` (~18 GB). `large` slot replaced by `thinking`
  (same base, alias-only, no extra pull weight). Disk-budget
  estimation updated for the new footprint and the legacy Qwen
  2.5-Coder sizes.
- `scripts/benchmark.sh` — manifest updated to match the new
  primary / thinking / secondary / gemma / deepseek layout.
- `SPECIFICATIONS.md` — "Model contract" rewritten for the Qwen 3.8
  generation; "Status" section now leads with the v0.3.0 work.
- `docs/04-models.md` — primary rewrite (Qwen3.8-27B), explicit
  partial-offload trade-off section, "Why Qwen 3.8" decision matrix,
  Modelfile list, sampling defaults note.
- `docs/02-hardware-decisions.md` — VRAM math and RAM budget
  updated for the 27B partial-offload case.
- `docs/01-architecture.md` — Open WebUI row now lists multimodal
  input; data flow note covers the image-content path.
- `docs/03-stack-choice.md` — new "Model choice (v0.3.0+)" section
  with the short version of the model decision.
- `docs/05-deployment.md` — install output updated to the
  v0.3.0 quick-start; partial offload is the expected steady state.
- `docs/06-networking-and-security.md` — Hermes Agent config
  example updated to `qwen3-27b`; multimodal note added; speed
  warning reflects the slower 27B partial offload.
- `docs/07-operations.md` — daily ops table now lists
  `install-aliases.sh`, the secondary alias swap path, and the
  low-tok/s symptom.
- `docs/08-troubleshooting.md` — new "Symptom: low tokens/s with
  qwen3.8:27b on the RTX 3060 (12 GB)" with the full tuning
  checklist (load confirmation, `num_ctx` lowering, disk /
  thermal / OOM checks, fallback to secondary).
- `docs/09-roadmap.md` — v0.3 and v0.4 marked Done; new v0.3.0
  section; v1.0 still pending (CI + doc audit).
- `tests/prompts/{go,csharp,devops}/README.md` — each suite now
  records the v0.3.0 target model and the variant choice guidance.
- `README.md` — Status, Features, and Quick Start updated to the
  v0.3.0 flow; the `pull-models.sh primary` step now notes that
  the alias is auto-created.

### Fixed
- `scripts/install-aliases.sh` closes the v0.2.x gap where the
  recipes in `config/ollama/Modelfile.*` were checked in but never
  applied to the running Ollama. Operators who used `pull-models.sh`
  in v0.2.x had to remember to run `ollama create -f …` by hand to
  pick up the system prompt and sampling defaults; from v0.3.0 the
  alias is created automatically.

### Removed
- `scripts/pull-models.sh` no longer pulls the v0.2.x primary
  (`qwen2.5-coder:14b-instruct-q4_K_M`) by default. Operators who
  want to experiment with the 14B can `ollama pull` it directly;
  the `Modelfile.coder-14b` recipe is kept in the repo for reference
  but no longer referenced by the install scripts.
- The `large` nickname (Qwen2.5-Coder-32B) is no longer in the
  `pull-models.sh` / `benchmark.sh` manifest. The recipe
  `config/ollama/Modelfile.coder-32b` stays in the repo for
  reference; pull the GGUF directly if you want to try it.

### Known limitations
- The v0.3.0 primary runs in **partial offload** on the RTX 3060
  (12 GB VRAM) and benchmarks at **~3-5 gen tok/s**, down from the
  ~18 gen tok/s the v0.2.x 14B primary hit when it fit fully in
  VRAM. This is the documented cost of gaining agentic coding,
  multimodal input, and 256K context on the same single-user box.
- Validation on the reference box (Ubuntu 26.04 + RTX 3060) is
  pending a fresh `pull-models.sh primary` run; the
  `docs/assets/ollama-pull-qwen38-27b-ok.png` and refreshed
  `docs/assets/open-webui-lan-192-168-10-69.png` screenshots are
  not in this tag. Capture on the next install and backport.
- Open WebUI's per-conversation model picker is not yet wired to
  default to `qwen3-27b`; operators pick the model in the UI for
  now. (Carried over from v0.4.)

## [0.2.2] - 2026-08-01

Hermes Agent client docs + optional Gemma / DeepSeek pulls.

### Added
- Docs: Hermes Agent + LAN clients — SSH tunnel to
  `http://127.0.0.1:11434/v1`; 64K via `ollama_num_ctx` /
  `context_length`; disable thinking with `agent.reasoning_effort: none`
  for Qwen2.5-Coder (HTTP 400 *does not support thinking*). See
  `docs/06-networking-and-security.md`, `docs/08-troubleshooting.md`.
- Optional model nicknames: `gemma` → `gemma4:12b`, `deepseek` →
  `deepseek-coder-v2:lite` in `scripts/pull-models.sh` /
  `scripts/benchmark.sh` (documented in `docs/04-models.md`).

### Changed
- `scripts/pull-models.sh`: chown model dirs to `ollama` (not `guasimo`)
  so pulls do not re-break daemon writes.
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

[Unreleased]: https://github.com/hrodrig/guasimo/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/hrodrig/guasimo/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/hrodrig/guasimo/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/hrodrig/guasimo/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/hrodrig/guasimo/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/hrodrig/guasimo/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/hrodrig/guasimo/releases/tag/v0.1.0
