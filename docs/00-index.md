# 00 — Index

**Guasimo** — **G**raphical **U**tility for **A**I **S**erver **I**nference
of **M**odels, **O**pen-source. A self-hosted local LLM workstation.

This directory is the authoritative technical documentation for the project.
Code in `deploy/`, `scripts/`, and `config/` is the operational surface; the
files here are the contract that surface must honour.

## Reading order

| # | File                          | Purpose                                              |
|---|-------------------------------|------------------------------------------------------|
| 01| `01-architecture.md`          | System diagram, component responsibilities, data flow |
| 02| `02-hardware-decisions.md`    | Why CPU-first, GPU opt-in, RAM/VRAM math, disk layout |
| 03| `03-stack-choice.md`          | Why llama.cpp + Ollama + Open WebUI (vs LM Studio etc) |
| 04| `04-models.md`                | Which models, quantisation levels, role per model    |
| 05| `05-deployment.md`            | What `install.sh` does, idempotency, ordering        |
| 06| `06-networking-and-security.md`| LAN exposure, TLS, auth, firewall                    |
| 07| `07-operations.md`            | Logs, backups, upgrades, model rotation              |
| 08| `08-troubleshooting.md`       | Common failures and their first response             |
| 09| `09-roadmap.md`               | v0.2 / v0.3 / v1.0 plans                             |

## Conventions used in this repo

- All commands assume the repository root unless prefixed with `cd ...`.
- All paths inside shell snippets are relative to `$REPO` = `~/guasimo`.
- Versions are pinned in `deploy/install.sh`. Bumping them is a deliberate act.
- Anything that creates a file on disk must be idempotent on second run.