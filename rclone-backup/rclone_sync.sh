#!/bin/bash

set -uo pipefail

### ====== KONFIGURATION ======
REMOTE_NAME="${RCLONE_REMOTE_NAME:?FEHLER: Umgebungsvariable RCLONE_REMOTE_NAME ist nicht gesetzt}"

REMOTE_BASE_PATH="${RCLONE_REMOTE_DIR:?FEHLER: Umgebungsvariable RCLONE_REMOTE_DIR ist nicht gesetzt}"

#   {date}  -> aktuelles Datum, z.B. 20260814
#   {time}  -> aktuelle Uhrzeit, z.B. 153000
SYNC_PATHS=(
    "/data/vaultwarden|vaultwarden_{date}"
    "/data/trilium|trilium_{date}"
)

TMP_DIR="/tmp/rclone_zip_tmp"

LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/sync_$(date +%Y%m%d_%H%M%S).log"

LOGS_TO_KEEP=30

### ====== ENDE KONFIGURATION ======
mkdir -p "$LOG_DIR" "$TMP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if ! command -v rclone &> /dev/null; then
    log "FEHLER: rclone ist nicht installiert. Abbruch."
    exit 1
fi

if ! command -v zip &> /dev/null; then
    log "FEHLER: 'zip' ist nicht installiert."
    exit 1
fi

if ! rclone listremotes | grep -q "^${REMOTE_NAME}:$"; then
    log "FEHLER: Remote '${REMOTE_NAME}' wurde nicht in der rclone-Konfiguration gefunden."
    log "Verfügbare Remotes: $(rclone listremotes | tr '\n' ' ')"
    exit 1
fi

log "===== Starte Backup & Upload ====="
ERRORS=0
CURRENT_DATE="$(date +%Y%m%d)"
CURRENT_TIME="$(date +%H%M%S)"

for entry in "${SYNC_PATHS[@]}"; do
    LOCAL_PATH="${entry%%|*}"
    ZIP_NAME_RAW="${entry##*|}"

    if [ ! -d "$LOCAL_PATH" ]; then
        log "WARNUNG: Lokaler Ordner '$LOCAL_PATH' existiert nicht - wird übersprungen."
        ERRORS=$((ERRORS+1))
        continue
    fi

    ZIP_NAME="${ZIP_NAME_RAW//\{date\}/$CURRENT_DATE}"
    ZIP_NAME="${ZIP_NAME//\{time\}/$CURRENT_TIME}"
    ZIP_FILE="${TMP_DIR}/${ZIP_NAME}.zip"

    log "-> Zippe '$LOCAL_PATH' nach '$ZIP_FILE'"

    rm -f "$ZIP_FILE"

    FOLDER_NAME="$(basename "$LOCAL_PATH")"
    if (cd "$(dirname "$LOCAL_PATH")" && zip -r -q "$ZIP_FILE" "$FOLDER_NAME"); then
        log "   OK: Zip erstellt ($(du -h "$ZIP_FILE" | cut -f1))"
    else
        log "   FEHLER beim Zippen von '$LOCAL_PATH'."
        ERRORS=$((ERRORS+1))
        continue
    fi

    DEST="${REMOTE_NAME}:${REMOTE_BASE_PATH}"
    log "-> Lade '$ZIP_FILE' nach '$DEST' hoch"

    if rclone copy "$ZIP_FILE" "$DEST" --log-file="$LOG_FILE" --log-level INFO; then
        log "   OK: Upload erfolgreich."
        rm -f "$ZIP_FILE"
    else
        log "   FEHLER beim Upload von '$ZIP_FILE'. Datei bleibt lokal in $TMP_DIR erhalten."
        ERRORS=$((ERRORS+1))
    fi
done

log "===== Backup & Upload abgeschlossen ====="

if [ "$ERRORS" -gt 0 ]; then
    log "Es sind $ERRORS Fehler/Warnungen aufgetreten. Bitte Log prüfen: $LOG_FILE"
else
    log "Alle Ordner wurden erfolgreich gesichert und hochgeladen."
fi

if [ "$LOGS_TO_KEEP" -gt 0 ]; then
    ls -1t "${LOG_DIR}"/sync_*.log 2>/dev/null | tail -n +$((LOGS_TO_KEEP+1)) | xargs -r rm --
fi

exit $ERRORS
