#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT_DIR}"

echo "=== Réparation et redémarrage des sauvegardes ==="

docker compose stop backup-client backup-server 2>/dev/null || true
docker compose rm -f backup-client backup-server 2>/dev/null || true

docker volume ls -q --filter name=backup-ssh-keys | xargs -r docker volume rm

docker compose up -d --build backup-server backup-client

echo "Forcer une sauvegarde immédiate..."
sleep 5
docker exec backup-client /usr/local/bin/backup.sh || true

echo "Attente (20s)..."
sleep 20

if ! docker compose ps backup-client | grep -q "Up"; then
    echo "ERREUR: backup-client arrêté. Logs :"
    docker logs backup-client 2>&1 | tail -30
    exit 1
fi

./scripts/check-backup.sh
