#!/usr/bin/env bash
# deploy/uninstall.sh — remove the ia-lab stack.
#
# Keeps downloaded model blobs in /data/models and /bulk/models.
# Keeps the log directory. Removes services, binaries, config, certs.

set -euo pipefail

INSTALL_ROOT="/opt/ia-lab"
SERVICE_USER="ia-lab"

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

systemctl disable --now ia-lab.target open-webui.service 2>/dev/null || true
systemctl disable --now ollama.service nginx 2>/dev/null || true

rm -f /etc/systemd/system/ia-lab.target
rm -f /etc/systemd/system/open-webui.service
rm -rf /etc/systemd/system/ollama.service.d
systemctl daemon-reload

rm -f /etc/nginx/sites-enabled/ia-lab.conf
rm -f /etc/nginx/sites-available/ia-lab.conf
nginx -t 2>/dev/null && systemctl reload nginx || true

rm -rf "${INSTALL_ROOT}"
rm -rf /etc/nginx/ssl/ia-lab

if id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  userdel "${SERVICE_USER}" 2>/dev/null || true
fi

echo "Uninstalled. Model blobs in /data/models and /bulk/models were kept."
echo "Re-run deploy/install.sh to recreate the stack."