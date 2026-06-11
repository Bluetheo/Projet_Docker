FROM alpine:3.21

RUN apk add --no-cache \
    restic \
    openssh-client \
    postgresql16-client \
    bash \
    dcron \
    curl

COPY backup.sh /usr/local/bin/backup.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/backup.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
