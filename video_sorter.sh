#!/bin/bash

# --- Config ---

# Paths can be overridden from the environment (the tests do this)
: "${ORIGIN_DIR:=/Users/nick/Torrent/completed_downloads}"
: "${TV_DESTINATION:=/Volumes/Media/TV Shows}"
: "${MOVIE_DESTINATION:=/Volumes/Media/New Movies}"
PLEX_IP="192.168.1.184"
PLEX_TOKEN=""  # set in config.local.sh (gitignored); see config.local.sh.example
PLEX_TV_SECTION=3
PLEX_MOVIE_SECTION=1
MIN_SIZE_BYTES=$((10 * 1024 * 1024))  # 10MB — skip tiny clips (short cartoons can be ~30MB)
# A download is only processed once nothing in it has changed for this long.
# qBittorrent moves finished files into ORIGIN_DIR one by one; a move keeps the
# old mtime but updates ctime (and the folder's ctime), so ctime is what we watch.
: "${SETTLE_SECONDS:=300}"
: "${PIDFILE:=/tmp/video_sorter.pid}"

CONFIG_FILE="${VIDEO_SORTER_CONFIG:-$(cd "$(dirname "$0")" && pwd)/config.local.sh}"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# --- Helpers ---

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

refresh_plex() {
  local section_id="$1" library_name="$2"
  if [ -z "$PLEX_TOKEN" ]; then
    log "└─ Plex: no PLEX_TOKEN (missing ${CONFIG_FILE}?); skipped ${library_name} refresh"
    return
  fi
  local url="http://${PLEX_IP}:32400/library/sections/${section_id}/refresh?X-Plex-Token=${PLEX_TOKEN}"
  if curl -sf --max-time 5 "$url" > /dev/null; then
    log "└─ Plex: refreshed ${library_name} library"
  else
    log "└─ Plex: failed to refresh ${library_name} library"
  fi
}

# Seconds since anything in the entry (itself, files, subfolders) last changed
seconds_since_last_change() {
  local newest
  newest=$(find "$1" -exec stat -f %c {} + 2>/dev/null | sort -n | tail -1)
  echo $(( $(date +%s) - ${newest:-0} ))
}

# A sample has the word "sample" in its path (file or folder name), or is under MIN_SIZE_BYTES
is_sample() {
  local file="$1" rel size
  rel="${file#${ORIGIN_DIR}/}"
  shopt -s nocasematch
  if [[ "$rel" =~ (^|[^[:alpha:]])sample([^[:alpha:]]|$) ]]; then
    shopt -u nocasematch
    return 0
  fi
  shopt -u nocasematch
  size=$(stat -f%z "$file" 2>/dev/null || echo 0)
  [ "$size" -lt "$MIN_SIZE_BYTES" ]
}

find_or_create_show_folder() {
  local show_title="$1"
  local existing
  existing=$(ls -1d "${TV_DESTINATION}/"* 2>/dev/null | grep -i "/${show_title}$" | head -1)
  if [ -n "$existing" ]; then
    echo "$existing"
  else
    local new_folder="${TV_DESTINATION}/${show_title}"
    mkdir "$new_folder"
    echo "$new_folder"
  fi
}

find_or_create_season_folder() {
  local show_folder="$1" season="$2"
  local existing
  existing=$(ls -1d "${show_folder}/"* 2>/dev/null | grep -i "/[Ss]eason ${season}$" | head -1)
  if [ -n "$existing" ]; then
    echo "$existing"
  else
    local new_folder="${show_folder}/Season ${season}"
    mkdir "$new_folder"
    echo "$new_folder"
  fi
}

# --- Single-instance lock ---

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  log "QUITTING: VideoSorter instance already running; exiting now!"
  exit 0
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

# --- Main ---

for entry in "${ORIGIN_DIR}"/*; do
  [ -e "$entry" ] || continue

  entry_name=$(basename "$entry")
  dot_file="${ORIGIN_DIR}/.${entry_name}"

  [ -f "$dot_file" ] && continue

  # Still downloading / still being moved in? Leave it for a later run.
  [ "$(seconds_since_last_change "$entry")" -lt "$SETTLE_SECONDS" ] && continue

  # Collect video files, skipping samples
  declare -a video_files=()
  if [ -f "$entry" ]; then
    if [[ "$entry" =~ \.(mkv|mp4|avi|m4v)$ ]] && ! is_sample "$entry"; then
      video_files+=("$entry")
    fi
  else
    while IFS= read -r -d '' file; do
      if ! is_sample "$file"; then
        video_files+=("$file")
      fi
    done < <(find "$entry" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" \) -print0 2>/dev/null)
  fi

  [ "${#video_files[@]}" -eq 0 ] && continue

  log "Files to process (${#video_files[@]}):"
  for f in "${video_files[@]}"; do
    log "    ${f#${ORIGIN_DIR}/}"
  done

  all_copied=1
  copied_movie=0
  copied_tv=0
  for video_file in "${video_files[@]}"; do
    filename=$(basename "$video_file")

    # Detect TV show via SxxExx pattern (also year-based seasons, e.g. S1952E08)
    if [[ "$filename" =~ [Ss]([0-9]{2,4})[[:space:]]*[Ee][0-9]{2,3} ]]; then
      season="${BASH_REMATCH[1]}"
      # Extract show title: everything before the SxxExx, minus separators (" - ", ".", "_")
      show_title=$(echo "$filename" | sed -E 's/[[:space:]._-]*[Ss][0-9]{2,4}[[:space:]]*[Ee][0-9]{2,3}.*//')

      log "┌─ COPYING ───────────────────────────────────────────────────"
      log "│  FROM: ${video_file#${ORIGIN_DIR}/}"

      show_folder=$(find_or_create_show_folder "$show_title")
      season_folder=$(find_or_create_season_folder "$show_folder" "$season")
      destination="${season_folder}"
    else
      log "┌─ COPYING ───────────────────────────────────────────────────"
      log "│  FROM: ${video_file#${ORIGIN_DIR}/}"
      destination="${MOVIE_DESTINATION}"
    fi

    log "│    TO: ${destination}/"

    target="${destination}/${filename}"
    if [ -f "$target" ] && [ "$(stat -f%z "$target")" = "$(stat -f%z "$video_file")" ]; then
      log "└─ already on the NAS at the same size; skipped"
    elif [ -n "$destination" ] && [ -d "$destination" ] && cp "$video_file" "${destination}/"; then
      log "└─ copied"
      osascript -e "display notification \"Copied ${filename}\" with title \"Video Sorter\"" 2>/dev/null &
      if [ "$destination" = "$MOVIE_DESTINATION" ]; then copied_movie=1; else copied_tv=1; fi
    else
      log "└─ ERROR: copy failed for ${filename}"
      all_copied=0
    fi
  done

  # Only mark the download done once every video in it made it across;
  # otherwise the next run retries the whole thing.
  if [ "$all_copied" -eq 1 ]; then
    touch "$dot_file"
    log "marked as processed: .${entry_name}"
  else
    log "NOT marked as processed (a copy failed; will retry): ${entry_name}"
  fi
  [ "$copied_movie" -eq 1 ] && refresh_plex "$PLEX_MOVIE_SECTION" "movies_unwatched"
  [ "$copied_tv" -eq 1 ] && refresh_plex "$PLEX_TV_SECTION" "tv_shows"
done

log "QUITTING: done"
