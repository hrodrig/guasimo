#!/usr/bin/env bash
# scripts/rotate-logs.sh — compress and expire ia-lab logs.
#
# Wired to ia-lab-logrotate.timer (weekly). Operates on /var/log/ia-lab.
# Keeps 7 days uncompressed, 90 days total.

set -euo pipefail

LOG_DIR="/var/log/ia-lab"
KEEP_RAW_DAYS=7
KEEP_COMPRESSED_DAYS=90

cd "${LOG_DIR}"

# 1) compress logs older than KEEP_RAW_DAYS that aren't already .gz
find . -maxdepth 1 -type f -name '*.log' -mtime +"${KEEP_RAW_DAYS}" \
  ! -name '*.gz' -exec gzip -9 {} \;

# 2) delete compressed logs older than KEEP_COMPRESSED_DAYS
find . -maxdepth 1 -type f -name '*.log.gz' -mtime +"${KEEP_COMPRESSED_DAYS}" \
  -delete

echo "$(date -Is) rotated logs in ${LOG_DIR}"