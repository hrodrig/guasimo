# 09 — Roadmap

## v0.1

Scaffolding and documentation. A new operator can read `docs/` and
understand the system without running anything.

## v0.2 — Minimum viable install (tagged `v0.2.0`)

Deliverables:

- [x] `deploy/install.sh` phases 1–5 on real Ubuntu 26.04 + RTX 3060
      (2026-07-31): CUDA `llama.cpp` (b4568 + GCC 15 patch), Ollama,
      Open WebUI 0.6.x (Python 3.12 via uv), nginx TLS. Lessons from
      that run live in `docs/08-troubleshooting.md`.
- [x] `scripts/pull-models.sh primary` exercised end-to-end on the
      validated box (2026-08-01): `qwen2.5-coder:14b-instruct-q4_K_M`
      ~9 GB; see `docs/04-models.md` +
      `docs/assets/ollama-pull-qwen25-coder-14b-ok.png`.
      (`secondary` still optional / not yet pulled.)
- [x] `scripts/benchmark.sh primary` on the box (2026-08-01):
      ~18 gen tok/s, ~4 prompt tok/s, 200 gen tokens
      (see `docs/04-models.md`).
- [x] `scripts/healthcheck.sh` exits 0: 8 ok / 0 fail
      (nginx, open-webui, ollama, 1 model, llama-server, nvidia,
      disk, RAM).

Exit criterion: after `install.sh` + `pull-models.sh primary`, chat UI
on `https://<hostname>/` with the primary model. Stack green on the
reference box; confirm once in the browser if not already.

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