# ia-lab-home

Local LLM coding workstation. Self-hosted inference stack for programming assistance
across Go, C#, DevOps, and general software engineering.

**Authoritative documentation lives in `docs/` — read `docs/00-index.md` first.**

## Repository layout

    docs/                   Technical documentation (English)
    deploy/                 Systemd units, nginx vhosts, install/uninstall scripts
    config/                 Ollama Modelfiles and llama.cpp server config
    models/                 Manifests / download recipes (no GGUF blobs committed)
    scripts/                Operations: benchmark, healthcheck, log rotation, etc.
    tests/prompts/          Per-language prompt suites for evaluation

## Hardware target

| Component | Spec                          | Role                                              |
|-----------|-------------------------------|---------------------------------------------------|
| CPU       | Intel i5-10xxx (Comet Lake-S) | Fallback inference; CPU build of llama.cpp        |
| GPU       | NVIDIA RTX 3060 (12 GB VRAM)  | Primary inference; CUDA build of llama.cpp        |
| RAM       | 32 GB DDR4                    | KV cache fallback, OS, IDE, browser               |
| SSD       | 2 TB SATA/NVMe                | Cold storage for downloaded model blobs           |
| NVMe      | 500 GB                        | Hot storage: runtime, models in use, logs         |
| OS        | Ubuntu 26.04                  | LTS kernel, modern CUDA 12.x packages              |

NVIDIA GPU is the primary inference target. `deploy/install.sh` detects it
in two phases (`lspci` for hardware, `nvidia-smi` for runtime) and selects
build flags accordingly. If the driver is freshly installed, the script
defers the CUDA build until after the first reboot — the user re-runs
`install.sh` post-reboot to finish the build. CPU remains a working
fallback path at all times.

## Stack

- **llama.cpp** — inference engine (server mode), compiled locally for the exact CPU
- **Ollama** — model lifecycle manager + OpenAI-compatible HTTP API
- **Open WebUI** — chat front-end (systemd unit, served by nginx with TLS)

A model is a named recipe + a GGUF blob. Ollama handles the recipe; llama.cpp does
the maths; Open WebUI does the chat. Each layer can be swapped without breaking
the others.

## Quick start (Ubuntu target machine)

    git clone <this-repo> ~/ia-lab-home
    cd ~/ia-lab-home
    sudo ./deploy/install.sh          # detects GPU, builds llama.cpp, wires systemd
    ./scripts/pull-models.sh primary  # ~10 GB primary code model
    ./scripts/benchmark.sh primary    # validates tokens/s on this box

Open `http://localhost:8080` (or `https://<lan-ip>` after TLS).

## Status

v0.1 — initial scaffolding. See `docs/01-architecture.md` for the design contract and
`docs/09-roadmap.md` for what is planned next.