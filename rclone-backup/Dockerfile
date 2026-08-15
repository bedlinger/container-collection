FROM alpine:3.20

RUN apk add --no-cache rclone zip bash coreutils tzdata dcron

WORKDIR /app

COPY rclone_sync.sh /app/rclone_sync.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /app/rclone_sync.sh /entrypoint.sh

ENV TZ=Europe/Vienna
ENV RCLONE_CONFIG=/config/rclone.conf

ENTRYPOINT ["/entrypoint.sh"]
