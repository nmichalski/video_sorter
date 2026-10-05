#!/bin/bash

# Removes dot-file markers from completed_downloads when the source no longer exists.

ORIGIN_DIR="/Users/nick/Torrent/completed_downloads"
PIDFILE="/tmp/dot_file_cleanup.pid"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  log "QUITTING: DotFileCleanup instance already running; exiting now!"
  exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

for dot_file in "${ORIGIN_DIR}"/.*; do
  [ -f "$dot_file" ] || continue

  dot_name=$(basename "$dot_file")
  source_name="${dot_name#.}"
  source_path="${ORIGIN_DIR}/${source_name}"

  if [ ! -e "$source_path" ]; then
    log "deleting: ${dot_file}"
    rm -f "$dot_file"
  fi
done

log "QUITTING: done"
