# guasimo

**G**raphical **U**tility for **A**I **S**erver **I**nference of **M**odels,
**O**pen-source.

A self-hosted local LLM coding workstation. One command goes from a
fresh Ubuntu 26.04 install to a working chat UI in your browser and an
OpenAI-compatible API for your IDE.

Target use: code generation, review, explanation, and translation across
Go, C#, and DevOps tooling. Models are local; nothing leaves the box.

> **Authoritative documentation lives in `SPECIFICATIONS.md`, `docs/`, and
> `CHANGELOG.md`. Read those first.**

## Repository layout

    docs/                   Technical documentation (English)
    deploy/                 Systemd units, nginx vhosts, install/uninstall scripts
    config/                 Ollama Modelfiles and llama.cpp server config
    scripts/                Operations: benchmark, healthcheck, log rotation, etc.
    tests/                  End-to-end smoke + per-language prompt suites
    SPECIFICATIONS.md       Scope and contract for v1
    CHANGELOG.md            Per-version release notes

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

    git clone <this-repo> ~/guasimo
    cd ~/guasimo
    # Ubuntu 26.04: add the NVIDIA CUDA apt repo first if nvidia-smi
    # is missing — see docs/05-deployment.md (pre-flight).
    sudo ./deploy/install.sh          # detects GPU, builds llama.cpp, wires systemd
    ./scripts/healthcheck.sh
    ./scripts/pull-models.sh primary  # ~10 GB primary code model
    ./scripts/benchmark.sh primary    # validates tokens/s on this box

Open `https://localhost/` (self-signed cert — accept in the browser).
Open WebUI listens on loopback `:8080`; nginx terminates TLS on `:443`.

## Status

Install path validated on real Ubuntu 26.04 + RTX 3060 hardware
(2026-07-31): CUDA `llama.cpp`, Ollama, Open WebUI 0.6.x, nginx TLS.
Next operator step after install: pull models + benchmark. Design
contract in `docs/`; roadmap in `docs/09-roadmap.md`.
