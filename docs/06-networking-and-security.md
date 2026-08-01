# 06 — Networking and security

## Threat model

This is a **single-user workstation on a trusted LAN**. The threat model is
"casual visitor on the Wi-Fi", not "nation-state adversary". We optimise
for: don't accidentally expose the model to the internet, don't let
browsers cache tokens, don't run the services as root.

Out of scope: zero-trust networking, mutual TLS, HSM, audit-grade logging,
DLP.

## Listening sockets (default)

| Service       | Bind                | Port (tcp) | TLS   |
|---------------|---------------------|------------|-------|
| llama-server  | 127.0.0.1           | 8081       | No    |
| Ollama        | 127.0.0.1           | 11434      | No    |
| Open WebUI    | 127.0.0.1           | 8080       | No    |
| nginx         | 0.0.0.0             | 80, 443    | Yes (443) |

The inference services bind to loopback only. nginx is the only service
listening on the LAN-facing side. nginx terminates TLS and reverse-proxies
to Open WebUI.

This means:

- IDE plugins on the same host use `http://127.0.0.1:11434/v1/...` directly.
- LAN browsers use `https://<hostname>/` (or LAN IP).
- The model API is never exposed to the LAN, only to Open WebUI on
  loopback.

### Validated LAN access (2026-08-01)

Reference box at `192.168.10.69`: browser on another LAN host opened
`https://192.168.10.69/` (self-signed → "Not secure" warning expected),
Open WebUI with `qwen2.5-coder:14b-instruct-q4_K_M` selected.

![Open WebUI over LAN at 192.168.10.69](assets/open-webui-lan-192-168-10-69.png)

## TLS

- `deploy/install.sh` generates a self-signed cert for the hostname at
  install time so first-run UX is "open https://<hostname>/ and accept the
  cert".
- Production should swap the cert for one issued by an internal CA or by
  Let's Encrypt. The swap is documented in `docs/09-roadmap.md`.
- TLS config in nginx is the Mozilla "intermediate" profile (no TLS 1.0/1.1,
  strong ciphers, HSTS off by default to avoid lock-in for the LAN).

## Authentication

- Open WebUI is configured for single-user mode (first account created
  becomes admin).
- No password reset flow; recovery is "ssh in, delete the SQLite user row".
- Open WebUI handles session cookies. nginx adds no auth layer; adding one
  would only complicate the proxy and add nothing if the LAN is trusted.

## Firewall

By default, the install **does not** open any firewall ports. The operator
must run `scripts/open-firewall.sh` explicitly:

    ufw allow from 192.168.0.0/16 to any port 443 proto tcp

That script is a thin wrapper around `ufw` and prints the rule before
applying. It never opens ports to `0.0.0.0`.

If `ufw` is inactive, the script informs the operator and exits non-zero.
We do not silently enable a firewall.

## Sandbox / privilege

- The three services run as a dedicated unprivileged user `guasimo` created
  by `install.sh`, not as root.
- `guasimo` has write access to `/data/models`, `/bulk/models`, `/var/log/guasimo`.
- No service gets sudo. No service has CAP_NET_BIND_SERVICE except nginx
  (which already binds 443 as a systemd-managed process).

## What the install script does NOT do

- Set up Let's Encrypt.
- Configure a reverse proxy other than nginx.
- Open ports automatically.
- Pull or store any credentials.

## Logging hygiene

- Inference logs (prompts, completions) are written to
  `/var/log/guasimo/` with mode `0640`, owner `guasimo:adm`.
- Log rotation is handled by `scripts/rotate-logs.sh` (cron'd weekly). We
  do not use `logrotate` for these files because the format is not
  syslog-native and we'd rather have one tool to look at.
- We do not log full prompts by default — only request ID, model, token
  counts, and latency. Full prompt logging is opt-in via env var.

## Backups

Inference config and recipes (`config/`, `deploy/`, `docs/`) are in the
git repo. Models are not; they are reproducible from upstream pulls.

For disaster recovery:

- `git clone` the repo.
- Re-run `deploy/install.sh`.
- Re-run `scripts/pull-models.sh primary secondary`.

Total restore time: download speed × (9 GB + 5 GB) + ~10 min setup.