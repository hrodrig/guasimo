# 09 — Roadmap

## v0.1 (this commit)

Scaffolding and documentation. A new operator can read `docs/` and
understand the system without running anything.

## v0.2 — Minimum viable install

Deliverables:

- `deploy/install.sh` that passes the Phase 1–5 contract from
  `docs/05-deployment.md` on a clean Ubuntu 26.04 VM.
- `scripts/pull-models.sh primary secondary` that actually downloads the
  GGUF blobs.
- `scripts/benchmark.sh primary` that prints tokens/s on the box.
- `scripts/healthcheck.sh` that exits 0 on a working stack.

Exit criterion: a fresh Ubuntu VM, single `install.sh`, 30 minutes later,
the operator has a working chat UI on `https://<hostname>/`.

## v0.3 — Production polish

- Let's Encrypt via certbot + DNS-01 (no inbound 80).
- `scripts/open-firewall.sh` that prints the rule before applying.
- `scripts/rotate-logs.sh` + systemd timer.
- `scripts/backup-webui-db.sh`.
- An end-to-end smoke test script runnable from CI: `tests/smoke.sh`.

## v0.4 — Multiple model recipes

- Add DeepSeek-Coder-V2-Lite-Instruct as a third option.
- Add Modelfile variants: "explainer" (higher temperature) and "reviewer"
  (critique mode).
- Wire model picker into Open WebUI's per-conversation default.

## v1.0 — Single-user LAN, stable

- Pinned versions, all packages from apt where possible.
- `tests/smoke.sh` runs in CI on a real Ubuntu 26.04 VM.
- `docs/` passes a self-audit (no broken links, every config in `config/`
  referenced, every script explained).
- Upgrade procedure for each component is tested on a clean VM.

## Post-v1 — Considered but deferred

- GPU-first install path as the default (revisit when 14 B becomes the
  "fast" tier).
- Multi-user mode in Open WebUI.
- Vector store for codebase-wide RAG (Chroma or Qdrant).
- Fine-tuning pipeline (LoRA on top of Qwen2.5-Coder for the user's own
  Go/C# code).
- Prometheus exporter for tokens/s, KV cache utilisation.
- WireGuard overlay so the box can be reached from outside the LAN
  without exposing it on the WAN.
- An MCP server exposing file/git tools to the model.

Each deferred item has a one-line rationale: not needed for "LLM that
helps me write Go and C#". Revisit when a real second user shows up.