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

# --- Fetch thread JSON with retries ---
Write-Host "Fetching thread /$board/$threadId ..." -ForegroundColor Cyan
$maxAttempts = 3
$attempt = 1
$success = $false
$thread = $null
$response = $null

while (-not $success -and $attempt -le $maxAttempts) {
    try {
        $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -Headers @{ "User-Agent" = "4chan-archiver/1.0" } -TimeoutSec 15
        $thread = $response.Content | ConvertFrom-Json
        $success = $true
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
        }
        
        if ($statusCode -eq 404) {
            break
        }
        
        Write-Host "  Attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
        if ($attempt -lt $maxAttempts) {
            $sleepSec = $attempt * 2
            Write-Host "  Retrying in $sleepSec seconds..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $sleepSec
        }
        $attempt++
    }
}

if (-not $success) {
    Write-Host "ERROR: Failed to fetch thread after $maxAttempts attempts. It may not exist, has been deleted, or network is down." -ForegroundColor Red
    if (-not $isUpdate) {
        Remove-Item -Recurse -Force $threadDir -ErrorAction SilentlyContinue
    }
    exit 1
}

$posts = $thread.posts
$op = $posts[0]

Write-Host "Found $($posts.Count) posts" -ForegroundColor Cyan

# --- Download images ---
$imageCount = 0
$failedImages = @()

$newPostCount = 0
$tasks = [System.Collections.ArrayList]::new()
foreach ($post in $posts) {
    $isNew = -not $existingPostIds.ContainsKey($post.no)
    if ($post.tim -and $post.ext -and -not $post.filedeleted) {
        $filename = "$($post.tim)$($post.ext)"
        $thumbFilename = "$($post.tim)s.jpg"

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

    $pool = [RunspaceFactory]::CreateRunspacePool(1, $concurrency)
    $pool.Open()

    $downloadScript = {
        param($Url, $Dest, $TimeoutSeconds)
        try {
            [Void][System.Reflection.Assembly]::LoadWithPartialName("System.Net.Http")
            $client = New-Object System.Net.Http.HttpClient
            if ($TimeoutSeconds -gt 0) {
                $client.Timeout = [System.TimeSpan]::FromSeconds($TimeoutSeconds)
            }
            $client.DefaultRequestHeaders.UserAgent.ParseAdd("4chan-archiver/1.0")
            
            $response = $client.GetAsync($Url).GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                $client.Dispose()
                return @{ Success = $false; Error = "HTTP $($response.StatusCode)" }
            }
            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $fileStream = New-Object System.IO.FileStream($Dest, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $stream.CopyTo($fileStream)
            $fileStream.Dispose()
            $stream.Dispose()
            $client.Dispose()
            return @{ Success = $true }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }

    $runspaces = [System.Collections.ArrayList]::new()
    $total = $pending.Count
    $completed = 0
    $failed = 0

    try {
        foreach ($task in $pending) {
            $ps = [PowerShell]::Create().AddScript($downloadScript).AddArgument($task.Url).AddArgument($task.Dest).AddArgument(30)
            $ps.RunspacePool = $pool

            [void]$runspaces.Add(@{
                Pipe   = $ps
                Handle = $ps.BeginInvoke()
                Task   = $task
            })
        }

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

            for ($j = $done.Count - 1; $j -ge 0; $j--) {
                $runspaces.RemoveAt($done[$j])
            }

            if ($runspaces.Count -gt 0) {
                Start-Sleep -Milliseconds 200
            }
        }
    } finally {
        $pool.Close()
        $pool.Dispose()
    }

    $imageCount = ($tasks | Where-Object { $_.Type -eq "image" -and (Test-Path $_.Dest) }).Count
} else {
    $imageCount = ($tasks | Where-Object { $_.Type -eq "image" }).Count
}

Write-Host "`nDownloaded $imageCount images ($($failedImages.Count) failed)" -ForegroundColor Cyan

# --- Save thread JSON for future updates (BOM-less UTF-8) ---
$jsonPath = Join-Path $threadDir "thread.json"
[System.IO.File]::WriteAllText($jsonPath, $response.Content)

# --- Generate HTML by delegating to update-html.ps1 ---
Write-Host "Generating HTML ..." -ForegroundColor Cyan
try {
    & "$PSScriptRoot\update-html.ps1" -ArchiveName "${board}_${threadId}"
} catch {
    Write-Host "ERROR: Failed to generate HTML: $($_.Exception.Message)" -ForegroundColor Red
}

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
