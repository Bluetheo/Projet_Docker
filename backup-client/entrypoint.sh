#!/bin/bash
set -euo pipefail

mkdir -p /root/.ssh /var/log
chmod 700 /root/.ssh

if [ -f /keys/id_ed25519 ]; then
    cp /keys/id_ed25519 /root/.ssh/id_ed25519
    cp /keys/id_ed25519.pub /root/.ssh/id_ed25519.pub
    chmod 600 /root/.ssh/id_ed25519
    chmod 644 /root/.ssh/id_ed25519.pub
fi

cat > /root/.ssh/config <<EOF
Host backup-server
    HostName backup-server
    User backup
    StrictHostKeyChecking accept-new
    IdentityFile /root/.ssh/id_ed25519
EOF
chmod 600 /root/.ssh/config

echo "Attente du serveur de sauvegarde..."
until ssh -o ConnectTimeout=5 backup@backup-server "echo ok" 2>/dev/null; do
    sleep 3
done

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-sftp:backup@backup-server:/backups/restic-repo}"

echo "*/5 * * * * /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" | crontab -

echo "Lancement de la première sauvegarde..."
/usr/local/bin/backup.sh || true

echo "Démarrage du cron (toutes les 5 minutes)..."
exec crond -f -l 2
