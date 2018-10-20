#!/bin/bash

# Set Finder label color
if [ $# -lt 2 ]; then
  echo "USAGE: change_file_label.sh [0-7] file1 [file2] ..."
  echo "Sets the Finder label (color) for files"
  echo "Default colors:"
  echo " 0  No color"
  echo " 1  Orange"
  echo " 2  Red"
  echo " 3  Yellow"
  echo " 4  Blue"
  echo " 5  Purple"
  echo " 6  Green"
  echo " 7  Gray"
else
  osascript - "$@" << EOF
  on run argv
      set labelIndex to (item 1 of argv as number)
      repeat with i from 2 to (count of argv)
        tell application "Finder"
            set theFile to POSIX file (item i of argv) as alias
            set label index of theFile to labelIndex
        end tell
      end repeat
  end run
EOF
fi
