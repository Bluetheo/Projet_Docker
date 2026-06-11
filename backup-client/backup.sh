#!/bin/bash
set -euo pipefail

BACKUP_DIR="/tmp/backup-staging"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"
log "=== Début sauvegarde $TIMESTAMP ==="

log "Dump PostgreSQL..."
PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    -h "${DB_HOST:-db-primary}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -F c \
    -f "${BACKUP_DIR}/db_${TIMESTAMP}.dump"

log "Sauvegarde Restic (chiffrée, via SFTP/SSH)..."
export RESTIC_PASSWORD
export RESTIC_REPOSITORY

restic snapshots >/dev/null 2>&1 || restic init

restic backup "${BACKUP_DIR}" \
    --tag "auto" \
    --tag "db" \
    --host "projet-b2"

restic forget --keep-last 7 --prune

log "=== Sauvegarde terminée ==="
rm -rf "${BACKUP_DIR}"
