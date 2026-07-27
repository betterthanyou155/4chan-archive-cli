# 4chan Thread Archiver Utility Functions

# Escape HTML entities
function Escape-Html($text) {
    if (-not $text) { return "" }
    return $text.Replace("&","&amp;").Replace("<","&lt;").Replace(">","&gt;").Replace('"',"&quot;").Replace("'","&#39;")
}

# Convert 4chan comment HTML to display HTML (already mostly HTML, just clean up and parse greentext)
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

# Generate a clean, filesystem-safe slug from thread title or comment text
function Get-SanitizedSlug($text) {
    if (-not $text) { return "" }
    # Strip HTML tags
    $clean = $text -replace '<[^>]+>', ' '
    # Decode HTML entities
    try {
        $clean = [System.Net.WebUtility]::HtmlDecode($clean)
    } catch {
        $clean = $clean.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&quot;", '"').Replace("&#39;", "'")
    }
    # Lowercase
    $clean = $clean.ToLowerInvariant()
    # Replace non-alphanumeric chars (keep hyphens and spaces) with spaces
    $clean = $clean -replace '[^a-z0-9\s-]', ' '
    # Replace spaces and multiple hyphens/underscores with single hyphens
    $clean = $clean -replace '[\s_]+', '-'
    $clean = $clean -replace '-+', '-'
    # Trim leading/trailing hyphens
    $clean = $clean.Trim('-')
    # Truncate to max 50 chars
    if ($clean.Length -gt 50) {
        $clean = $clean.Substring(0, 50).TrimEnd('-')
    }
    return $clean
}

# Find existing archive directory for a given board and thread ID regardless of title slug
function Get-ExistingArchiveDir($archiveRoot, $board, $threadId) {
    if (-not (Test-Path $archiveRoot)) { return $null }
    $matching = Get-ChildItem $archiveRoot -Directory | Where-Object { $_.Name -match "^${board}_${threadId}(?:_.*)?$" } | Select-Object -First 1
    if ($matching) {
        return $matching.FullName
    }
    return $null
}

# Parse board, thread ID, and optional title slug from an archive folder name
function Parse-ArchiveFolderName($folderName) {
    if ($folderName -match '^([a-z0-9]+)_(\d+)(?:_(.*))?$') {
        return @{
            Board    = $Matches[1]
            ThreadId = $Matches[2]
            Slug     = $Matches[3]
        }
    }
    return $null
}

