param(
    [ValidateRange(1,16)]
    [int]$Concurrency = 4,
    [ValidateRange(0,10000)]
    [int]$DelayMs = 0
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  4chan Thread Archiver (Interactive Mode)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Paste a thread URL and press Enter to archive it."
Write-Host "  Settings: Concurrency=$Concurrency, Delay=${DelayMs}ms" -ForegroundColor DarkGray
Write-Host "  Type 'exit', 'quit', or 'q' to exit.`n"

while ($true) {
    $url = Read-Host "URL"
    $trimmedUrl = $url.Trim()
    
    if ($trimmedUrl -eq "" -or $trimmedUrl -match '^(exit|quit|q)$') {
        Write-Host "`nGoodbye!" -ForegroundColor Cyan
        break
    }

    # Validate URL
    if ($trimmedUrl -match '(?:boards\.(?:4chan|4channel)\.org|(?:4chan|4channel)\.org|a\.4cdn\.org)/([a-z0-9]+)/thread/(\d+)') {
        try {
            # Execute archive.ps1 in the same session
            & "$PSScriptRoot\archive.ps1" -Url $trimmedUrl -Concurrency $Concurrency -DelayMs $DelayMs
        } catch {
            Write-Host "An error occurred during archival: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "ERROR: Invalid 4chan thread URL." -ForegroundColor Red
        Write-Host "Expected format: https://boards.4chan.org/{board}/thread/{id}" -ForegroundColor Gray
    }
    Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
}

