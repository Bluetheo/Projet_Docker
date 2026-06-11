#!/bin/bash
set -euo pipefail

mkdir -p /home/backup/.ssh /backups/restic-repo
chmod 700 /home/backup/.ssh
chown -R backup:backup /home/backup /backups

if [ -f /keys/authorized_keys ]; then
    cp /keys/authorized_keys /home/backup/.ssh/authorized_keys
    chmod 600 /home/backup/.ssh/authorized_keys
    chown backup:backup /home/backup/.ssh/authorized_keys
fi

ssh-keygen -A
exec /usr/sbin/sshd -D -e
