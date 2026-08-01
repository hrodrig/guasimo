#!/usr/bin/env bash
# deploy/uninstall.sh — remove the guasimo stack.
#
# Keeps downloaded model blobs in /data/models and /bulk/models.
# Keeps the log directory. Removes services, binaries, config, certs.
# Also cleans legacy ia-lab names from the pre-rebrand install path.

set -euo pipefail

INSTALL_ROOT="/opt/guasimo"
SERVICE_USER="guasimo"
LEGACY_ROOT="/opt/ia-lab"
LEGACY_USER="ia-lab"

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

systemctl disable --now guasimo.target open-webui.service 2>/dev/null || true
systemctl disable --now guasimo-logrotate.timer 2>/dev/null || true
systemctl disable --now ia-lab.target 2>/dev/null || true
systemctl disable --now ia-lab-logrotate.timer 2>/dev/null || true
systemctl disable --now ollama.service nginx 2>/dev/null || true

rm -f /etc/systemd/system/guasimo.target
rm -f /etc/systemd/system/guasimo-logrotate.service
rm -f /etc/systemd/system/guasimo-logrotate.timer
rm -f /etc/systemd/system/ia-lab.target
rm -f /etc/systemd/system/ia-lab-logrotate.service
rm -f /etc/systemd/system/ia-lab-logrotate.timer
rm -f /etc/systemd/system/open-webui.service
rm -rf /etc/systemd/system/ollama.service.d
systemctl daemon-reload

rm -f /etc/nginx/sites-enabled/guasimo.conf /etc/nginx/sites-available/guasimo.conf
rm -f /etc/nginx/sites-enabled/ia-lab.conf /etc/nginx/sites-available/ia-lab.conf
nginx -t 2>/dev/null && systemctl reload nginx || true

rm -rf "${INSTALL_ROOT}" "${LEGACY_ROOT}"
rm -rf /etc/nginx/ssl/guasimo /etc/nginx/ssl/ia-lab

for u in "${SERVICE_USER}" "${LEGACY_USER}"; do
  if id -u "${u}" >/dev/null 2>&1; then
    userdel "${u}" 2>/dev/null || true
  fi
done

echo "Uninstalled. Model blobs in /data/models and /bulk/models were kept."
echo "Re-run deploy/install.sh to recreate the stack."
