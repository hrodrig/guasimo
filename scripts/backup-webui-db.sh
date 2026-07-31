#!/usr/bin/env bash
# scripts/backup-webui-db.sh — snapshot Open WebUI's SQLite database.
#
# The DB lives at /data/open-webui/webui.db (per open-webui.service).
# The file is small (chat history, user accounts) and the WAL can be live.
# We use sqlite3's .backup command which is safe against concurrent writes.

set -euo pipefail

SRC="/data/open-webui/webui.db"
DEST_DIR="/bulk/backups/open-webui"
RETENTION_DAYS=30

if [ ! -f "${SRC}" ]; then
  echo "no Open WebUI database at ${SRC}; nothing to back up" >&2
  exit 0
fi

mkdir -p "${DEST_DIR}"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST="${DEST_DIR}/webui-${STAMP}.db"

# Use the dedicated "ia-lab" service user to read; the file is owned by it.
sudo -u ia-lab sqlite3 "${SRC}" ".backup '${DEST}'"

gzip -9 "${DEST}"
echo "wrote ${DEST}.gz"

# Retention
find "${DEST_DIR}" -type f -name 'webui-*.db.gz' \
  -mtime +"${RETENTION_DAYS}" -delete

echo "retention: ${RETENTION_DAYS} days"