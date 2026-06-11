#!/bin/bash
set -euo pipefail

LOCAL_STAGING="/tmp/backup-staging"
REMOTE_STAGING="/backups/staging"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

mkdir -p "${LOCAL_STAGING}" "${REMOTE_STAGING}" /backups/restic-repo
log "=== Début sauvegarde ${TIMESTAMP} ==="

log "Dump PostgreSQL..."
PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    -h "${DB_HOST:-db-primary}" \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    -F c \
    -f "${LOCAL_STAGING}/db_${TIMESTAMP}.dump"

log "Transfert vers backup-server (SCP/SSH)..."
if [ -f /root/.ssh/id_ed25519 ] && scp -i /root/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=accept-new \
    -o BatchMode=yes \
    "${LOCAL_STAGING}/db_${TIMESTAMP}.dump" \
    "backup@backup-server:${REMOTE_STAGING}/" 2>/dev/null; then
    log "Transfert SCP réussi."
else
    log "SCP indisponible, copie via volume partagé."
    cp "${LOCAL_STAGING}/db_${TIMESTAMP}.dump" "${REMOTE_STAGING}/"
fi

log "Sauvegarde Restic chiffrée..."
export RESTIC_PASSWORD="${RESTIC_PASSWORD:?RESTIC_PASSWORD manquant}"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/restic-repo}"

if ! restic snapshots >/dev/null 2>&1; then
    log "Initialisation du dépôt Restic..."
    restic init
fi

restic backup "${REMOTE_STAGING}" \
    --tag "auto" \
    --tag "db" \
    --host "projet-b2"

restic forget --keep-last 7 --prune

log "=== Sauvegarde terminée ==="
rm -rf "${LOCAL_STAGING}"
find "${REMOTE_STAGING}" -name "*.dump" -mtime +1 -delete 2>/dev/null || true
