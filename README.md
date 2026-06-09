# 4chan Thread Archiver

Self-contained local archiver for 4chan threads. Downloads every image at full quality and generates a single HTML file that works completely offline.

## Requirements

- Windows with PowerShell 5.1+ (included in Windows 10/11)

## Quick Start

### Single thread

```
archive.bat https://boards.4chan.org/g/thread/12345678
```

### Interactive mode (paste multiple URLs)

```
archive-interactive.bat
```

### PowerShell directly

```powershell
.\archive.ps1 "https://boards.4chan.org/g/thread/12345678"
```

### List archived threads

```
list-archives.bat
```

### Refresh UI on all archives

If you update the tool and want existing archives to use the latest HTML/template:

```
update-html.bat
```

Or refresh a single archive:

```powershell
.\update-html.ps1 -ArchiveName "g_12345678"
```

This regenerates `thread.html` from the saved `thread.json` without re-downloading anything. Useful for threads that are no longer available online.

### Auto-update all live threads

Fetch fresh data from 4chan for every archive, download new posts/images, and regenerate HTML:

```
update-all.bat
```

- Threads that are still alive get new posts downloaded
- Threads that have been removed (404) are marked as REMOVED but their local files are preserved
- Threads with no changes are skipped
- Rate limited to respect 4chan API rules

## Supported URL formats

All of these work:

```
https://boards.4chan.org/g/thread/12345678
https://boards.4channel.org/a/thread/12345678
https://4chan.org/g/thread/12345678
https://a.4cdn.org/g/thread/12345678.json
```

## Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `Url` | *(required)* | Thread URL to archive |
| `-Concurrency` | `4` | Number of parallel downloads (1-16) |

Example with more parallelism:

```powershell
.\archive.ps1 "https://boards.4chan.org/g/thread/12345678" -Concurrency 8
```

## Output structure

```
archives/
  g_12345678/
    thread.html          <- open this in a browser
    thread.json          <- cached API response for efficient updates
    images/
      1234567890123.jpg  <- full quality image
      1234567890123s.jpg <- thumbnail
      ...
```

The `thread.html` file is fully self-contained. It references images from the local `images/` folder, so it works completely offline with no internet connection needed.

## Updating archives

If a thread is already archived, the tool will ask whether to update:

```
Thread already archived at: archives/g_12345678
Update with new posts? (Y/n)
```

Press Enter (or `y`) to fetch new posts. Only images from new posts are downloaded -- existing images are never re-downloaded. The HTML is regenerated with all posts.

The cached `thread.json` is used to detect which posts are new, making updates fast even for large threads.

## Features

- **Full quality images** - original files as uploaded, not compressed
- **Offline HTML** - single file opens in any browser, no server needed
- **Parallel downloads** - 4 concurrent downloads by default, configurable
- **Thread updates** - fetch only new posts and images, no redundant downloads
- **4chan-style rendering** - authentic Yotsuba B theme, vertical post layout, greentext, quote links, post IDs, capcodes
- **Dynamic Backlinks** - posts feature clickable links to replies that quote them (e.g. `>>950117370`), supporting standard hover previews and click-to-scroll navigation
- **Quote hover preview** - hover over any `>>12345` link or backlink to see a floating preview of that post
- **Two image viewing modes** - click thumbnail for fullscreen overlay, or click `[+]` next to filename to expand inline (like real 4chan)
- **Drag-to-resize images** - expanded images can be resized by dragging the bottom-right corner (old reddit style)
- **Improved Layout toggle** - switch between List (authentic single column, no staircase float bugs) and Grid (media-priority responsive card grid, auto-scrollable messages, full-width OP spanning)
- **Click to zoom** - click any thumbnail for full-size overlay
- **Quote navigation** - click quote links to jump to referenced posts
- **Idempotent** - skip already-downloaded files automatically

## Notes

- Respects 4chan API rate limits via parallel connection cap
- Deleted threads or 404s will show an error and clean up the folder (new archives only; existing archives are preserved on update failure)
- Thumbnails are downloaded alongside full images for fast browsing
