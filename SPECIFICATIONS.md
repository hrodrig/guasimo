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
  back. `systemctl status guasimo.target` should report `active`.

## Model contract

- Primary: `qwen3.8:27b` (Q4_K_M, ~18 GB). Qwen3.8-27B-Instruct, Apache 2.0,
  dense 27B, vision-language (text + image), 256K context, thinking on by
  default. On the RTX 3060 (12 GB) this is partial-offloaded; the operator
  can force a lower `num_ctx` to keep RAM pressure manageable. See
  `docs/04-models.md` and `docs/08-troubleshooting.md` for the
  partial-offload tradeoff.
- Primary alias: `qwen3-27b`, created from
  `config/ollama/Modelfile.qwen3-27b` (inherits the shared coding system
  prompt and conservative sampling defaults). Pulled and aliased by
  `scripts/pull-models.sh primary`; the alias is set up automatically by
  `scripts/install-aliases.sh` once the base is in the local library.
- Secondary: `qwen2.5-coder:7b-instruct-q4_K_M` (~5 GB). Full VRAM on the
  RTX 3060; the fast path. Unchanged from v0.2.x.
- Thinking variant: same `qwen3.8:27b` base as primary, with a system
  prompt that forces explicit step-by-step reasoning. Alias
  `qwen3-27b-thinking` from
  `config/ollama/Modelfile.qwen3-27b-thinking`. Use for review, multi-step
  refactor, and hard bug analysis; not the chat default.
- Large (LEGACY, partial offload): `qwen2.5-coder:32b-instruct-q4_K_M`
  (~20 GB). Not pulled by `pull-models.sh` since v0.3.0. Operators who
  want to experiment with it can `ollama pull qwen2.5-coder:32b-instruct-q4_K_M`
  directly.
- Optional nicknames in `scripts/pull-models.sh`:
  `gemma` → `gemma4:12b`; `deepseek` → `deepseek-coder-v2:lite`.
- The primary, thinking, and secondary recipes are upstream Ollama
  recipes or Modelfile aliases checked in to this repo. No fine-tuned
  model weights ship with this project.

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

**v0.3.0** (in progress) — Qwen 3.8 generation. New default primary
`qwen3.8:27b` (Qwen3.8-27B-Instruct, Apache 2.0, dense 27B, vision
+ image, 256K context, thinking on by default), with two Modelfile
aliases: `qwen3-27b` (default chat) and `qwen3-27b-thinking` (reasoning
on). `scripts/install-aliases.sh` closes the v0.2.x gap where the
checked-in recipes were never auto-applied. `large` slot becomes a
legacy reference to Qwen2.5-Coder-32B. See `docs/04-models.md`,
`docs/08-troubleshooting.md`, `CHANGELOG.md`, and `docs/09-roadmap.md`.

**v0.2.2** (2026-08-01) — install, primary pull, healthcheck (8/0),
benchmark (~18 gen tok/s), and LAN chat UI (`https://192.168.10.69/`)
validated on Ubuntu 26.04 + RTX 3060. Hermes Agent client docs;
optional `gemma` / `deepseek` model nicknames.
