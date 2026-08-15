FROM alpine:3.20

RUN apk add --no-cache zip bash coreutils tzdata dcron curl unzip ca-certificates \
    && curl -fsSL https://rclone.org/install.sh | bash \
    && apk del curl unzip \
    && rm -rf /var/cache/apk/*

WORKDIR /app

COPY rclone_sync.sh /app/rclone_sync.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /app/rclone_sync.sh /entrypoint.sh

# Standard-Zeitzone, wird via docker-compose überschrieben
ENV TZ=Europe/Vienna
ENV RCLONE_CONFIG=/config/rclone.conf

ENTRYPOINT ["/entrypoint.sh"]
