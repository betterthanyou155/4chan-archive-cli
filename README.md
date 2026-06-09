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

Or run the PowerShell script directly:

```powershell
.\archive-interactive.ps1
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

- **Full quality images & videos** - downloads original attachments at full quality without compression
- **Offline HTML** - single file opens directly in any browser (works completely offline under `file://` protocol)
- **Parallel downloads** - concurrent file downloads with configurable limits (defaults to 4, supports 1-16)
- **Native Video Player Support** - WebM and MP4 files are rendered using a native HTML5 video player with playback controls, autoplay, loop, and auto-mute in both inline-expanded and fullscreen modes
- **Expand / Collapse All Images** - dedicated top-bar toggle button to expand or collapse all static image attachments inline simultaneously
- **Viewport Bounds Capping** - expanded images and videos are restricted to viewport dimensions (`90vw` and `80vh` max), scaling down proportionally to prevent screen overflow on initial expansion
- **Drag-to-Resize** - expanded images and video players can be resized dynamically via mouse dragging. The drag logic tracks aspect ratio calculations and respects viewport limits, completely preventing distortion or layout clipping
- **Dynamic Backlinks** - posts automatically parse quote mentions and render quote backlinks (e.g. `>>950117370`), supporting scroll-to-highlight navigation and quote hover previews
- **Quote Hover Previews** - hovering over quote links or backlinks displays a floating preview of the referenced post
- **Authentic 4chan Yotsuba B Style** - renders threads with Yotsuba styling, vertical layouts, greentext, identity tripcodes, capcodes, and post headers
- **Improved Layout Toggle** - switch between List (authentic single column, resolves staircase floating layout bugs) and Grid (responsive layout cards, scroll-constrained comments, centered media)
- **Idempotent Downloads** - automatically skips already-downloaded files, ensuring fast and network-efficient updates
- **Transient Error Resilience** - exponential backoff request retries, modern connection timeouts, and dynamic API rate limiting to ensure reliable downloads


## Notes

- Respects 4chan API rate limits via parallel connection cap
- Deleted threads or 404s will show an error and clean up the folder (new archives only; existing archives are preserved on update failure)
- Thumbnails are downloaded alongside full images for fast browsing
