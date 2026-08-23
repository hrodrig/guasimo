# 09 — Roadmap

## v0.1

Scaffolding and documentation. A new operator can read `docs/` and
understand the system without running anything. **Done.**

## v0.2 — Minimum viable install (tagged `v0.2.0`–`v0.2.2`)

Deliverables:

- [x] `deploy/install.sh` phases 1–5 on real Ubuntu 26.04 + RTX 3060
      (2026-07-31): CUDA `llama.cpp` (b4568 + GCC 15 patch), Ollama,
      Open WebUI 0.6.x (Python 3.12 via uv), nginx TLS. Lessons from
      that run live in `docs/08-troubleshooting.md`.
- [x] `scripts/pull-models.sh primary` exercised end-to-end on the
      validated box (2026-08-01): `qwen2.5-coder:14b-instruct-q4_K_M`
      ~9 GB; see `docs/04-models.md` +
      `docs/assets/ollama-pull-qwen25-coder-14b-ok.png`.
- [x] `scripts/benchmark.sh primary` on the box (2026-08-01):
      ~18 gen tok/s, ~4 prompt tok/s, 200 gen tokens
      (see `docs/04-models.md`).
- [x] `scripts/healthcheck.sh` exits 0: 8 ok / 0 fail
      (nginx, open-webui, ollama, 1 model, llama-server, nvidia,
      disk, RAM).

Exit criterion **met** (2026-08-01): install + primary pull +
healthcheck + benchmark + LAN chat at `https://192.168.10.69/` with
primary model selected. Evidence:
`docs/assets/open-webui-lan-192-168-10-69.png`. **Done.**

## v0.3 — Production polish (folded into v0.3.0)

All v0.3 deliverables shipped between v0.2.0 and v0.2.2:

- [x] Let's Encrypt via certbot + DNS-01 (no inbound 80) — **deferred** to v0.3.0+ (operator-driven, see `docs/06-networking-and-security.md`).
- [x] `scripts/open-firewall.sh` that prints the rule before applying — shipped in v0.2.0.
- [x] `scripts/rotate-logs.sh` + systemd timer — shipped in v0.2.0.
- [x] `scripts/backup-webui-db.sh` — shipped in v0.2.0.
- [x] An end-to-end smoke test script runnable from CI: `tests/smoke.sh` — shipped in v0.2.0 (CI integration pending in v1.0).

**Status: merged into v0.3.0.** The model refresh in v0.3.0 makes this
an organic merge rather than a separate tag.

## v0.3.0 — Qwen 3.8 generation (in progress)

- [x] New default primary `qwen3.8:27b` (Qwen3.8-27B-Instruct, Apache
      2.0, dense 27B, vision-language, 256K context, thinking on by
      default) — partial offload on the RTX 3060 (12 GB). See
      `docs/04-models.md` for the trade-off.
- [x] `thinking` Modelfile alias (`qwen3-27b-thinking`) — same
      `qwen3.8:27b` base, reasoning on. Reuses the primary pull.
- [x] `scripts/install-aliases.sh` — closes the v0.2.x gap where
      checked-in Modelfile recipes were never auto-applied. Now runs
      at the end of `pull-models.sh` and is callable standalone.
- [x] `large` slot demoted to LEGACY. The 32B Qwen2.5-Coder recipe
      stays in the repo for experiments but is no longer pulled by
      `pull-models.sh`.
- [x] Disk-budget estimation in `pull-models.sh` updated to the
      18 GB Q4_K_M footprint of the new primary.
- [x] Validate end-to-end on the reference box (Ubuntu 26.04 +
      RTX 3060, done 2026-08-23): `pull-models.sh primary` completed,
      the `qwen3-27b` alias answers in Open WebUI,
      `benchmark.sh primary` reports gen tok/s in range (4 t/s @ 64K
      `num_ctx`; prompt 35 t/s), `healthcheck.sh` still 8/0.
- [ ] Capture `docs/assets/ollama-pull-qwen38-27b-ok.png` and refresh
      `docs/assets/open-webui-lan-192-168-10-69.png` with the new
      model selected (manual browser capture; pending).

## v0.4 — Multiple model recipes

- [x] DeepSeek-Coder-V2-Lite as pull nickname `deepseek`
      (`deepseek-coder-v2:lite`) + Gemma 4 12B as `gemma`
      (`gemma4:12b`) in `scripts/pull-models.sh` / `benchmark.sh`
      (docs in `docs/04-models.md`). Operator still pulls on demand.
- [x] Thinking variant of the primary — shipped in v0.3.0 as
      `qwen3-27b-thinking`. Replaces the original "explainer" /
      "reviewer" idea with a single reasoning-on alias; the recipe
      is one line of system-prompt edit away from either behaviour.
- [x] Wire model picker into Open WebUI's per-conversation default —
      `DEFAULT_MODELS=coder-14b` in `deploy/systemd/open-webui.service`
      pre-selects the fast secondary alias in the chat model picker. The
      primary `qwen3-27b` (and `-thinking`) remains reachable by
      explicit selection for deep/long-context work; `coder-14b`
      (33 t/s @ 8K ctx) is the right default for day-to-day Go/Rust/React
      coding, while the 27B @ 64K is the trade-off for agentic depth.
      Activated on re-run of `deploy/install.sh` (or reinstall of the
      unit); the aliases are created by `install-aliases.sh` after
      `pull-models.sh`.

**Status: merged into v0.3.0.** All v0.4 deliverables have shipped.

## v1.0 — Single-user LAN, stable

- Pinned versions, all packages from apt where possible.
- `tests/smoke.sh` runs in CI on a real Ubuntu 26.04 VM. **Still pending.**
- `docs/` passes a self-audit (no broken links, every config in `config/`
  referenced, every script explained). **Partial: links OK in
  v0.3.0, full audit pending.**
- Upgrade procedure for each component is tested on a clean VM.

## Post-v1 — Considered but deferred

- GPU-first install path as the default (revisit when Qwen 3.x
  yields a fast ≤14 B tier that fits fully in 12 GB VRAM again).
- Multi-user mode in Open WebUI.
- Vector store for codebase-wide RAG (Chroma or Qdrant).
- Fine-tuning pipeline (LoRA on top of Qwen 3.8 for the user's own
  Go/C# code).
- Prometheus exporter for tokens/s, KV cache utilisation.
- WireGuard overlay so the box can be reached from outside the LAN
  without exposing it on the WAN.
- An MCP server exposing file/git tools to the model.
- Quantisation-aware fine-tuning for the Qwen 3.8 27B GGUF to recover
  the tokens/s the v0.2.x 14B had (deferred until the offload
  tradeoff feels too costly in daily use).

Each deferred item has a one-line rationale: not needed for "LLM that
helps me write Go and C#". Revisit when a real second user shows up.