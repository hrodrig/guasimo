# guasimo

[![Version](https://img.shields.io/badge/version-0.2.2-blue)](https://github.com/hrodrig/guasimo/releases)
[![Release](https://img.shields.io/github/v/release/hrodrig/guasimo)](https://github.com/hrodrig/guasimo/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![CUDA](https://img.shields.io/badge/CUDA-RTX%203060-76B900?logo=nvidia&logoColor=white)](https://developer.nvidia.com/cuda-zone)
[![gghstats clones](https://gghstats.hermesrodriguez.com/api/v1/badge/hrodrig/guasimo?metric=clones)](https://gghstats.hermesrodriguez.com/hrodrig/guasimo)

**Repo:** [github.com/hrodrig/guasimo](https://github.com/hrodrig/guasimo) · **Releases:** [GitHub Releases](https://github.com/hrodrig/guasimo/releases) · **Spec:** [SPECIFICATIONS.md](SPECIFICATIONS.md) · **Docs:** [docs/00-index.md](docs/00-index.md) · **Changelog:** [CHANGELOG.md](CHANGELOG.md)

![Open WebUI on the guasimo LAN workstation, Ornith-9b selected as the default model](docs/assets/open-webui-lan-192-168-10-69.png)

**G**raphical **U**tility for **A**I **S**erver **I**nference of **M**odels, **O**pen-source.

A self-hosted local LLM coding workstation. One command takes a fresh Ubuntu 26.04 box to a browser chat UI and an OpenAI-compatible API for your IDE. Models stay on the machine — nothing leaves the box.

**Related tools (same maintainer):**
- **[pgwd](https://github.com/hrodrig/pgwd)** — PostgreSQL connection watchdog ([live traffic](https://gghstats.hermesrodriguez.com/hrodrig/pgwd); deploy: [pgwd-selfhosted](https://github.com/hrodrig/pgwd-selfhosted))
- **[gghstats](https://github.com/hrodrig/gghstats)** — GitHub repo traffic beyond 14 days ([live demo](https://gghstats.hermesrodriguez.com); deploy: [gghstats-selfhosted](https://github.com/hrodrig/gghstats-selfhosted))
- **[kzero](https://github.com/hrodrig/kzero)** — bastion-first declarative workload reset ([live traffic](https://gghstats.hermesrodriguez.com/hrodrig/kzero); deploy: [kzero-selfhosted](https://github.com/hrodrig/kzero-selfhosted))
- **[groot](https://github.com/hrodrig/groot)** — Kubernetes diagnostics archive ([live traffic](https://gghstats.hermesrodriguez.com/hrodrig/groot); deploy: [groot-selfhosted](https://github.com/hrodrig/groot-selfhosted))

## Table of contents

- [Why guasimo](#why-guasimo)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Stack](#stack)
- [Hardware target](#hardware-target)
- [Status](#status)
- [Documentation](#documentation)
- [Repository layout](#repository-layout)
- [Contributing](#contributing)
- [License](#license)

## Why guasimo

- **Local by default** — inference and model blobs stay on your hardware; no cloud round-trip for code.
- **One install path** — `deploy/install.sh` detects GPU, builds llama.cpp, and wires systemd + nginx TLS.
- **IDE-ready API** — Ollama exposes an OpenAI-compatible HTTP surface for Cursor, Continue, and friends.
- **Built for coding** — primary focus is generation, review, explanation, and translation across Go, C#, and DevOps tooling.

![Ornith-9b answering a Go prompt on the LAN workstation — hybrid attention holds ~38 tok/s flat from 8K to 64K context](docs/assets/prompt-go-ornith-9b.png)

## Features

- Dual inference path: NVIDIA CUDA when `nvidia-smi` is ready; CPU fallback always available
- Deferred CUDA build after a fresh driver install (re-run `install.sh` post-reboot)
- systemd units for the stack; nginx terminates TLS on `:443` (self-signed by default)
- `healthcheck.sh`, `pull-models.sh`, and `benchmark.sh` for day-one validation
- `install-aliases.sh` keeps the Modefile recipes in `config/ollama/` in sync
  with the running Ollama (auto-runs at the end of `pull-models.sh`)
- Default primary is Ornith-1.5-9B (`ornith-9b`, Q6_K): hybrid-attention 9B,
  flat throughput across 8K→64K context (0 % cliff), full VRAM on the
  RTX 3060 (12 GB). A manual GGUF drop — see `docs/04-models.md` for the
  speed/quality trade-off and the "how to add a model" flow.
- Optional model nicknames: `secondary` (Qwen3.8-27B, 256K agentic depth),
  `thinking` (Qwen3.8-27B with reasoning on), `gemma`, `deepseek`
- Docs-first contract: `SPECIFICATIONS.md` + `docs/` stay authoritative

## Prerequisites

- **OS:** Ubuntu 26.04 (validated target)
- **GPU:** NVIDIA with working driver preferred (reference box: RTX 3060 12 GB). CPU-only still works, slower.
- **Disk:** room for GGUF blobs (primary pull is on the order of ~10 GB)
- **Pre-flight:** if `nvidia-smi` is missing, add the NVIDIA CUDA apt repo first — see [docs/05-deployment.md](docs/05-deployment.md)

## Quick start

On the Ubuntu target machine:

```bash
git clone https://github.com/hrodrig/guasimo.git ~/guasimo
cd ~/guasimo
sudo ./deploy/install.sh              # detects GPU, builds llama.cpp, wires systemd
./scripts/healthcheck.sh
./scripts/pull-models.sh primary      # ornith-9b (Q6_K; manual GGUF drop — see docs/04-models.md)
./scripts/benchmark.sh primary        # validates tokens/s on this box
```

`ornith-9b` is a manual GGUF drop, not an Ollama library tag: place
`Ornith-1.5-9B-Q6_K.gguf` in `/bulk/models/`, then
`./scripts/install-aliases.sh` creates the `ornith-9b` alias from
`config/ollama/Modelfile.ornith-9b`. `pull-models.sh primary` skips the
`ollama pull` for it and prints the drop reminder.

Open `https://localhost/` (self-signed cert — accept in the browser).  
Open WebUI listens on loopback `:8080`; nginx terminates TLS on `:443`.

## Stack

| Layer | Role |
|-------|------|
| **llama.cpp** | Inference engine (server mode), compiled on the box |
| **Ollama** | Model lifecycle + OpenAI-compatible HTTP API |
| **Open WebUI** | Chat UI (systemd), fronted by nginx + TLS |

A model is a named recipe + a GGUF blob. Ollama owns the recipe; llama.cpp does the maths; Open WebUI does the chat. Each layer can be swapped without breaking the others.

## Hardware target

Validated on a **real reference workstation** (not a cloud VM):

![guasimo reference workstation — Intel Core i5 + EVGA RTX, NZXT AIO](docs/assets/guasimo-workstation-tower.png)

| Component | Spec | Role |
|-----------|------|------|
| CPU | Intel i5-10xxx (Comet Lake-S) | Fallback inference; CPU build of llama.cpp |
| GPU | NVIDIA RTX 3060 (12 GB VRAM) | Primary inference; CUDA build of llama.cpp |
| RAM | 32 GB DDR4 | KV cache, OS, IDE, browser |
| Storage | 2 TB SSD + 500 GB NVMe | Cold GGUF store + hot runtime/models/logs |
| OS | Ubuntu 26.04 | LTS kernel, modern CUDA 12.x packages |

Details and trade-offs: [docs/02-hardware-decisions.md](docs/02-hardware-decisions.md).

## Status

**v0.4.0** (in progress) — Ornith 1.5 generation. New default primary
`ornith-9b` (Ornith-1.5-9B Q6_K, hybrid attention, ~7.4 GB), replacing
`qwen3.8:27b` as the daily driver. Ornith's hybrid attention keeps the
KV cache small, so the 9B runs ~38 gen tok/s flat across 8K→64K (0 %
cliff) full-VRAM on the RTX 3060 — vs the v0.3.x 27B primary at ~4 t/s
@ 64K partial offload. `qwen3.8:27b` drops to `secondary` for agentic
depth (256K, vision-language). See `docs/04-models.md` for the measured
throughput table and the MoE `--cpu-moe` findings.

**v0.2.2** — install + primary pull + healthcheck (8/0) + benchmark
(~18 gen tok/s) + LAN chat UI validated on Ubuntu 26.04 + RTX 3060
(2026-07-31 / 2026-08-01). Hermes Agent docs; optional `gemma` /
`deepseek` pulls. History: [CHANGELOG.md](CHANGELOG.md). Roadmap:
[docs/09-roadmap.md](docs/09-roadmap.md).

## Documentation

| Doc | Purpose |
|-----|---------|
| [SPECIFICATIONS.md](SPECIFICATIONS.md) | Scope and contract for v1 |
| [docs/00-index.md](docs/00-index.md) | Docs map and reading order |
| [docs/05-deployment.md](docs/05-deployment.md) | What `install.sh` does, CUDA pre-flight |
| [docs/08-troubleshooting.md](docs/08-troubleshooting.md) | Common failures |
| [docs/09-roadmap.md](docs/09-roadmap.md) | Near-term plans |
| [CHANGELOG.md](CHANGELOG.md) | Per-version release notes |

## Repository layout

```
docs/                   Technical documentation (English)
deploy/                 Systemd units, nginx vhosts, install/uninstall scripts
config/                 Ollama Modelfiles and llama.cpp server config
scripts/                Operations: benchmark, healthcheck, log rotation, etc.
tests/                  End-to-end smoke + per-language prompt suites
SPECIFICATIONS.md       Scope and contract for v1
CHANGELOG.md            Per-version release notes
```

## Contributing

Issues and PRs welcome. Keep project docs in **English**. Operational changes should stay consistent with `SPECIFICATIONS.md` and `docs/`.

## License

[MIT](./LICENSE)
