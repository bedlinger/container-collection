#!/usr/bin/env bash
set -uo pipefail

SRC_DIR="/source"
BACKUP_NAME="${BACKUP_NAME:-docker-backup}"
REMOTE_DIR="${REMOTE_DIR:-/my-files/Backups}"
BACKUP_TIME="${BACKUP_TIME:-02:30}"
RUN_ON_START="${RUN_ON_START:-false}"

NTFY_URL="${NTFY_URL:-}"
NTFY_USER="${NTFY_USER:-}"
NTFY_PASSWORD="${NTFY_PASSWORD:-}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
HOST="$(hostname)"

log() { echo "[$(date '+%F %T')] $*"; }

# notify <title> <priority 1-5> <tags> <message>   (no-op unless NTFY_URL + NTFY_TOPIC are set)
notify() {
  [[ -n "$NTFY_URL" && -n "$NTFY_TOPIC" ]] || return 0
  local title="$1" prio="$2" tags="$3" msg="$4" auth=""
  if [[ -n "$NTFY_USER" ]]; then
    auth="header = \"Authorization: Basic $(printf '%s:%s' "$NTFY_USER" "$NTFY_PASSWORD" | base64 -w0)\""
  fi
  # credentials go to curl via stdin config, so they never show up in the process list
  if ! printf '%s\n' "$auth" | curl -fsS -m 15 --retry 2 -K - \
        -H "Title: ${title}" -H "Priority: ${prio}" -H "Tags: ${tags}" \
        -d "$msg" "${NTFY_URL%/}/${NTFY_TOPIC}" >/dev/null; then
    log "WARN: could not send ntfy notification"
  fi
}

run_backup() {
  local failed=0 count=0 name rc dir ts run_name STAGING failed_names="" size="" ok_count=0 auth_failed=0 out_file upload_rc
  ts="$(date +%Y-%m-%d_%H%M%S)"
  run_name="${BACKUP_NAME}_${ts}"
  STAGING="/staging/${run_name}"

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
      failed_names+=" ${name}"
      continue
    fi
    (( rc == 1 )) && log "WARN: ${name} changed while being archived"
    mv "$STAGING/${name}.partial" "$STAGING/${name}.tar.gz"
    ok_count=$((ok_count + 1))
  done

  if (( count == 0 )); then
    log "ERROR: nothing mounted under ${SRC_DIR}/"
    notify "Backup FAILED on ${HOST}" 4 "x,floppy_disk" "Nothing is mounted under ${SRC_DIR}/, so there was nothing to back up."
    return 1
  fi

  size="$(du -sh "$STAGING" | cut -f1)"
  log "Uploading to Proton Drive: ${REMOTE_DIR}/${run_name}"
  out_file="$(mktemp)"
  proton-drive filesystem upload "$STAGING" "$REMOTE_DIR" \
      --folder-conflict-strategy merge \
      --file-conflict-strategy create-new-revision 2>&1 | tee "$out_file"
  upload_rc=${PIPESTATUS[0]}
  if (( upload_rc != 0 )); then
    failed=1
    failed_names+=" (upload)"
    # Heuristic: the CLI's exact wording isn't documented, so match common auth/session phrases
    if grep -qiE 'unauthori[sz]ed|not (logged|signed)|log ?in|sign[ -]?in|authenticat|session|expired|invalid (token|credential)|\b401\b' "$out_file"; then
      auth_failed=1
      log "ERROR: Proton session invalid/expired - run: docker compose run --rm proton-backup proton-drive auth login"
    else
      log "ERROR: upload failed (exit ${upload_rc})"
    fi
  fi
  rm -f "$out_file"

  rm -rf "$STAGING"

  if (( failed )); then
    if (( auth_failed )); then
      notify "Proton Drive login expired on ${HOST}" 5 "key,warning" \
        "The Proton Drive CLI needs to be re-authenticated. No backups are uploaded until you run: docker compose run --rm proton-backup proton-drive auth login"
    else
      notify "Backup FAILED on ${HOST}" 4 "x,floppy_disk" \
        "Problems with:${failed_names}. ${ok_count}/${count} archives were created. See 'docker logs proton-backup'."
    fi
    return 1
  fi
  log "Backup finished OK"
  notify "Backup OK on ${HOST}" 3 "white_check_mark,floppy_disk" \
    "${ok_count} archives (${size}) uploaded to ${REMOTE_DIR}/${run_name}"
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
