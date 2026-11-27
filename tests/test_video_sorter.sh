#!/bin/bash
# Behavior tests for video_sorter.sh. Run: tests/test_video_sorter.sh
# Each test builds a throwaway completed_downloads + destination tree, runs the
# real script against it, and checks what ended up on disk.

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/video_sorter.sh"
PASS=0
FAIL=0

setup() {
  T=$(mktemp -d)
  mkdir -p "$T/downloads" "$T/tv" "$T/movies" "$T/bin"
  # Stub out macOS banners and Plex calls
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/osascript"
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/curl"
  chmod +x "$T/bin/"*
}

teardown() {
  chmod -R u+w "$T" 2>/dev/null
  rm -rf "$T"
}

# 11MB sparse file (above the 10MB sample threshold)
make_video() {
  mkdir -p "$(dirname "$1")"
  dd if=/dev/zero of="$1" bs=1 count=0 seek=11534336 2>/dev/null
}

run_sorter() {
  # $1 = settle window in seconds
  PATH="$T/bin:$PATH" \
  ORIGIN_DIR="$T/downloads" TV_DESTINATION="$T/tv" MOVIE_DESTINATION="$T/movies" \
  PIDFILE="$T/sorter.pid" VIDEO_SORTER_CONFIG=/dev/null SETTLE_SECONDS="$1" \
    "$SCRIPT" > "$T/run.log" 2>&1
}

check() {
  local desc="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1)); echo "  ok   - $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $desc"; sed 's/^/         /' "$T/run.log"
  fi
}

echo "a download folder that changed within the settle window is left alone"
setup
make_video "$T/downloads/Shrek 4 Pack/Shrek 2001.mkv"
make_video "$T/downloads/Shrek 4 Pack/Shrek 2 2004.mkv"
run_sorter 300
check "no movies copied yet" test -z "$(ls -A "$T/movies")"
check "folder not marked as processed" test ! -e "$T/downloads/.Shrek 4 Pack"
teardown

echo "a settled download folder has every video copied, then is marked processed"
setup
make_video "$T/downloads/Shrek 4 Pack/Shrek 2001.mkv"
make_video "$T/downloads/Shrek 4 Pack/Shrek 2 2004.mkv"
make_video "$T/downloads/Shrek 4 Pack/Shrek The Third 2007.mkv"
make_video "$T/downloads/Shrek 4 Pack/Shrek Forever After 2010.mkv"
run_sorter 0
check "all four movies copied" test "$(ls "$T/movies" | wc -l | tr -d ' ')" = 4
check "folder marked as processed" test -e "$T/downloads/.Shrek 4 Pack"
teardown

echo "a file moved late into an otherwise settled folder holds the whole folder back"
setup
make_video "$T/downloads/Show S01/Show S01E01.mkv"
make_video "$T/staging/Show S01E02.mkv"
touch -t 202001010000 "$T/staging/Show S01E02.mkv"   # finished long ago, as qBittorrent leaves it
sleep 3                                              # E01 is now older than the 2s window
mv "$T/staging/Show S01E02.mkv" "$T/downloads/Show S01/"
run_sorter 2
check "no episodes copied while the folder is still changing" test ! -d "$T/tv/Show"
check "folder not marked as processed" test ! -e "$T/downloads/.Show S01"
teardown

echo "a recently written loose video file is left alone; once settled it is copied"
setup
make_video "$T/downloads/Loose Movie 2020.mkv"
run_sorter 300
check "not copied while recent" test ! -e "$T/movies/Loose Movie 2020.mkv"
check "not marked while recent" test ! -e "$T/downloads/.Loose Movie 2020.mkv"
run_sorter 0
check "copied once settled" test -e "$T/movies/Loose Movie 2020.mkv"
check "marked once settled" test -e "$T/downloads/.Loose Movie 2020.mkv"
teardown

echo "if any copy in a folder fails, the folder is not marked, so the next run retries it"
setup
make_video "$T/downloads/Mixed Pack/Some Movie 2019.mkv"
make_video "$T/downloads/Mixed Pack/Show S02E01.mkv"
chmod a-w "$T/tv"            # TV destination unwritable -> episode copy fails
run_sorter 0
check "folder not marked after a failed copy" test ! -e "$T/downloads/.Mixed Pack"
chmod u+w "$T/tv"
run_sorter 0
check "episode copied on the retry" test -e "$T/tv/Show/Season 02/Show S02E01.mkv"
check "movie present after the retry" test -e "$T/movies/Some Movie 2019.mkv"
check "folder marked after the retry succeeds" test -e "$T/downloads/.Mixed Pack"
teardown

echo "a retry does not re-copy files already on the NAS at the same size"
setup
make_video "$T/downloads/Mixed Pack/Some Movie 2019.mkv"
make_video "$T/downloads/Mixed Pack/Show S02E01.mkv"
chmod a-w "$T/tv"
run_sorter 0
touch -t 202001010000 "$T/movies/Some Movie 2019.mkv"   # stamp the copy from the first run
chmod u+w "$T/tv"
run_sorter 0
check "movie from the first run left untouched" \
  test "$(stat -f %m "$T/movies/Some Movie 2019.mkv")" = "$(touch -t 202001010000 "$T/ref" && stat -f %m "$T/ref")"
check "missing episode copied" test -e "$T/tv/Show/Season 02/Show S02E01.mkv"
check "folder marked" test -e "$T/downloads/.Mixed Pack"
teardown

echo "a same-named file of a different size on the NAS is replaced"
setup
make_video "$T/downloads/Some Movie 2019.mkv"
echo "truncated" > "$T/movies/Some Movie 2019.mkv"
run_sorter 0
check "NAS copy now matches the download" \
  test "$(stat -f %z "$T/movies/Some Movie 2019.mkv")" = "$(stat -f %z "$T/downloads/Some Movie 2019.mkv")"
teardown

echo "TV episodes still sort into Show/Season folders"
setup
make_video "$T/downloads/The Show S03E07 1080p.mkv"
run_sorter 0
check "episode in The Show/Season 03" test -e "$T/tv/The Show/Season 03/The Show S03E07 1080p.mkv"
teardown

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
