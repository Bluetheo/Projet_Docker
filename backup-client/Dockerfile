FROM alpine:3.21

RUN apk add --no-cache \
    restic \
    openssh-client \
    postgresql16-client \
    bash \
    curl

RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

COPY backup-client/backup.sh /usr/local/bin/backup.sh
COPY backup-client/entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/backup.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
