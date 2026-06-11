#!/bin/bash
set -uo pipefail

mkdir -p /root/.ssh /backups/staging /backups/restic-repo /var/log
chmod 700 /root/.ssh

echo "Attente des clés SSH partagées..."
for i in $(seq 1 30); do
    [ -f /shared/id_ed25519 ] && break
    sleep 2
done

if [ -f /shared/id_ed25519 ]; then
    cp /shared/id_ed25519 /root/.ssh/id_ed25519
    cp /shared/id_ed25519.pub /root/.ssh/id_ed25519.pub
    chmod 600 /root/.ssh/id_ed25519
    chmod 644 /root/.ssh/id_ed25519.pub
    cat > /root/.ssh/config <<'EOF'
Host backup-server
    HostName backup-server
    User backup
    IdentityFile /root/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    BatchMode yes
EOF
    chmod 600 /root/.ssh/config
fi

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/restic-repo}"

echo "Lancement de la première sauvegarde..."
/usr/local/bin/backup.sh || true

echo "Planification : sauvegarde toutes les 5 minutes..."
while true; do
    sleep 300
    /usr/local/bin/backup.sh || true
done
