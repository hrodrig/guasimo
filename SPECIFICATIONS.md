# SPECIFICATIONS

**G**raphical **U**tility for **A**I **S**erver **I**nference of **M**odels,
**O**pen-source.

The authoritative short-form description of this project. Anything that
contradicts what is written here is a bug. Detailed design rationale lives
in `docs/`; operational procedures in `docs/07-operations.md`.

## What this is

A self-hosted coding Large Language Model workstation running on an
Ubuntu 26.04 box. The model is reachable from a browser on the same LAN
via a web chat UI, and from any IDE via an OpenAI-compatible HTTP API.

## Scope (v1)

In scope:

- A single local user on a trusted LAN.
- Code generation, review, explanation, and translation across Go, C#,
  DevOps tooling (Helm, nginx, GitHub Actions), and similar.
- File-upload RAG via Open WebUI's built-in capabilities.
- Pulling and swapping coding models without rebuilding the stack.
- Surviving reboots without operator intervention.

Out of scope:

- Multi-tenant authentication or remote access from outside the LAN.
- Model fine-tuning.
- A persistent vector database for codebase-wide RAG.
- Apple Silicon, AMD ROCm, or Intel Arc as the inference target.
- Containerised deployment (v1 is host-native systemd).
- Compliance, audit logging, or DLP.

## Hardware contract

The stack targets the following box. Other hardware may work but is not
covered by the install contract:

| Component | Required                              |
|-----------|---------------------------------------|
| CPU       | x86-64 with AVX2                      |
| RAM       | ≥ 32 GB                               |
| GPU       | NVIDIA RTX 3060 (12 GB) recommended, CUDA optional |
| Storage   | One fast disk (NVMe, ≥ 100 GB) + optional bulk disk |
| OS        | Ubuntu 26.04 LTS                      |

CPU-only operation is supported as a documented fallback at degraded
performance.

## Behaviour contract

- All inference services bind to 127.0.0.1. Only nginx listens on the LAN.
- TLS is terminated by nginx. Self-signed cert on first install; the
  operator is expected to swap to a real cert before exposing the box
  outside the LAN.
- The stack is reachable at `https://<hostname>/` after install; the
  OpenAI-compatible API is at `http://127.0.0.1:11434/v1/`.
- After a reboot, no operator action is needed for the stack to come
  back. `systemctl status ia-lab.target` should report `active`.

## Model contract

- Primary: `qwen2.5-coder:14b-instruct-q4_K_M` (Q4_K_M, ~9 GB).
- Secondary: `qwen2.5-coder:7b-instruct-q4_K_M` (~5 GB).
- Large (optional, partial offload):
  `qwen2.5-coder:32b-instruct-q4_K_M` (~20 GB).
- All three are pre-trained upstream. No fine-tuned variants ship with
  this project.

## Versions

Pinned at install time by `deploy/install.sh`:

| Component  | Source                              |
|------------|-------------------------------------|
| llama.cpp  | git, pinned to a specific SHA/tag   |
| Ollama     | Ubuntu `.deb` or upstream script    |
| Open WebUI | pip, pinned in `scripts/`           |
| nginx      | Ubuntu package                      |

Versions change by editing `deploy/install.sh` and re-running it.

## Operational contract

- `deploy/install.sh` is the one command that goes from a fresh Ubuntu
  install to a working stack. It is idempotent.
- `scripts/healthcheck.sh` reports the stack's status in table form and
  exits 0 only if every check passes.
- `scripts/pull-models.sh` is the only way to add models. The operator
  picks the size; the script does not.
- Models are not committed. They are pulled from Ollama's registry on
  demand.

## Quality gates

The project is considered correct when:

1. `bash -n` passes on every shell script in `deploy/` and `scripts/`.
2. `docs/` has no broken internal references.
3. Every file in `config/`, `deploy/`, `docs/`, `scripts/`, and `tests/`
   is referenced from somewhere or documented in `docs/`.
4. `git ls-files` matches the expected whitelist (see `.gitignore`).

These are checked manually for now; `tests/smoke.sh` provides an
end-to-end runtime gate that runs against a live box.

## Status

v0.1 — initial scaffolding. See `docs/09-roadmap.md` for the path from
here to v1.0.