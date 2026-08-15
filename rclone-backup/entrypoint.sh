#!/bin/bash
set -uo pipefail

CRON_SCHEDULE="${CRON_SCHEDULE:-0 2 * * *}"

echo "[entrypoint] Richte Cron-Job ein: ${CRON_SCHEDULE} /app/rclone_sync.sh"

: "${RCLONE_REMOTE_NAME:?FEHLER: Umgebungsvariable RCLONE_REMOTE_NAME ist nicht gesetzt (siehe .env)}"
: "${RCLONE_REMOTE_DIR:?FEHLER: Umgebungsvariable RCLONE_REMOTE_DIR ist nicht gesetzt (siehe .env)}"

{
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    echo "HOME=${HOME:-/root}"
    echo "RCLONE_CONFIG=${RCLONE_CONFIG:-/config/rclone.conf}"
    echo "RCLONE_REMOTE_NAME=${RCLONE_REMOTE_NAME}"
    echo "RCLONE_REMOTE_DIR=${RCLONE_REMOTE_DIR}"
    echo "${CRON_SCHEDULE} /app/rclone_sync.sh >> /logs/cron.log 2>&1"
} > /etc/crontabs/root

if [ "${RUN_ON_START:-false}" = "true" ]; then
    echo "[entrypoint] RUN_ON_START=true -> führe Backup jetzt einmalig aus"
    /app/rclone_sync.sh || true
fi

echo "[entrypoint] Starte crond im Vordergrund"
exec crond -f -l 8
