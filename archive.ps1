param(
    [Parameter(Position=0)]
    [string]$Url,
    [ValidateRange(1,16)]
    [int]$Concurrency = 4
)

if (-not $Url) {
    Write-Host "`n  4chan Thread Archiver" -ForegroundColor Cyan
    Write-Host "  Paste a 4chan thread URL and press Enter.`n"
    $Url = Read-Host "URL"
    if (-not $Url) {
        Write-Host "No URL provided. Exiting."
        exit 0
    }
}

$ErrorActionPreference = "Stop"

# --- Parse URL ---
# Handles: boards.4chan.org, boards.4channel.org, 4chan.org, 4channel.org
# Also handles: a.4cdn.org/{board}/thread/{id}.json
if ($Url -match '(?:boards\.(?:4chan|4channel)\.org|(?:4chan|4channel)\.org|a\.4cdn\.org)/([a-z0-9]+)/thread/(\d+)') {
    $board = $Matches[1]
    $threadId = $Matches[2]
} else {
    Write-Host "ERROR: Invalid 4chan thread URL." -ForegroundColor Red
    Write-Host "Expected format: https://boards.4chan.org/{board}/thread/{id}"
    exit 1
}

$apiUrl = "https://a.4cdn.org/$board/thread/$threadId.json"
$imageBase = "https://i.4cdn.org/$board"

# --- Create folder structure ---
$archiveRoot = Join-Path $PSScriptRoot "archives"
$threadDir = Join-Path $archiveRoot "${board}_${threadId}"
$imgDir = Join-Path $threadDir "images"
$isUpdate = $false

if (Test-Path $threadDir) {
    Write-Host "Thread already archived at: $threadDir" -ForegroundColor Yellow
    $reply = Read-Host "Update with new posts? (Y/n)"
    if ($reply -match '^(n|no)$') {
        Write-Host "Aborted."
        exit 0
    }
    $isUpdate = $true
}

New-Item -ItemType Directory -Path $imgDir -Force | Out-Null

# --- Load existing post IDs for efficient updating ---
$existingPostIds = @{}
if ($isUpdate) {
    $savedJsonPath = Join-Path $threadDir "thread.json"
    if (Test-Path $savedJsonPath) {
        try {
            $savedThread = (Get-Content $savedJsonPath -Raw | ConvertFrom-Json)
            foreach ($p in $savedThread.posts) {
                $existingPostIds[$p.no] = $true
            }
            Write-Host "  Loaded $($existingPostIds.Count) existing posts from cache" -ForegroundColor DarkGray
        } catch {
            Write-Host "  Could not read cached thread.json, will re-download all" -ForegroundColor Yellow
        }
    }
}

# --- Fetch thread JSON ---
Write-Host "Fetching thread /$board/$threadId ..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -Headers @{ "User-Agent" = "4chan-archiver/1.0" }
    $thread = $response.Content | ConvertFrom-Json
} catch {
    Write-Host "ERROR: Failed to fetch thread. It may not exist or has been deleted." -ForegroundColor Red
    if (-not $isUpdate) {
        Remove-Item -Recurse -Force $threadDir
    }
    exit 1
}

$posts = $thread.posts
$op = $posts[0]

Write-Host "Found $($posts.Count) posts" -ForegroundColor Cyan

# --- Download images ---
$imageCount = 0
$failedImages = @()

# Collect all download tasks (full image + thumbnail per post)
$newPostCount = 0
$tasks = [System.Collections.ArrayList]::new()
foreach ($post in $posts) {
    $isNew = -not $existingPostIds.ContainsKey($post.no)
    if ($post.tim -and $post.ext -and -not $post.filedeleted) {
        $filename = "$($post.tim)$($post.ext)"
        $thumbFilename = "$($post.tim)s.jpg"

        # Only queue downloads for new posts or missing files
        if ($isNew -or -not (Test-Path (Join-Path $imgDir $filename))) {
            [void]$tasks.Add(@{
                Url  = "$imageBase/$filename"
                Dest = Join-Path $imgDir $filename
                Name = $filename
                Type = "image"
            })
            [void]$tasks.Add(@{
                Url  = "$imageBase/$thumbFilename"
                Dest = Join-Path $imgDir $thumbFilename
                Name = $thumbFilename
                Type = "thumb"
            })
        }
    }
    if ($isNew) { $newPostCount++ }
}

# Skip already-downloaded files
$pending = $tasks | Where-Object { -not (Test-Path $_.Dest) }
$skipped = $tasks.Count - $pending.Count

if ($isUpdate) {
    Write-Host "  $newPostCount new post(s) found" -ForegroundColor Cyan
}

if ($skipped -gt 0) {
    Write-Host "  Skipping $skipped already-downloaded files" -ForegroundColor DarkGray
}

if ($pending.Count -gt 0) {
    Write-Host "  Downloading $($pending.Count) files ($concurrency concurrent) ..." -ForegroundColor Cyan

    # --- Runspace pool for parallel downloads ---
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $concurrency)
    $pool.Open()

    $downloadScript = {
        param($Url, $Dest, $Timeout)
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "4chan-archiver/1.0")
            $wc.DownloadFile($Url, $Dest)
            return @{ Success = $true }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }

    $runspaces = [System.Collections.ArrayList]::new()
    $total = $pending.Count
    $completed = 0
    $failed = 0

    foreach ($task in $pending) {
        $ps = [PowerShell]::Create().AddScript($downloadScript).AddArgument($task.Url).AddArgument($task.Dest).AddArgument(30)
        $ps.RunspacePool = $pool

        [void]$runspaces.Add(@{
            Pipe   = $ps
            Handle = $ps.BeginInvoke()
            Task   = $task
        })
    }

    # Monitor completion
    while ($runspaces.Count -gt 0) {
        $done = @()
        for ($i = 0; $i -lt $runspaces.Count; $i++) {
            $rs = $runspaces[$i]
            if ($rs.Handle.IsCompleted) {
                $result = $rs.Pipe.EndInvoke($rs.Handle)
                $rs.Pipe.Dispose()
                $completed++

                if ($result -and $result[0].Success) {
                    if ($rs.Task.Type -eq "image") {
                        Write-Host "  [$completed/$total] $($rs.Task.Name)" -ForegroundColor Green
                    }
                } else {
                    $failed++
                    if ($rs.Task.Type -eq "image") {
                        $failedImages += $rs.Task.Name
                        $err = if ($result) { $result[0].Error } else { "unknown" }
                        Write-Host "  [$completed/$total] FAILED: $($rs.Task.Name) - $err" -ForegroundColor Red
                    }
                }

                $done += $i
            }
        }

        # Remove completed runspaces (reverse order to keep indices stable)
        for ($j = $done.Count - 1; $j -ge 0; $j--) {
            $runspaces.RemoveAt($done[$j])
        }

        if ($runspaces.Count -gt 0) {
            Start-Sleep -Milliseconds 200
        }
    }

    $pool.Close()
    $pool.Dispose()

    $imageCount = ($tasks | Where-Object { $_.Type -eq "image" -and (Test-Path $_.Dest) }).Count
} else {
    $imageCount = ($tasks | Where-Object { $_.Type -eq "image" }).Count
}

Write-Host "`nDownloaded $imageCount images ($($failedImages.Count) failed)" -ForegroundColor Cyan

# --- Build HTML ---
Write-Host "Generating HTML ..." -ForegroundColor Cyan

$boardTitle = if ($board -eq "po") { "/po/ - Papercraft & Origami" } else { "/$board/" }
$threadTitle = if ($op.sub) { $op.sub } else { "Thread #$threadId" }
$archivedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Escape HTML entities
function Escape-Html($text) {
    if (-not $text) { return "" }
    return $text.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;").Replace("'","&#39;")
}

# Convert 4chan comment HTML to display HTML (already mostly HTML, just clean up)
function Convert-Comment($com) {
    if (-not $com) { return "" }
    # Remove <wbr> tags (word break hints, not needed locally)
    $com = $com -replace '<wbr>', ''
    # Wrap greentext lines (lines starting with &gt; but not &gt;&gt;quote links)
    $lines = $com -split '<br\s*/?>'
    $processed = @()
    foreach ($line in $lines) {
        $trimmed = $line.TrimStart()
        if ($trimmed -match '^&gt;' -and $trimmed -notmatch '^&gt;&gt;\d+') {
            $processed += "<span class=`"greentext`">$line</span>"
        } else {
            $processed += $line
        }
    }
    return $processed -join '<br>'
}

$htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$(Escape-Html $threadTitle) - 4chan Archive</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    background: #FFFFEE;
    color: #800000;
    font-family: Arial, Helvetica, sans-serif;
    font-size: 13px;
    line-height: 1.5;
  }

  a { color: #FF0000; text-decoration: none; }
  a:hover { text-decoration: underline; }

  /* --- Board title bar --- */
  .board-banner {
    background: #EEF2FF;
    border-bottom: 1px solid #D6DAF0;
    padding: 6px 12px;
    font-size: 11px;
    color: #AF0A0F;
    text-align: center;
    margin-bottom: 8px;
  }
  .board-banner a { color: #AF0A0F; }
  .board-banner .board-label { font-weight: bold; font-size: 13px; }

  /* --- Archive notice --- */
  .archive-notice {
    background: #FFFFDD;
    border: 1px solid #DD8;
    padding: 6px 10px;
    margin: 0 0 10px 0;
    font-size: 11px;
    text-align: center;
    color: #880;
  }

  /* --- Container --- */
  .container {
    max-width: 900px;
    margin: 0 auto;
    padding: 0 10px;
  }

  /* --- OP post --- */
  .op-container {
    margin-bottom: 2px;
  }

  .op {
    background: #F0E0D0;
    border: 1px solid #D9BFB7;
    padding: 5px 10px;
    overflow: hidden;
  }

  .op .post-info {
    margin-bottom: 2px;
  }

  .op .file-info {
    margin-bottom: 4px;
  }

  .op .post-image {
    float: left;
    margin: 4px 20px 10px 0;
  }

  .op .post-image img {
    max-width: 400px;
    max-height: 400px;
    border: 0;
    cursor: pointer;
  }

  .op .post-message {
    overflow: hidden;
  }

  /* --- Thread replies area --- */
  .thread-replies {
    border-left: 0;
    margin: 0 0 10px 0;
    padding: 0 0 0 20px;
  }

  /* --- Reply post --- */
  .reply {
    background: #F0E0D0;
    border: 1px solid #D9BFB7;
    display: inline-block;
    max-width: 100%;
    vertical-align: top;
    margin: 2px 0;
    padding: 5px 8px;
    overflow: hidden;
  }

  .reply .post-image {
    float: left;
    margin: 4px 15px 4px 0;
  }

  .reply .post-image img {
    max-width: 250px;
    max-height: 250px;
    border: 0;
    cursor: pointer;
  }

  /* --- Post info line --- */
  .post-info {
    font-size: 13px;
    white-space: nowrap;
  }

  .post-subject {
    color: #0F0C5D;
    font-weight: bold;
  }

  .post-name {
    color: #117743;
    font-weight: bold;
  }

  .post-trip {
    color: #228854;
  }

  .post-id {
    padding: 0 2px;
    cursor: pointer;
  }

  .post-date {
    color: #106030;
    font-size: 12px;
  }

  .post-number {
    color: #800000;
    font-size: 12px;
    cursor: pointer;
  }
  .post-number:hover { color: #D00; }

  .post-reply-link {
    color: #800000;
    font-size: 12px;
    margin-left: 2px;
  }

  .capcode {
    color: #F0A;
    font-weight: bold;
  }

  /* --- File info --- */
  .file-info {
    color: #707070;
    font-size: 11px;
    margin-bottom: 2px;
  }
  .file-info a { color: #707070; }

  /* --- Post message --- */
  .post-message {
    margin-top: 2px;
    word-wrap: break-word;
    overflow-wrap: break-word;
    font-size: 13px;
    line-height: 1.5;
  }

  .post-message .quotelink {
    color: #D00;
    text-decoration: none;
  }
  .post-message .quotelink:hover { text-decoration: underline; }

  .post-message .greentext {
    color: #789922;
  }

  .post-message .deadlink {
    color: #999;
    text-decoration: line-through;
  }

  .post-message br + br { margin-top: 0.4em; }

  /* --- Deleted file --- */
  .file-deleted {
    color: #707070;
    font-size: 11px;
    font-style: italic;
    margin: 4px 0;
  }

  /* --- Sticky/Closed icons --- */
  .thread-icons {
    display: inline-block;
    margin-left: 6px;
    vertical-align: middle;
  }
  .thread-icons img {
    vertical-align: middle;
    margin-right: 2px;
  }

  /* --- Stats bar --- */
  .thread-stats {
    color: #707070;
    font-size: 11px;
    margin: 6px 0 0 0;
  }

  /* --- Full-size overlay --- */
  .image-full {
    display: none;
    position: fixed;
    top: 0; left: 0;
    width: 100vw; height: 100vh;
    background: rgba(0,0,0,0.85);
    z-index: 9999;
    cursor: zoom-out;
    justify-content: center;
    align-items: center;
  }
  .image-full img {
    max-width: 95vw;
    max-height: 95vh;
    object-fit: contain;
  }
  .image-full.active { display: flex; }

  /* --- Reply highlight --- */
  .reply-highlight {
    background: #D6DAF0 !important;
  }

  /* --- Mobile --- */
  @media (max-width: 600px) {
    .container { padding: 0 4px; }
    .op .post-image img { max-width: 85vw; max-height: 50vh; }
    .reply .post-image img { max-width: 60vw; max-height: 40vh; }
    .thread-replies { padding-left: 8px; }
    .post-info { white-space: normal; }
  }
</style>
</head>
<body>

<div class="board-banner">
  <span class="board-label">$boardTitle</span>
</div>

<div class="container">

<div class="archive-notice">
  Locally archived on $archivedDate &mdash;
  Source: <a href="https://boards.4chan.org/$board/thread/$threadId">boards.4chan.org/$board/thread/$threadId</a>
  &mdash; All images stored locally
</div>

"@

foreach ($post in $posts) {
    $isOp = ($post.resto -eq 0)

    if ($isOp) {
        $htmlContent += '<div class="op-container">' + "`n"
        $htmlContent += '<div class="op" id="p' + $post.no + '">' + "`n"
    } else {
        $htmlContent += '<div class="reply" id="p' + $post.no + '">' + "`n"
    }

    # Post info line (comes first on 4chan)
    $htmlContent += '  <div class="post-info">'

    if ($post.sub) {
        $htmlContent += '<span class="post-subject">' + (Escape-Html $post.sub) + '</span> '
    }

    $htmlContent += '<span class="post-name">' + (Escape-Html $post.name) + '</span> '

    if ($post.trip) {
        $htmlContent += '<span class="post-trip">' + (Escape-Html $post.trip) + '</span> '
    }

    if ($post.capcode) {
        $capLabel = switch ($post.capcode) {
            "admin" { "## Admin" }
            "mod" { "## Mod" }
            "manager" { "## Manager" }
            "developer" { "## Developer" }
            "founder" { "## Founder" }
            default { "## $($post.capcode)" }
        }
        $htmlContent += '<span class="capcode">' + $capLabel + '</span> '
    }

    $htmlContent += '<span class="post-date">' + (Escape-Html $post.now) + '</span> '
    $htmlContent += '<a class="post-number" href="#p' + $post.no + '">No.' + $post.no + '</a>'

    if (-not $isOp) {
        $htmlContent += ' <a class="post-reply-link" href="#p' + $post.resto + '">&#9658;' + $post.resto + '</a>'
    }

    $htmlContent += '</div>' + "`n"

    # File info and image
    if ($post.tim -and $post.ext -and -not $post.filedeleted) {
        $filename = "$($post.tim)$($post.ext)"
        $thumbFilename = "$($post.tim)s.jpg"
        $origName = if ($post.filename) { "$($post.filename)$($post.ext)" } else { $filename }
        $fsizeKB = [math]::Round($post.fsize / 1024, 1)
        $fsizeStr = if ($fsizeKB -ge 1024) { "$([math]::Round($fsizeKB/1024, 2)) MB" } else { "$fsizeKB KB" }

        $htmlContent += @"
  <div class="file-info">
    File: <a href="images/$filename">$(Escape-Html $origName)</a>
    ($($post.w)x$($post.h), $fsizeStr)
  </div>
  <div class="post-image">
    <a href="images/$filename">
      <img src="images/$thumbFilename" alt="$(Escape-Html $origName)" loading="lazy" onclick="return showFullImage(this, 'images/$filename')">
    </a>
  </div>

"@
    }

    if ($post.filedeleted) {
        $htmlContent += '  <div class="file-deleted">[File deleted]</div>' + "`n"
    }

    # Post message
    if ($post.com) {
        $message = Convert-Comment $post.com
        $htmlContent += '  <div class="post-message">' + $message + '</div>' + "`n"
    }

    $htmlContent += '</div>' + "`n"

    # Close OP container and open thread replies area after OP
    if ($isOp) {
        if ($posts.Count -gt 1) {
            $htmlContent += '<div class="thread-stats">' + "`n"
            $stats = @()
            if ($op.replies) { $stats += "$($op.replies) replies" }
            if ($op.images) { $stats += "$($op.images) images" }
            if ($op.archived) { $stats += "ARCHIVED" }
            $htmlContent += '  ' + ($stats -join ' &mdash; ')
            $htmlContent += "`n</div>`n"
            $htmlContent += '</div>' + "`n"
            $htmlContent += '<div class="thread-replies">' + "`n"
        } else {
            $htmlContent += '</div>' + "`n"
        }
    }
}

# Close thread-replies if it was opened
if ($posts.Count -gt 1) {
    $htmlContent += '</div>' + "`n"
}

$htmlContent += @"

</div>

<div class="image-full" id="imageOverlay" onclick="this.classList.remove('active')">
  <img id="fullImg" src="" alt="Full size">
</div>

<script>
// Full-size image overlay
function showFullImage(el, src) {
  var overlay = document.getElementById('imageOverlay');
  document.getElementById('fullImg').src = src;
  overlay.classList.add('active');
  return false;
}

document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    document.getElementById('imageOverlay').classList.remove('active');
  }
});

// Highlight post on quote link click
document.addEventListener('click', function(e) {
  var link = e.target.closest('a.quotelink');
  if (!link) return;
  var href = link.getAttribute('href');
  if (!href || href.charAt(0) !== '#') return;
  var target = document.getElementById(href.substring(1));
  if (!target) return;
  e.preventDefault();
  target.scrollIntoView({ behavior: 'smooth', block: 'center' });
  target.classList.add('reply-highlight');
  setTimeout(function() { target.classList.remove('reply-highlight'); }, 2000);
  history.replaceState(null, '', href);
});

// Click post number to highlight
document.addEventListener('click', function(e) {
  var num = e.target.closest('.post-number');
  if (!num) return;
  var post = num.closest('.op, .reply');
  if (!post) return;
  post.classList.add('reply-highlight');
  setTimeout(function() { post.classList.remove('reply-highlight'); }, 1500);
});
</script>

</body>
</html>
"@

# --- Save thread JSON for future updates ---
$jsonPath = Join-Path $threadDir "thread.json"
$response.Content | Out-File -FilePath $jsonPath -Encoding UTF8

# --- Write HTML file ---
$htmlPath = Join-Path $threadDir "thread.html"
$htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8

# --- Summary ---
Write-Host "`n========================================" -ForegroundColor Green
if ($isUpdate) {
    Write-Host " Update complete! ($newPostCount new posts)" -ForegroundColor Green
} else {
    Write-Host " Archive complete!" -ForegroundColor Green
}
Write-Host "========================================" -ForegroundColor Green
Write-Host " Location: $threadDir" -ForegroundColor White
Write-Host " HTML:     thread.html" -ForegroundColor White
Write-Host " Images:   $($posts | Where-Object { $_.tim -and -not $_.filedeleted } | Measure-Object | Select-Object -ExpandProperty Count) total files in images/" -ForegroundColor White

if ($failedImages.Count -gt 0) {
    Write-Host "`n Failed downloads:" -ForegroundColor Yellow
    foreach ($f in $failedImages) {
        Write-Host "   - $f" -ForegroundColor Yellow
    }
}

Write-Host "`nOpen thread.html in your browser to view the archive." -ForegroundColor Cyan
