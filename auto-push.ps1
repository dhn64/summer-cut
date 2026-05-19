# auto-push.ps1 - Watches summer-cut for changes and pushes to GitHub
# Usage: powershell -ExecutionPolicy Bypass -File auto-push.ps1
# To run on startup: Win+R > shell:startup > paste a shortcut to this script

Import-Module BurntToast -ErrorAction SilentlyContinue

$repoPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debounceSeconds = 5
$watchFiles = @("data.json", "briefing.md", "index.html")

function Send-Notification($title, $message, $isError) {
    if ($isError) {
        New-BurntToastNotification -Text $title, $message -UniqueIdentifier "summer-cut"
    } else {
        New-BurntToastNotification -Text $title, $message -UniqueIdentifier "summer-cut"
    }
}

Send-Notification "Summer Cut" "Watcher started. Monitoring data.json and briefing.md"
Write-Host "Watching $repoPath for changes to: $($watchFiles -join ', ')" -ForegroundColor Cyan
Write-Host "Debounce: ${debounceSeconds}s | Press Ctrl+C to stop" -ForegroundColor DarkGray

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $repoPath
$watcher.Filter = "*.*"
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite
$watcher.EnableRaisingEvents = $false

$lastPush = [DateTime]::MinValue

while ($true) {
    $result = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Changed, 2000)

    if (-not $result.TimedOut) {
        $changed = $result.Name
        if ($changed -in $watchFiles) {
            Start-Sleep -Seconds $debounceSeconds

            $now = Get-Date
            if (($now - $lastPush).TotalSeconds -lt 10) {
                continue
            }

            Push-Location $repoPath
            try {
                $lockFile = Join-Path $repoPath ".git\index.lock"
                if (Test-Path $lockFile) {
                    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                }

                $status = git status --porcelain $watchFiles 2>&1
                if ($status) {
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
                    git add $watchFiles
                    git commit -m "auto: dashboard update $timestamp"
                    git push
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[$timestamp] Pushed: $changed" -ForegroundColor Green
                        Send-Notification "Dashboard Updated" "Pushed $changed at $timestamp"
                    } else {
                        Write-Host "[$timestamp] Push failed, will retry on next change" -ForegroundColor Red
                        Send-Notification "Push FAILED" "Could not push $changed. Will retry on next change." $true
                    }
                    $lastPush = $now
                }
            } finally {
                Pop-Location
            }
        }
    }
}
