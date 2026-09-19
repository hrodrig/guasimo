# 07 — Operations

## Daily ops

After install, day-to-day operation is one of:

| Want to...                                | Run                                      |
|-------------------------------------------|------------------------------------------|
| Start the stack after a reboot           | `sudo systemctl start guasimo.target`     |
| Stop the stack                            | `sudo systemctl stop guasimo.target`      |
| See status of all three services          | `systemctl status 'ollama\|llama-cpp\|open-webui'` |
| Pull a new model                          | `./scripts/pull-models.sh <nickname\|tag>` (`primary` = `ornith-9b`, `secondary` = `qwen3.8:27b`, `thinking`, `large` / 35B, `bonsai`, `gemma`, `deepseek`, …) |
| Recreate Modelfile aliases                | `./scripts/install-aliases.sh`           |
| Drop a model                              | `ollama rm <name>`                       |
| Re-render the nginx config                | `sudo nginx -t && sudo systemctl reload nginx` |
| Tail logs                                 | `journalctl -u ollama -u open-webui -u guasimo-thermal -f`  |
| Health check                              | `./scripts/healthcheck.sh`               |
| Go quality gate (Ornith assertiveness)    | `ORNITH_BASE=http://192.168.10.10:8082/v1 ORNITH_MODEL=ornith-35b ./scripts/eval-go-ornith.sh` |
| Serve Ornith-35B (quality)                | `./scripts/serve-35b.sh` (OpenAI `/v1`; default `:8081`; AMD lab systemd `:8082`) |
| Serve Bonsai 2 (PrismML fork)             | `sudo ./scripts/build-bonsai-llama.sh` once, then `./scripts/serve-bonsai.sh` (`:8083`; `--no-repack` default — see `docs/04-models.md`) |
| Wire clients from another LAN host        | AMD lab: direct `http://192.168.10.10:8082/v1` (no tunnel). Ollama/CUDA: SSH tunnel — `docs/06-networking-and-security.md` |
| Hermes "context below 64K" error          | Raise ctx without changing model — `docs/08-troubleshooting.md` |
| Slow tokens/s on RTX 3060 (12 GB)         | Partial offload is expected; see `docs/08-troubleshooting.md` → *low tokens/s with qwen3.8:27b* |

`guasimo.target` is a systemd target that orders the three services so
nginx waits for Open WebUI, Open WebUI waits for Ollama, Ollama waits for
nothing (it manages its own llama.cpp child). The target is the single
thing an operator needs to learn.

## Lab hosts

| Role | Host | Hardware | Notes |
|------|------|----------|-------|
| Reference (CUDA) | `192.168.10.69` | Intel + RTX 3060 12 GB, 32 GB RAM | Docs screenshots / LAN hero |
| AMD lab | `192.168.10.10` (`hrodrig-EliteMini-Series`) | Ryzen 7640HS + Radeon 760M, ~76 GB RAM | Vulkan llama.cpp; thermal unit on |

Repo checkout on the AMD lab is typically `~/guasimo` (rsync from the
dev machine is fine; `.git` optional). Live binaries live under
`/opt/guasimo/`. Cold GGUFs in `/bulk/models/`.

### Port map (AMD lab convention)

Scripts default to the ports below so optional servers do not collide.
**Policy: one inference path at a time** (see `docs/06` → AMD lab modes).
`guasimo-llama` 9B stays disabled. Flip between Ollama (Gemma) and
`guasimo-llama-35b` — never both.

| Port | Service | How |
|------|---------|-----|
| `:443` | nginx → Open WebUI | systemd |
| `:8080` | Open WebUI (loopback) | systemd |
| `:11434` | Ollama OpenAI-compat (LAN when override set) | **fast mode** — `gemma4:12b` |
| `:8081` | (idle) was Ornith 9B | disabled |
| `:8082` | Ornith 35B `--cpu-moe`, LAN `0.0.0.0` | **quality mode** — `guasimo-llama-35b` |
| `:8083` | Bonsai 2 (`serve-bonsai.sh`) | PrismML; experimental |

`serve-35b.sh` still defaults to `:8081` for a clean single-quality-path
box. Lab systemd binds **`:8082` on all interfaces** for quality mode.

Open WebUI → Admin → Connections → **OpenAI API** for non-Ollama servers
(`http://127.0.0.1:8082/v1`, `http://127.0.0.1:8083/v1`, …).

### Pending lab bake-offs (do not close without measuring)

| Track | Status | Next |
|-------|--------|------|
| **Hermes + Gemma 4 12B** | usable (~15–21 s TTFB w/ skills) | keep as fast-mode default |
| **Hermes + Ornith-35B** | too slow w/ full skills | only lean clients / Pi `-ns` |
| **Colibrì** (`~/colibri`, binary built) | **blocked** — HF snapshot of `Kreuzzelg/qwen36-35b-a3b-colibri-i4-gs64` → `/bulk/models/qwen36_i4_gs64` incomplete (~9/47 shards, CDN/DNS flake); resume `hf download … --local-dir` | finish download → `./coli chat --model …` |
| **Ollama pulls** | `gemma4:12b`, `deepseek-coder-v2:lite` **done** | optional smoke under Hermes / Colibrì if format fits |
| **deepseek-v4-flash** dir | empty placeholder | drop or finish pull |
| **Bonsai 2** | GGUF present; `--no-repack` loads then unusable under load | tok/s + quality vs Ornith before promoting |

When the mini is back on LAN: resume Colibrì download first, then bake-off
Qwen36-i4 / DeepSeek paths against Gemma+Hermes and Ornith curl baselines.

## Thermal (AMD)

The mini-PC soft-caps at **80 °C** (Tjmax 95 °C) after a burst-capacitor
failure under sustained load.

| Piece | Role |
|-------|------|
| `guasimo-thermal.service` | Always-on sampler → journal (`thermal-monitor.sh`) |
| `scripts/thermal-guard.sh` | One-shot backoff; called by `serve-35b.sh` / `serve-bonsai.sh` |
| `healthcheck.sh` | Reports SoC/GPU peak; FAIL if above cap |

```bash
systemctl status guasimo-thermal
journalctl -u guasimo-thermal -f
THERMAL_MAX_C=85 ./scripts/thermal-guard.sh 3   # optional override
```

Enabled automatically by `install.sh` when AMD graphics hardware is
detected. CUDA-only boxes leave the unit disabled.

## Upgrades

### Upgrading llama.cpp

1. Edit `LLAMA_CPP_REF` in `deploy/install.sh`.
2. Re-run `sudo ./deploy/install.sh`. Phase 3 detects the SHA mismatch and
   rebuilds.
3. Restart: `sudo systemctl restart ollama` (Ollama will respawn the new
   llama-server).

### Upgrading Ollama

- If pinned to Ubuntu `.deb`, `apt upgrade ollama` and restart.
- If installed via upstream script, re-run `curl -fsSL .../install.sh | sh`
  and restart.

### Upgrading Open WebUI

- Edit the version in `requirements.txt`.
- `sudo -u guasimo /opt/guasimo/webui-venv/bin/pip install -U -r requirements.txt`.
- `sudo systemctl restart open-webui`.

### Upgrading the box

- `apt full-upgrade`.
- Reboot.
- Re-run `scripts/healthcheck.sh`. If llama.cpp fails to load a model,
  rebuild llama.cpp (kernel ABI may have shifted).

## Backups

- `config/`, `deploy/`, `docs/` are in git. Backed up by virtue of being
  in git.
- `models/` is **not** in git. Recovery = re-pull.
- `/var/log/guasimo/` is rotated weekly; not backed up.
- Open WebUI's SQLite DB lives at `/data/open-webui/webui.db`. Back this up
  with `scripts/backup-webui-db.sh` weekly if conversation history matters.

## Log rotation

- `scripts/rotate-logs.sh` is the canonical log rotator.
- Compresses `/var/log/guasimo/*.log` older than 7 days, deletes older than
  90 days.
- Triggered via a systemd timer (`guasimo-logrotate.timer`), weekly.

## Model rotation

- Models are pulled on demand. There is no automatic re-pull.
- To swap the primary model, edit `config/ollama/Modelfile.qwen3-27b`
  (or whichever recipe you want to change), run
  `scripts/install-aliases.sh qwen3.8` to re-create the alias, and
  restart Open WebUI.
- To remove a stale model: `ollama rm <name>`. The blob stays in
  `/bulk/models/` until manually deleted; this is intentional, so the
  next `ollama create` is fast.

## Health check semantics

`scripts/healthcheck.sh` reports a table:

| Component  | Check                                  | Pass condition                  |
|------------|----------------------------------------|---------------------------------|
| nginx      | `nginx -t`                             | exit 0                          |
| Open WebUI | `GET /`                                | HTTP 200                        |
| Ollama     | `GET /api/tags`                        | HTTP 200 and `models[]` non-empty |
| llama.cpp  | Ollama list-loaded-models equivalent   | at least one model loaded       |
| Accelerator| `nvidia-smi` *or* AMD render + RADV    | driver / ICD healthy            |
| Thermal    | peak `k10temp` / `amdgpu` (AMD only)   | ≤ 80 °C soft cap                |
| Disk       | `/data` free space                     | > 5 GB                          |
| RAM        | available RAM                          | > 4 GB                          |

Exit code: 0 if all pass, 1 if any fails. Designed to be wired into cron
or a status page later.

## Observability

No Prometheus / Grafana in v1. Reasoning: overkill for a single-user box.
If we ever want to track tokens/s, inference latency, OOM events — that's
`docs/09-roadmap.md`.

## What this doc explicitly does not cover

- Multi-tenant operations
- Disaster recovery beyond "re-clone + re-pull"
- Compliance / audit logging