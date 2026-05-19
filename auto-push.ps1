# auto-push.ps1 - Watches summer-cut for changes and pushes to GitHub
# Usage: powershell -ExecutionPolicy Bypass -File auto-push.ps1
# To run on startup: Win+R > shell:startup > paste a shortcut to this script

Import-Module BurntToast -ErrorAction SilentlyContinue

$repoPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debounceSeconds = 8
$watchFiles = @("data.json", "briefing.md", "index.html")

function Send-Notification($title, $message, $isError) {
    if ($isError) {
        New-BurntToastNotification -Text $title, $message -UniqueIdentifier "summer-cut"
    } else {
        New-BurntToastNotification -Text $title, $message -UniqueIdentifier "summer-cut"
    }
}

function Clear-GitLocks {
    foreach ($lockName in @("index.lock", "HEAD.lock")) {
        $lockPath = Join-Path $repoPath ".git\$lockName"
        if (Test-Path $lockPath) {
            # Only remove if older than 5 seconds (not from a live git process)
            $age = (Get-Date) - (Get-Item $lockPath).LastWriteTime
            if ($age.TotalSeconds -gt 5) {
                Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
                Write-Host "  Cleaned stale $lockName" -ForegroundColor Yellow
            }
        }
    }
}

Send-Notification "Summer Cut" "Watcher started. Monitoring data.json, briefing.md, index.html"
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
            # Debounce: wait for all writes to settle before pushing
            Start-Sleep -Seconds $debounceSeconds

            # Drain any queued events so we don't double-fire
            do {
                $extra = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Changed, 500)
            } while (-not $extra.TimedOut)

            $now = Get-Date
            if (($now - $lastPush).TotalSeconds -lt 10) {
                continue
            }

            Push-Location $repoPath
            try {
                Clear-GitLocks

                $status = git status --porcelain $watchFiles 2>&1
                if ($status) {
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

                    # Stage all watched files at once
                    git add $watchFiles 2>&1 | Out-Null

                    $commitOut = git commit -m "auto: dashboard update $timestamp" 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "[$timestamp] Commit failed, retrying in 3s..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 3
                        Clear-GitLocks
                        $commitOut = git commit -m "auto: dashboard update $timestamp" 2>&1
                    }

                    if ($LASTEXITCODE -eq 0) {
                        # Parse which files were committed
                        $committed = ($commitOut | Select-String "^\s" | ForEach-Object { $_.Line.Trim() }) -join ", "
                        git push 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "[$timestamp] Pushed: $committed" -ForegroundColor Green
                            Send-Notification "Dashboard Updated" "Pushed at $timestamp"
                        } else {
                            Write-Host "[$timestamp] Push failed, will retry on next change" -ForegroundColor Red
                            Send-Notification "Push FAILED" "Commit OK but push failed. Will retry." $true
                        }
                    } else {
                        Write-Host "[$timestamp] Commit failed after retry: $commitOut" -ForegroundColor Red
                    }
                    $lastPush = $now
                }
            } finally {
                Pop-Location
            }
        }
    }
}
