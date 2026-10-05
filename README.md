# video_sorter

Auto-sorts Movies & TV Shows from qBittorrent's `completed_downloads` folder into the Plex
`TV Shows` and `New Movies` folders, then triggers a Plex library refresh.

TV Shows are sorted into folders by Title and then Season, detected from an `SxxEyy` tag.
Year-based seasons (e.g. `S1952E08`) are supported.

## Scripts

| Script | Status |
|---|---|
| `video_sorter.sh` | **Active.** Run by cron every minute. |
| `dot_file_cleanup.sh` | **Active.** Run by cron every minute; removes stale dot-file markers. |
| `video_sorter.rb`, `dot_file_cleanup.rb` | **Defunct.** Superseded by the `.sh` versions; kept for reference only. |

## Setup

```sh
cp config.local.sh.example config.local.sh   # then set PLEX_TOKEN (file is gitignored)
```

crontab:
```
*  *  *  *  *  /Users/nick/Code/video_sorter/video_sorter.sh >> /tmp/video_sorter.log 2>&1
*  *  *  *  *  /Users/nick/Code/video_sorter/dot_file_cleanup.sh >> /tmp/dot_file_cleanup.log 2>&1
```

## Notes

- Video files are **copied**, not moved, so the torrent can keep seeding.
- After an item is copied, a dot file (`.<name>`) is created next to it in `completed_downloads`;
  that item is never processed again while the dot file exists.
- Files with the word "sample" in their path, or under 10MB, are skipped as samples.
