#!/bin/bash
set -euo pipefail

# Restauration complète depuis le serveur de sauvegarde Restic
# Usage: ./scripts/restore.sh [snapshot-id]

SNAPSHOT="${1:-latest}"
RESTORE_DIR="/tmp/restic-restore-$$"
RESTIC_PASSWORD="${RESTIC_PASSWORD:-backup-secret-key-change-me}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== Restauration complète depuis Restic ==="

log "Liste des snapshots disponibles :"
docker exec -e RESTIC_PASSWORD="${RESTIC_PASSWORD}" \
    -e RESTIC_REPOSITORY="/backups/restic-repo" \
    backup-client restic snapshots

log "Restauration du snapshot: ${SNAPSHOT}"
docker exec -e RESTIC_PASSWORD="${RESTIC_PASSWORD}" \
    -e RESTIC_REPOSITORY="/backups/restic-repo" \
    backup-client sh -c "
        mkdir -p ${RESTORE_DIR} && \
        restic restore ${SNAPSHOT} --target ${RESTORE_DIR} && \
        ls -la ${RESTORE_DIR}/tmp/backup-staging/ 2>/dev/null || ls -laR ${RESTORE_DIR}
    "

DUMP_FILE=$(docker exec backup-client sh -c "find ${RESTORE_DIR} -name '*.dump' | head -1" 2>/dev/null || true)

if [ -z "$DUMP_FILE" ]; then
    log "ERREUR: Aucun dump PostgreSQL trouvé dans la sauvegarde."
    exit 1
fi

log "Dump trouvé: ${DUMP_FILE}"
log "Arrêt des serveurs web pour restauration..."
docker stop web1 web2 2>/dev/null || true

log "Restauration de la base de données..."
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-secretpassword}" db-primary sh -c "
    dropdb -U app --if-exists appdb && \
    createdb -U app appdb && \
    pg_restore -U app -d appdb ${DUMP_FILE}
" 2>/dev/null || {
    log "Tentative alternative via copie du dump..."
    docker cp "backup-client:${DUMP_FILE}" /tmp/restore.dump
    docker cp /tmp/restore.dump db-primary:/tmp/restore.dump
    docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-secretpassword}" db-primary sh -c "
        dropdb -U app --if-exists appdb && \
        createdb -U app appdb && \
        pg_restore -U app -d appdb /tmp/restore.dump
    "
    rm -f /tmp/restore.dump
}

log "Redémarrage des serveurs web..."
docker start web1 web2

log "Vérification post-restauration..."
sleep 5
curl -sf http://localhost:8080/ | head -20

log "=== Restauration terminée ==="
docker exec backup-client rm -rf "${RESTORE_DIR}" 2>/dev/null || true
