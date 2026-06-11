#!/bin/bash
set -euo pipefail

mkdir -p /backups/restic-repo /shared /home/backup/.ssh /var/run/sshd

if [ ! -f /shared/id_ed25519 ]; then
    echo "Génération de la paire de clés SSH partagée..."
    ssh-keygen -t ed25519 -f /shared/id_ed25519 -N "" -C "backup@projet-b2"
    chmod 600 /shared/id_ed25519
    chmod 644 /shared/id_ed25519.pub
fi

cp /shared/id_ed25519.pub /home/backup/.ssh/authorized_keys
chown -R backup:backup /home/backup /backups
chmod 755 /home/backup
chmod 700 /home/backup/.ssh
chmod 600 /home/backup/.ssh/authorized_keys

mkdir -p /backups/staging

cat > /etc/ssh/sshd_config <<'SSHD'
Port 22
ListenAddress 0.0.0.0
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
UsePAM no
StrictModes no
AuthorizedKeysFile /home/backup/.ssh/authorized_keys
AllowUsers backup
Subsystem sftp /usr/lib/ssh/sftp-server
SSHD

ssh-keygen -A
/usr/sbin/sshd -t
exec /usr/sbin/sshd -D -e
