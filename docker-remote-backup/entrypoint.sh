#!/usr/bin/env bash
set -uo pipefail

SRC_DIR="/source"
BACKUP_NAME="${BACKUP_NAME:-docker-backup}"
REMOTE_DIR="${REMOTE_DIR:}"
BACKUP_TIME="${BACKUP_TIME:-02:30}"
RUN_ON_START="${RUN_ON_START:-false}"

log() { echo "[$(date '+%F %T')] $*"; }

ping_hc() {
  [[ -n "${HEALTHCHECK_URL:-}" ]] || return 0
  curl -fsS -m 10 --retry 3 "${HEALTHCHECK_URL}${1:-}" >/dev/null 2>&1 || true
}

run_backup() {
  local failed=0 count=0 name rc dir ts run_name STAGING
  ts="$(date +%Y-%m-%d_%H%M%S)"
  run_name="${BACKUP_NAME}_${ts}"
  STAGING="/staging/${run_name}"
  ping_hc /start

  rm -rf /staging/*          # clear leftovers from any interrupted run
  mkdir -p "$STAGING"

  shopt -s nullglob
  for dir in "$SRC_DIR"/*/; do
    name="$(basename "$dir")"
    count=$((count + 1))
    log "Archiving ${name}"
    rc=0
    tar -C "$dir" -czf "$STAGING/${name}.partial" . || rc=$?
    # tar exit 1 = "file changed as we read it" -> warning only; >=2 is a real error
    if (( rc > 1 )); then
      log "ERROR: tar failed for ${name} (exit ${rc})"
      rm -f "$STAGING/${name}.partial"
      failed=1
      continue
    fi
    (( rc == 1 )) && log "WARN: ${name} changed while being archived"
    mv "$STAGING/${name}.partial" "$STAGING/${name}.tar.gz"
  done

  if (( count == 0 )); then
    log "ERROR: nothing mounted under ${SRC_DIR}/"
    ping_hc /fail
    return 1
  fi

  log "Uploading to Proton Drive: ${REMOTE_DIR}/${run_name}"
  if ! proton-drive filesystem upload "$STAGING" "$REMOTE_DIR" \
        --folder-conflict-strategy merge \
        --file-conflict-strategy create-new-revision; then
    log "ERROR: upload failed (is the session still valid? re-run 'auth login')"
    failed=1
  fi

  rm -rf "$STAGING"

  if (( failed )); then
    ping_hc /fail
    return 1
  fi
  log "Backup finished OK"
  ping_hc
}

seconds_until() {
  local now target
  now="$(date +%s)"
  target="$(date -d "today ${BACKUP_TIME}" +%s)"
  (( target <= now )) && target="$(date -d "tomorrow ${BACKUP_TIME}" +%s)"
  echo $(( target - now ))
}

# Any arguments = run that command instead (e.g. `proton-drive auth login`)
if [[ $# -gt 0 ]]; then
  exec "$@"
fi

trap 'log "Shutting down"; exit 0' TERM INT

if [[ "$RUN_ON_START" == "true" ]]; then
  run_backup || true
fi

while true; do
  wait_s="$(seconds_until)"
  log "Next backup at ${BACKUP_TIME} (in ${wait_s}s)"
  sleep "$wait_s" &
  wait $!
  run_backup || true
done
