#!/usr/bin/env bash
# scripts/open-firewall.sh — explicit, audited opening of port 443 on the LAN.
#
# Refuses to open 0.0.0.0. Prints the rule before applying. No daemon,
# no surprises. Run as root.

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0 [CIDR]" >&2; exit 1; }

CIDR="${1:-192.168.0.0/16}"

# Validate CIDR shape. Bash's regex is good enough for the common forms.
if ! [[ "${CIDR}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]; then
  echo "refusing to apply: ${CIDR} does not look like a CIDR" >&2
  exit 2
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw not installed. Install with: apt-get install -y ufw" >&2
  exit 3
fi

# Refuse a "default" CIDR like 0.0.0.0/0.
if [[ "${CIDR}" =~ ^0\.0\.0\.0/0$ ]]; then
  echo "refusing to open to 0.0.0.0/0. Pass a LAN CIDR (e.g. 192.168.0.0/16)." >&2
  exit 4
fi

RULE="ufw allow from ${CIDR} to any port 443 proto tcp comment 'ia-lab HTTPS'"

cat <<EOF
about to run:
  ${RULE}

This will not enable ufw if it is inactive. Verify before pressing on.
EOF
read -rp "apply? [y/N] " ans
if [[ ! "${ans}" =~ ^[Yy]$ ]]; then
  echo "aborted"; exit 0
fi

# Enable ufw non-interactively if it is inactive.
if ufw status 2>/dev/null | grep -q 'Status: inactive'; then
  ufw --force enable
fi

${RULE}
ufw reload
ufw status verbose