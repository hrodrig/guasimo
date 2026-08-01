# 07 — Operations

## Daily ops

After install, day-to-day operation is one of:

| Want to...                                | Run                                      |
|-------------------------------------------|------------------------------------------|
| Start the stack after a reboot           | `sudo systemctl start guasimo.target`     |
| Stop the stack                            | `sudo systemctl stop guasimo.target`      |
| See status of all three services          | `systemctl status 'ollama\|llama-cpp\|open-webui'` |
| Pull a new model                          | `./scripts/pull-models.sh <nickname\|tag>` (`primary`, `secondary`, `gemma`, `deepseek`, …) |
| Drop a model                              | `ollama rm <name>`                       |
| Re-render the nginx config                | `sudo nginx -t && sudo systemctl reload nginx` |
| Tail logs                                 | `journalctl -u ollama -u open-webui -f`  |
| Health check                              | `./scripts/healthcheck.sh`               |
| Wire Hermes / IDE from another LAN host   | SSH tunnel + `/v1` — see `docs/06-networking-and-security.md` |
| Hermes "context below 64K" error          | Raise ctx without changing model — `docs/08-troubleshooting.md` |

`guasimo.target` is a systemd target that orders the three services so
nginx waits for Open WebUI, Open WebUI waits for Ollama, Ollama waits for
nothing (it manages its own llama.cpp child). The target is the single
thing an operator needs to learn.

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
- To swap the primary model, edit `config/ollama/Modelfile.coder-14b`,
  run `ollama create coder-14b -f ...`, restart Open WebUI.
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