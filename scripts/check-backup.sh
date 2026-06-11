#!/bin/bash
set -euo pipefail

echo "=== Test SSH (optionnel) ==="
if docker exec backup-client ssh \
    -i /root/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=accept-new \
    -o BatchMode=yes \
    backup@backup-server "echo SSH OK" 2>/dev/null; then
    echo "SSH : OK"
else
    echo "SSH : indisponible (les sauvegardes utilisent le volume partagé)"
fi

echo ""
echo "=== Snapshots Restic ==="
docker exec backup-client restic snapshots

echo ""
echo "=== Fichiers de staging ==="
docker exec backup-client ls -la /backups/staging/ 2>/dev/null || echo "(vide pour l'instant)"
