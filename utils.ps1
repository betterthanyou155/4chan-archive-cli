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
