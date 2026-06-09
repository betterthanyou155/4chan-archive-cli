param(
    [string]$ArchiveName
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\utils.ps1"

$archiveRoot = Join-Path $PSScriptRoot "archives"

if (-not (Test-Path $archiveRoot)) {
    Write-Host "No archives folder found." -ForegroundColor Yellow
    exit 0
}

# Get list of archive folders
if ($ArchiveName) {
    $folders = @(Get-Item (Join-Path $archiveRoot $ArchiveName) -ErrorAction SilentlyContinue)
    if (-not $folders) {
        Write-Host "Archive not found: $ArchiveName" -ForegroundColor Red
        exit 1
    }
} else {
    $folders = Get-ChildItem $archiveRoot -Directory
}

$updated = 0
$skipped = 0
$errors = @()

foreach ($folder in $folders) {
    $jsonPath = Join-Path $folder.FullName "thread.json"
    $htmlPath = Join-Path $folder.FullName "thread.html"

    if (-not (Test-Path $jsonPath)) {
        Write-Host "  SKIP $($folder.Name) - no thread.json" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    # Parse board and threadId from folder name (format: board_threadId)
    $parts = $folder.Name -split '_', 2
    if ($parts.Count -ne 2) {
        Write-Host "  SKIP $($folder.Name) - unexpected folder name format" -ForegroundColor DarkGray
        $skipped++
        continue
    }
    $board = $parts[0]
    $threadId = $parts[1]

    try {
        $thread = Get-Content $jsonPath -Raw | ConvertFrom-Json
        $posts = $thread.posts
        $op = $posts[0]

        $boardTitle = if ($board -eq "po") { "/po/ - Papercraft & Origami" } else { "/$board/" }
        $threadTitle = if ($op.sub) { $op.sub } else { "Thread #$threadId" }
        $archivedDate = if (Test-Path $htmlPath) {
            # Try to keep original date from existing HTML
            $existing = Get-Content $htmlPath -Raw
            if ($existing -match 'Locally archived on (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
                $Matches[1]
            } else {
                Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        } else {
            Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }



        # --- Generate HTML (same template as archive.ps1) ---

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

  .board-banner {
    background: #EEF2FF;
    border-bottom: 1px solid #D6DAF0;
    padding: 6px 12px;
    font-size: 11px;
    color: #AF0A0F;
    text-align: center;
    margin-bottom: 8px;
    position: relative;
  }
  .board-banner a { color: #AF0A0F; }
  .board-banner .board-label { font-weight: bold; font-size: 13px; }

  .layout-toggle {
    position: absolute;
    right: 10px;
    top: 50%;
    transform: translateY(-50%);
    display: flex;
    gap: 4px;
    align-items: center;
  }
  .layout-toggle span { font-size: 10px; color: #666; margin-right: 2px; }
  .layout-btn {
    background: #D6DAF0;
    border: 1px solid #B0B4D0;
    color: #333;
    font-size: 11px;
    padding: 2px 8px;
    cursor: pointer;
    border-radius: 2px;
    user-select: none;
  }
  .layout-btn:hover { background: #C0C4E0; }
  .layout-btn.active { background: #8888CC; color: #fff; border-color: #6666AA; }

  .archive-notice {
    background: #FFFFDD;
    border: 1px solid #DD8;
    padding: 6px 10px;
    margin: 0 0 6px 0;
    font-size: 11px;
    text-align: center;
    color: #880;
  }

  .update-btn {
    background: #E0F0E0;
    border: 1px solid #A0C0A0;
    color: #106030;
    font-weight: bold;
    margin-right: 12px;
  }
  .update-btn:hover { background: #D0E8D0; }
  .update-btn:disabled { background: #E8E8E8; border-color: #C8C8C8; color: #888; cursor: not-allowed; }
  .archive-notice.temp-notice {
    background: #E0FFE0;
    border: 1px solid #A0D0A0;
    color: #106030;
  }

  .container {
    max-width: 960px;
    margin: 0 auto;
    padding: 0 10px;
  }

  .thread { margin-bottom: 20px; }

  .op {
    background: #F0E0D0;
    border: 1px solid #D9BFB7;
    padding: 5px 10px;
    margin-bottom: 4px;
    display: flow-root;
  }
  .op .post-image { float: left; margin: 4px 20px 10px 0; }
  .op .post-image img { max-width: 400px; max-height: 400px; border: 0; cursor: pointer; }
  .op .post-message { overflow: hidden; }

  .reply {
    background: #F0E0D0;
    border: 1px solid #D9BFB7;
    display: table;
    clear: both;
    margin: 4px 0;
    padding: 5px 8px;
  }
  .reply .post-image { float: left; margin: 4px 15px 4px 0; }
  .reply .post-image img { max-width: 250px; max-height: 250px; border: 0; cursor: pointer; }

  /* --- Grid mode overrides --- */
  body.grid-mode .container {
    max-width: 95vw;
  }
  body.grid-mode .thread {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    gap: 12px;
    align-items: start;
  }
  body.grid-mode .op {
    grid-column: 1 / -1;
    display: flow-root;
  }
  body.grid-mode .thread-stats {
    grid-column: 1 / -1;
  }
  body.grid-mode .reply {
    display: flex;
    flex-direction: column;
    width: 100%;
    max-width: none;
    margin: 0;
    padding: 10px;
    border-radius: 4px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    background: #F0E0D0;
    border: 1px solid #D9BFB7;
    transition: transform 0.15s ease, box-shadow 0.15s ease;
  }
  body.grid-mode .reply:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 10px rgba(0,0,0,0.15);
  }
  body.grid-mode .reply .post-image {
    float: none;
    margin: 8px 0;
    text-align: center;
    align-self: center;
    width: 100%;
  }
  body.grid-mode .reply .post-image img {
    max-width: 100%;
    max-height: 200px;
    width: auto;
    height: auto;
    object-fit: contain;
    border-radius: 2px;
  }
  body.grid-mode .reply .post-image.expanded {
    display: block;
    width: 100%;
  }
  body.grid-mode .reply .post-image.expanded img {
    max-width: 100%;
    max-height: none;
    height: auto;
  }
  body.grid-mode .reply .post-info {
    white-space: normal;
    font-size: 11px;
    border-bottom: 1px solid rgba(128, 0, 0, 0.15);
    padding-bottom: 5px;
    margin-bottom: 6px;
    line-height: 1.3;
  }
  body.grid-mode .reply .file-info {
    font-size: 10px;
    color: #707070;
    margin-bottom: 4px;
    word-break: break-all;
  }
  body.grid-mode .reply .post-message {
    font-size: 12px;
    line-height: 1.4;
    max-height: 160px;
    overflow-y: auto;
    scrollbar-width: thin;
    scrollbar-color: #D9BFB7 transparent;
    border-top: 1px solid rgba(128, 0, 0, 0.08);
    padding-top: 6px;
    margin-top: 6px;
  }
  body.grid-mode .reply .post-message::-webkit-scrollbar {
    width: 4px;
  }
  body.grid-mode .reply .post-message::-webkit-scrollbar-track {
    background: transparent;
  }
  body.grid-mode .reply .post-message::-webkit-scrollbar-thumb {
    background: #D9BFB7;
    border-radius: 2px;
  }
  body.grid-mode .reply .post-message::-webkit-scrollbar-thumb:hover {
    background: #AF0A0F;
  }

  .post-info { font-size: 13px; white-space: nowrap; margin-bottom: 2px; }
  .post-subject { color: #0F0C5D; font-weight: bold; }
  .post-name { color: #117743; font-weight: bold; }
  .post-trip { color: #228854; }
  .post-date { color: #106030; font-size: 12px; }
  .post-number { color: #800000; font-size: 12px; cursor: pointer; }
  .post-number:hover { color: #D00; }
  .post-reply-link { color: #800000; font-size: 12px; margin-left: 2px; }
  .post-reply-link:hover { color: #D00; }
  .capcode { color: #F0A; font-weight: bold; }
  .backlink { font-size: 11px; display: inline-block; margin-left: 6px; vertical-align: middle; }
  .backlink a { color: #D00; margin-right: 4px; }

  .file-info { color: #707070; font-size: 11px; margin-bottom: 2px; }
  .file-info a { color: #707070; }

  .expand-btn {
    display: inline-block;
    color: #707070;
    font-size: 11px;
    font-weight: bold;
    cursor: pointer;
    margin-left: 3px;
    padding: 0 3px;
    border: 1px solid #B8B8B8;
    border-radius: 2px;
    background: #F5F5F0;
    line-height: 14px;
    vertical-align: middle;
    user-select: none;
  }
  .expand-btn:hover { background: #E8E8E0; color: #555; }

  .post-message {
    margin-top: 2px;
    word-wrap: break-word;
    overflow-wrap: break-word;
    font-size: 13px;
    line-height: 1.5;
  }
  .post-message .quotelink { color: #D00; text-decoration: none; cursor: pointer; }
  .post-message .quotelink:hover { text-decoration: underline; }
  .post-message .greentext { color: #789922; }
  .post-message .deadlink { color: #999; text-decoration: line-through; }
  .post-message br + br { margin-top: 0.4em; }

  .file-deleted { color: #707070; font-size: 11px; font-style: italic; margin: 4px 0; }

  .thread-stats {
    color: #707070;
    font-size: 11px;
    margin: 4px 0;
    padding: 4px 0;
    border-top: 1px solid #D9BFB7;
    border-bottom: 1px solid #D9BFB7;
  }

  .post-image.expanded {
    float: none !important;
    margin: 4px 0 10px 0 !important;
    position: relative;
    z-index: 100;
    display: inline-block;
  }
  .post-image.expanded img {
    max-width: none;
    max-height: none;
    cursor: nwse-resize;
  }
  .resize-handle {
    display: none;
    position: absolute;
    bottom: 0;
    right: 0;
    width: 16px;
    height: 16px;
    cursor: nwse-resize;
    z-index: 101;
  }
  .resize-handle::after {
    content: '';
    position: absolute;
    bottom: 3px;
    right: 3px;
    width: 8px;
    height: 8px;
    border-right: 2px solid #888;
    border-bottom: 2px solid #888;
  }
  .post-image.expanded .resize-handle { display: block; }

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
  .image-full img { max-width: 95vw; max-height: 95vh; object-fit: contain; }
  .image-full.active { display: flex; }

  .post-preview {
    position: absolute;
    z-index: 9000;
    background: #F0E0D0;
    border: 1px solid #D9BFB7;
    padding: 4px 8px;
    max-width: 420px;
    min-width: 200px;
    font-size: 12px;
    line-height: 1.4;
    box-shadow: 2px 2px 6px rgba(0,0,0,0.2);
    pointer-events: none;
    overflow: hidden;
  }
  .post-preview .pv-info { font-size: 11px; margin-bottom: 2px; white-space: nowrap; }
  .post-preview .pv-info .pv-subject { color: #0F0C5D; font-weight: bold; }
  .post-preview .pv-info .pv-name { color: #117743; font-weight: bold; }
  .post-preview .pv-image { float: left; margin: 2px 8px 2px 0; }
  .post-preview .pv-image img { max-width: 120px; max-height: 120px; }
  .post-preview .pv-msg { overflow: hidden; font-size: 12px; color: #800000; word-wrap: break-word; max-height: 200px; overflow-y: auto; }
  .post-preview .pv-msg .greentext { color: #789922; }
  .post-preview .pv-msg .quotelink { color: #D00; }

  .post-highlight { background: #D6DAF0 !important; }

  @media (max-width: 600px) {
    .container { padding: 0 4px; }
    .op .post-image img { max-width: 85vw; max-height: 50vh; }
    .reply .post-image img { max-width: 60vw; max-height: 40vh; }
    .post-info { white-space: normal; }
    .post-preview { max-width: 80vw; }
    .layout-toggle span { display: none; }
  }
</style>
</head>
<body>

<div class="board-banner">
  <span class="board-label">$boardTitle</span>
  <div class="layout-toggle">
    <button class="layout-btn update-btn" onclick="updateThreadDynamic()" id="btn-update" title="Fetch new posts from 4chan API (dynamic update)">Update</button>
    <span>Layout:</span>
    <button class="layout-btn active" onclick="setLayout('list')" id="btn-list">List</button>
    <button class="layout-btn" onclick="setLayout('grid')" id="btn-grid">Grid</button>
  </div>
</div>

<div class="container">

<div class="archive-notice">
  Locally archived on $archivedDate &mdash;
  Source: <a href="https://boards.4chan.org/$board/thread/$threadId">boards.4chan.org/$board/thread/$threadId</a>
  &mdash; All images stored locally
</div>

<div class="thread" data-board="$board" data-thread-id="$threadId">

"@

        $backlinks = @{}
        foreach ($p in $posts) {
            if ($p.com -and $p.com -match 'href="#p(\d+)"') {
                $matches = [regex]::Matches($p.com, 'href="#p(\d+)"')
                foreach ($m in $matches) {
                    $targetId = $m.Groups[1].Value
                    if (-not $backlinks.ContainsKey($targetId)) {
                        $backlinks[$targetId] = [System.Collections.Generic.List[string]]::new()
                    }
                    if (-not $backlinks[$targetId].Contains($p.no.ToString())) {
                        $backlinks[$targetId].Add($p.no.ToString())
                    }
                }
            }
        }

        foreach ($post in $posts) {
            $isOp = ($post.resto -eq 0)
            $divClass = if ($isOp) { "op" } else { "reply" }

            $htmlContent += '<div class="' + $divClass + '" id="p' + $post.no + '" data-postno="' + $post.no + '">' + "`n"
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

            $postNoStr = $post.no.ToString()
            if ($backlinks.ContainsKey($postNoStr)) {
                $htmlContent += '<span class="backlink">'
                foreach ($quotedBy in $backlinks[$postNoStr]) {
                    $htmlContent += '<a class="quotelink" href="#p' + $quotedBy + '">&gt;&gt;' + $quotedBy + '</a>'
                }
                $htmlContent += '</span>'
            }

            $htmlContent += '</div>' + "`n"

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
    <span class="expand-btn" onclick="toggleExpand(this)" title="Expand image inline">+</span>
  </div>
  <div class="post-image">
    <a href="images/$filename">
      <img src="images/$thumbFilename" alt="$(Escape-Html $origName)" loading="lazy" onclick="return showFullImage(this, 'images/$filename')">
    </a>
    <div class="resize-handle" title="Drag to resize"></div>
  </div>

"@
            }

            if ($post.filedeleted) {
                $htmlContent += '  <div class="file-deleted">[File deleted]</div>' + "`n"
            }

            if ($post.com) {
                $message = Convert-Comment $post.com
                $htmlContent += '  <div class="post-message">' + $message + '</div>' + "`n"
            }

            $htmlContent += '</div>' + "`n"

            if ($isOp -and $posts.Count -gt 1) {
                $htmlContent += '<div class="thread-stats">' + "`n"
                $stats = @()
                if ($op.replies) { $stats += "$($op.replies) replies" }
                if ($op.images) { $stats += "$($op.images) images" }
                if ($op.archived) { $stats += "ARCHIVED" }
                $htmlContent += '  ' + ($stats -join ' &mdash; ')
                $htmlContent += "`n</div>`n"
            }
        }

        $htmlContent += '</div>' + "`n"

        $htmlContent += @"

</div>

<div class="image-full" id="imageOverlay" onclick="this.classList.remove('active')">
  <img id="fullImg" src="" alt="Full size">
</div>

<div class="post-preview" id="postPreview" style="display:none"></div>

<script>
(function() {
  window.setLayout = function(mode) {
    document.body.classList.remove('list-mode', 'grid-mode');
    document.body.classList.add(mode + '-mode');
    document.getElementById('btn-list').classList.toggle('active', mode === 'list');
    document.getElementById('btn-grid').classList.toggle('active', mode === 'grid');
    try { localStorage.setItem('archive-layout', mode); } catch(e) {}
  };
  (function() {
    var saved = 'list';
    try { saved = localStorage.getItem('archive-layout') || 'list'; } catch(e) {}
    setLayout(saved);
  })();

  window.showFullImage = function(el, src) {
    if (el.closest('.post-image.expanded')) return false;
    document.getElementById('fullImg').src = src;
    document.getElementById('imageOverlay').classList.add('active');
    return false;
  };
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') document.getElementById('imageOverlay').classList.remove('active');
  });

  window.toggleExpand = function(btn) {
    var post = btn.closest('.op, .reply');
    var imgDiv = post.querySelector('.post-image');
    if (!imgDiv) return;
    var img = imgDiv.querySelector('img');
    if (!img) return;
    var fullSrc = imgDiv.querySelector('a').getAttribute('href');
    if (imgDiv.classList.contains('expanded')) {
      imgDiv.classList.remove('expanded');
      img.src = img.getAttribute('data-thumb');
      img.style.width = '';
      btn.textContent = '+';
      btn.title = 'Expand image inline';
    } else {
      img.setAttribute('data-thumb', img.src);
      imgDiv.classList.add('expanded');
      img.src = fullSrc;
      img.style.width = '';
      btn.textContent = '\u2013';
      btn.title = 'Collapse image';
    }
  };

  // --- High-Performance Drag-to-resize on expanded images using requestAnimationFrame ---
  document.addEventListener('mousedown', function(e) {
    var imgDiv = e.target.closest('.post-image.expanded');
    if (!imgDiv) return;
    var img = imgDiv.querySelector('img');
    if (!img || e.target !== img) return;

    e.preventDefault();
    var startX = e.clientX;
    var startW = img.offsetWidth;
    var currentX = e.clientX;
    var ticking = false;

    function onMove(ev) {
      currentX = ev.clientX;
      if (!ticking) {
        window.requestAnimationFrame(updateResize);
        ticking = true;
      }
    }

    function updateResize() {
      img.style.width = Math.max(50, startW + currentX - startX) + 'px';
      ticking = false;
    }

    function onUp() {
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    }

    document.body.style.cursor = 'nwse-resize';
    document.body.style.userSelect = 'none';
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  });

  // --- Dynamic Thread Updates via 4chan API ---
  function escapeHtmlJs(text) {
    if (!text) return "";
    return text.toString().replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function convertCommentJs(com) {
    if (!com) return "";
    com = com.replace(/<wbr>/g, '');
    var lines = com.split(/<br\s*\/?>/i);
    var processed = lines.map(function(line) {
      var trimmed = line.trim();
      if (trimmed.indexOf('&gt;') === 0 && trimmed.indexOf('&gt;&gt;') !== 0) {
        return '<span class="greentext">' + line + '</span>';
      }
      return line;
    });
    return processed.join('<br>');
  }

  function rebuildBacklinks() {
    var existingBacklinks = document.querySelectorAll('.backlink');
    existingBacklinks.forEach(function(el) { el.remove(); });

    var backlinksMap = {};
    var posts = document.querySelectorAll('.op, .reply');
    posts.forEach(function(post) {
      var postId = post.getAttribute('data-postno');
      var msgEl = post.querySelector('.post-message');
      if (!msgEl) return;
      var quotes = msgEl.querySelectorAll('.quotelink');
      quotes.forEach(function(quote) {
        var href = quote.getAttribute('href');
        if (!href || href.charAt(0) !== '#') return;
        var targetId = href.substring(2); // Skip '#p'
        if (!backlinksMap[targetId]) {
          backlinksMap[targetId] = [];
        }
        if (backlinksMap[targetId].indexOf(postId) === -1) {
          backlinksMap[targetId].push(postId);
        }
      });
    });

    Object.keys(backlinksMap).forEach(function(targetId) {
      var targetPost = document.getElementById('p' + targetId);
      if (!targetPost) return;
      var infoEl = targetPost.querySelector('.post-info');
      if (!infoEl) return;

      var span = document.createElement('span');
      span.className = 'backlink';
      backlinksMap[targetId].forEach(function(quotingId) {
        var a = document.createElement('a');
        a.className = 'quotelink';
        a.href = '#p' + quotingId;
        a.textContent = '>>' + quotingId;
        span.appendChild(a);
      });
      infoEl.appendChild(span);
    });
  }

  window.updateThreadDynamic = function() {
    var btn = document.getElementById('btn-update');
    if (btn.disabled) return;

    btn.disabled = true;
    btn.textContent = 'Updating...';

    var threadEl = document.querySelector('.thread');
    var board = threadEl.getAttribute('data-board');
    var threadId = threadEl.getAttribute('data-thread-id');
    var apiUrl = 'https://a.4cdn.org/' + board + '/thread/' + threadId + '.json';

    function showUpdateError(msg) {
      btn.textContent = 'Error: ' + msg;
      btn.style.background = '#FFD0D0';
      btn.style.borderColor = '#C0A0A0';
      btn.style.color = '#800000';
      setTimeout(function() {
        btn.disabled = false;
        btn.textContent = 'Update';
        btn.style.background = '';
        btn.style.borderColor = '';
        btn.style.color = '';
      }, 4000);
    }

    fetch(apiUrl)
      .then(function(res) {
        if (!res.ok) {
          if (res.status === 404) {
            throw new Error('Thread deleted (404)');
          }
          throw new Error('HTTP ' + res.status);
        }
        return res.json();
      })
      .then(function(data) {
        var posts = data.posts;
        var newPostCount = 0;
        var addedHtml = '';

        posts.forEach(function(post) {
          if (document.getElementById('p' + post.no)) return;

          newPostCount++;
          var html = '';
          html += '<div class="reply" id="p' + post.no + '" data-postno="' + post.no + '">';
          html += '  <div class="post-info">';
          if (post.sub) html += '<span class="post-subject">' + escapeHtmlJs(post.sub) + '</span> ';
          html += '<span class="post-name">' + escapeHtmlJs(post.name) + '</span> ';
          if (post.trip) html += '<span class="post-trip">' + escapeHtmlJs(post.trip) + '</span> ';
          if (post.capcode) {
            var capLabel = '## ' + post.capcode;
            if (post.capcode === 'admin') capLabel = '## Admin';
            else if (post.capcode === 'mod') capLabel = '## Mod';
            html += '<span class="capcode">' + capLabel + '</span> ';
          }
          html += '<span class="post-date">' + escapeHtmlJs(post.now) + '</span> ';
          html += '<a class="post-number" href="#p' + post.no + '">No.' + post.no + '</a>';
          html += ' <a class="post-reply-link" href="#p' + post.resto + '">&#9658;' + post.resto + '</a>';
          html += '</div>';

          if (post.tim && post.ext && !post.filedeleted) {
            var filename = post.tim + post.ext;
            var origName = post.filename ? (post.filename + post.ext) : filename;
            var fsizeKB = Math.round(post.fsize / 102.4) / 10;
            var fsizeStr = fsizeKB >= 1024 ? (Math.round(fsizeKB / 10.24) / 100 + ' MB') : (fsizeKB + ' KB');
            var fullSrc = 'https://i.4cdn.org/' + board + '/' + filename;
            var thumbSrc = 'https://i.4cdn.org/' + board + '/' + post.tim + 's.jpg';

            html += '  <div class="file-info">';
            html += '    File: <a href="' + fullSrc + '" target="_blank">' + escapeHtmlJs(origName) + '</a>';
            html += '    (' + post.w + 'x' + post.h + ', ' + fsizeStr + ')';
            html += '    <span class="expand-btn" onclick="toggleExpand(this)" title="Expand image inline">+</span>';
            html += '  </div>';
            html += '  <div class="post-image">';
            html += '    <a href="' + fullSrc + '" target="_blank">';
            html += '      <img src="' + thumbSrc + '" alt="' + escapeHtmlJs(origName) + '" loading="lazy" onclick="return showFullImage(this, \'' + fullSrc + '\')">';
            html += '    </a>';
            html += '    <div class="resize-handle" title="Drag to resize"></div>';
            html += '  </div>';
          }

          if (post.filedeleted) {
            html += '  <div class="file-deleted">[File deleted]</div>';
          }

          if (post.com) {
            html += '  <div class="post-message">' + convertCommentJs(post.com) + '</div>';
          }
          html += '</div>';
          addedHtml += html;
        });

        if (newPostCount > 0) {
          // Append new replies
          var tempDiv = document.createElement('div');
          tempDiv.innerHTML = addedHtml;
          while (tempDiv.firstChild) {
            threadEl.appendChild(tempDiv.firstChild);
          }

          // Rebuild backlinks list across all posts
          rebuildBacklinks();

          // Show temp notification banner at top
          var existingTempNotice = document.querySelector('.temp-notice');
          if (existingTempNotice) existingTempNotice.remove();

          var notice = document.createElement('div');
          notice.className = 'archive-notice temp-notice';
          notice.textContent = newPostCount + ' new post(s) dynamically loaded from 4chan CDN. These updates are temporary; run the archive update script to save them permanently to disk.';
          document.querySelector('.container').insertBefore(notice, document.querySelector('.thread'));
          
          // Smooth scroll to first new post
          var firstNewPostId = posts[posts.length - newPostCount].no;
          var firstNewPost = document.getElementById('p' + firstNewPostId);
          if (firstNewPost) {
            firstNewPost.scrollIntoView({ behavior: 'smooth', block: 'center' });
            firstNewPost.classList.add('post-highlight');
            setTimeout(function() { firstNewPost.classList.remove('post-highlight'); }, 2000);
          }
        }

        // Reset button
        btn.disabled = false;
        btn.textContent = 'Update';
        btn.style.background = '';
        btn.style.borderColor = '';
        btn.style.color = '';
      })
      .catch(function(err) {
        showUpdateError(err.message === 'Failed to fetch' ? 'Network error' : err.message);
      });
  };

  var previewEl = document.getElementById('postPreview');
  var previewTimer = null;
  document.addEventListener('mouseover', function(e) {
    var link = e.target.closest('.quotelink');
    if (!link) return;
    var href = link.getAttribute('href');
    if (!href || href.charAt(0) !== '#') return;
    var target = document.getElementById(href.substring(1));
    if (!target) return;
    clearTimeout(previewTimer);
    previewTimer = setTimeout(function() {
      previewEl.innerHTML = buildPreview(target);
      previewEl.style.display = 'block';
      positionPreview(link);
    }, 250);
  });
  document.addEventListener('mouseout', function(e) {
    if (!e.target.closest('.quotelink')) return;
    clearTimeout(previewTimer);
    previewEl.style.display = 'none';
  });
  function positionPreview(link) {
    var rect = link.getBoundingClientRect();
    var left = rect.left + window.scrollX;
    var top = rect.bottom + window.scrollY + 4;
    if (left + previewEl.offsetWidth > window.innerWidth - 10) left = window.innerWidth - previewEl.offsetWidth - 10;
    if (left < 5) left = 5;
    if (top + previewEl.offsetHeight > window.innerHeight + window.scrollY - 10) top = rect.top + window.scrollY - previewEl.offsetHeight - 4;
    previewEl.style.left = left + 'px';
    previewEl.style.top = top + 'px';
  }
  function buildPreview(post) {
    var info = post.querySelector('.post-info');
    var imgEl = post.querySelector('.post-image img');
    var msgEl = post.querySelector('.post-message');
    var h = '<div class="pv-info">';
    var s;
    if (info && (s = info.querySelector('.post-subject'))) h += '<span class="pv-subject">' + s.textContent + '</span> ';
    if (info && (s = info.querySelector('.post-name'))) h += '<span class="pv-name">' + s.textContent + '</span> ';
    if (info && (s = info.querySelector('.post-date'))) h += '<span>' + s.textContent + '</span> ';
    if (info && (s = info.querySelector('.post-number'))) h += '<span>' + s.textContent + '</span>';
    h += '</div>';
    if (imgEl) h += '<div class="pv-image"><img src="' + (imgEl.getAttribute('data-thumb') || imgEl.src) + '" alt=""></div>';
    if (msgEl) h += '<div class="pv-msg">' + msgEl.innerHTML + '</div>';
    return h;
  }

  document.addEventListener('click', function(e) {
    var link = e.target.closest('a.quotelink');
    if (!link) return;
    var href = link.getAttribute('href');
    if (!href || href.charAt(0) !== '#') return;
    var target = document.getElementById(href.substring(1));
    if (!target) return;
    e.preventDefault();
    previewEl.style.display = 'none';
    target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    target.classList.add('post-highlight');
    setTimeout(function() { target.classList.remove('post-highlight'); }, 2000);
    history.replaceState(null, '', href);
  });
  document.addEventListener('click', function(e) {
    var num = e.target.closest('.post-number');
    if (!num) return;
    var post = num.closest('.op, .reply');
    if (!post) return;
    post.classList.add('post-highlight');
    setTimeout(function() { post.classList.remove('post-highlight'); }, 1500);
  });
})();
</script>

</body>
</html>
"@

        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Host "  OK   $($folder.Name) ($($posts.Count) posts)" -ForegroundColor Green
        $updated++

    } catch {
        Write-Host "  ERR  $($folder.Name) - $($_.Exception.Message)" -ForegroundColor Red
        $errors += $folder.Name
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Updated $updated archive(s)" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host " Skipped $skipped (no thread.json)" -ForegroundColor DarkGray
}
if ($errors.Count -gt 0) {
    Write-Host " Errors: $($errors.Count)" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Green
