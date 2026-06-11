FROM alpine:3.21

RUN apk add --no-cache \
    openssh \
    restic \
    bash \
    shadow

RUN adduser -D -h /home/backup -s /bin/sh backup \
    && mkdir -p /backups/restic-repo /var/run/sshd /home/backup/.ssh /shared \
    && chmod 700 /home/backup/.ssh \
    && chown -R backup:backup /backups /home/backup

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

VOLUME ["/backups", "/shared"]

ENTRYPOINT ["/entrypoint.sh"]
