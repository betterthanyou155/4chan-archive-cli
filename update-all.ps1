param(
    [ValidateRange(1,16)]
    [int]$Concurrency = 4,
    [ValidateRange(0,10000)]
    [int]$DelayMs = 0
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\utils.ps1"

$archiveRoot = Join-Path $PSScriptRoot "archives"

if (-not (Test-Path $archiveRoot)) {
    Write-Host "No archives folder found." -ForegroundColor Yellow
    exit 0
}

$folders = Get-ChildItem $archiveRoot -Directory
if ($folders.Count -eq 0) {
    Write-Host "No archives found." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n  Updating $($folders.Count) archive(s) ...`n" -ForegroundColor Cyan

$updated = 0
$skipped = 0
$removed = 0
$errors = 0

foreach ($folder in $folders) {
    # Start stopwatch for dynamic rate limiting
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $jsonPath = Join-Path $folder.FullName "thread.json"
    $htmlPath = Join-Path $folder.FullName "thread.html"
    $imgDir = Join-Path $folder.FullName "images"

    Write-Host "--- $($folder.Name) ---" -ForegroundColor White

    # Parse board and threadId from folder name
    $info = Parse-ArchiveFolderName $folder.Name
    if (-not $info) {
        Write-Host "  SKIP - unexpected folder name format" -ForegroundColor DarkGray
        $skipped++
        continue
    }
    $board = $info.Board
    $threadId = $info.ThreadId
    $apiUrl = "https://a.4cdn.org/$board/thread/$threadId.json"
    $imageBase = "https://i.4cdn.org/$board"

    # Load existing post IDs
    $existingPostIds = @{}
    if (Test-Path $jsonPath) {
        try {
            $savedThread = Get-Content $jsonPath -Raw | ConvertFrom-Json
            foreach ($p in $savedThread.posts) {
                $existingPostIds[$p.no] = $true
            }
        } catch {
            Write-Host "  Could not read cached thread.json" -ForegroundColor Yellow
        }
    }

    # Fetch fresh thread JSON with retries
    $maxAttempts = 3
    $attempt = 1
    $success = $false
    $thread = $null
    $response = $null
    $is404 = $false

    while (-not $success -and $attempt -le $maxAttempts) {
        try {
            $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -Headers @{ "User-Agent" = "4chan-archiver/1.1" } -TimeoutSec 15
            $thread = $response.Content | ConvertFrom-Json
            $success = $true
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            }
            if ($statusCode -eq 404) {
                $is404 = $true
                break
            }
            Write-Host "    Attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($attempt -lt $maxAttempts) {
                $sleepSec = $attempt * 2
                Start-Sleep -Seconds $sleepSec
            }
            $attempt++
        }
    }

    if ($is404) {
        Write-Host "  REMOVED - thread no longer exists (404)" -ForegroundColor Yellow
        $removed++
        
        # Enforce rate limit before next thread
        $elapsed = $stopwatch.ElapsedMilliseconds
        $sleepTime = [math]::Max(0, 1100 - $elapsed)
        Start-Sleep -Milliseconds $sleepTime
        continue
    }

    if (-not $success) {
        Write-Host "  ERROR - Failed to fetch thread after $maxAttempts attempts" -ForegroundColor Red
        $errors++
        
        # Enforce rate limit before next thread
        $elapsed = $stopwatch.ElapsedMilliseconds
        $sleepTime = [math]::Max(0, 1100 - $elapsed)
        Start-Sleep -Milliseconds $sleepTime
        continue
    }

    $posts = $thread.posts
    $op = $posts[0]

    # Count new posts
    $newPostCount = 0
    foreach ($post in $posts) {
        if (-not $existingPostIds.ContainsKey($post.no)) { $newPostCount++ }
    }

    if ($newPostCount -eq 0 -and $existingPostIds.Count -eq $posts.Count) {
        Write-Host "  UP TO DATE - $($posts.Count) posts, no changes" -ForegroundColor Green
        $skipped++
        
        # Enforce rate limit before next thread
        $elapsed = $stopwatch.ElapsedMilliseconds
        $sleepTime = [math]::Max(0, 1100 - $elapsed)
        Start-Sleep -Milliseconds $sleepTime
        continue
    }

    Write-Host "  $newPostCount new post(s) found" -ForegroundColor Cyan

    # Collect download tasks for new posts only
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
    }

    $pending = $tasks | Where-Object { -not (Test-Path $_.Dest) }

    if ($pending.Count -gt 0) {
        $delayMsg = if ($DelayMs -gt 0) { ", ${DelayMs}ms delay" } else { "" }
        Write-Host "  Downloading $($pending.Count) files ($Concurrency concurrent$delayMsg) ..." -ForegroundColor Cyan

        $pool = [RunspaceFactory]::CreateRunspacePool(1, $Concurrency)
        $pool.Open()

        $downloadScript = {
            param($Url, $Dest, $TimeoutSeconds, $DelayMs)
            if ($DelayMs -gt 0) {
                Start-Sleep -Milliseconds $DelayMs
            }
            $maxTries = 3
            $try = 1
            while ($try -le $maxTries) {
                try {
                    [Void][System.Reflection.Assembly]::LoadWithPartialName("System.Net.Http")
                    $client = New-Object System.Net.Http.HttpClient
                    if ($TimeoutSeconds -gt 0) {
                        $client.Timeout = [System.TimeSpan]::FromSeconds($TimeoutSeconds)
                    }
                    $client.DefaultRequestHeaders.UserAgent.ParseAdd("4chan-archiver/1.1")
                    
                    $response = $client.GetAsync($Url).GetAwaiter().GetResult()
                    if (-not $response.IsSuccessStatusCode) {
                        $statusCode = [int]$response.StatusCode
                        $client.Dispose()
                        if (($statusCode -eq 429 -or $statusCode -ge 500) -and $try -lt $maxTries) {
                            Start-Sleep -Milliseconds ($try * 1000)
                            $try++
                            continue
                        }
                        return @{ Success = $false; Error = "HTTP $statusCode" }
                    }
                    $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                    $fileStream = New-Object System.IO.FileStream($Dest, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                    $stream.CopyTo($fileStream)
                    $fileStream.Dispose()
                    $stream.Dispose()
                    $client.Dispose()
                    return @{ Success = $true }
                } catch {
                    if ($try -lt $maxTries) {
                        Start-Sleep -Milliseconds ($try * 1000)
                        $try++
                    } else {
                        return @{ Success = $false; Error = $_.Exception.Message }
                    }
                }
            }
        }

        $runspaces = [System.Collections.ArrayList]::new()
        $total = $pending.Count
        $completed = 0
        $dlFailed = 0

        try {
            foreach ($task in $pending) {
                $ps = [PowerShell]::Create().AddScript($downloadScript).AddArgument($task.Url).AddArgument($task.Dest).AddArgument(30).AddArgument($DelayMs)
                $ps.RunspacePool = $pool
                [void]$runspaces.Add(@{
                    Pipe   = $ps
                    Handle = $ps.BeginInvoke()
                    Task   = $task
                })

                if ($DelayMs -gt 0) {
                    Start-Sleep -Milliseconds $DelayMs
                }
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
                                Write-Host "    [$completed/$total] $($rs.Task.Name)" -ForegroundColor Green
                            }
                        } else {
                            $dlFailed++
                            if ($rs.Task.Type -eq "image") {
                                $err = if ($result) { $result[0].Error } else { "unknown" }
                                Write-Host "    [$completed/$total] FAILED: $($rs.Task.Name) - $err" -ForegroundColor Red
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

        if ($dlFailed -gt 0) {
            Write-Host "  $dlFailed download(s) failed" -ForegroundColor Yellow
        }
    }

    # Save updated thread.json (BOM-less UTF-8)
    [System.IO.File]::WriteAllText($jsonPath, $response.Content)

    # Regenerate HTML using update-html logic
    try {
        & (Join-Path $PSScriptRoot "update-html.ps1") -ArchiveName $folder.Name
        Write-Host "  UPDATED - $newPostCount new posts" -ForegroundColor Green
        $updated++
    } catch {
        Write-Host "  HTML generation error: $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }

    # Dynamic Rate Limiting before next thread
    $elapsed = $stopwatch.ElapsedMilliseconds
    $sleepTime = [math]::Max(0, 1100 - $elapsed)
    Start-Sleep -Milliseconds $sleepTime
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Results" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host " Updated:  $updated" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host " Skipped:  $skipped (up to date)" -ForegroundColor DarkGray
}
if ($removed -gt 0) {
    Write-Host " Removed:  $removed (404, preserved locally)" -ForegroundColor Yellow
}
if ($errors -gt 0) {
    Write-Host " Errors:   $errors" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Green

