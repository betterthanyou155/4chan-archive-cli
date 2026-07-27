$archiveRoot = Join-Path $PSScriptRoot "archives"

if (-not (Test-Path $archiveRoot)) {
    Write-Host "No archives found." -ForegroundColor Yellow
    exit 0
}

$folders = Get-ChildItem $archiveRoot -Directory
if ($folders.Count -eq 0) {
    Write-Host "No archives found." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "  Archived Threads" -ForegroundColor Cyan
Write-Host "  ================" -ForegroundColor Cyan
Write-Host ""

foreach ($folder in $folders) {
    $htmlPath = Join-Path $folder.FullName "thread.html"
    if (Test-Path $htmlPath) {
        $imgDir = Join-Path $folder.FullName "images"
        $imgCount = 0
        if (Test-Path $imgDir) {
            $imgCount = (Get-ChildItem $imgDir -File).Count
        }
        Write-Host "  $($folder.Name)  [$imgCount files]"
    }
}

Write-Host ""
