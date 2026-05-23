# auto-push.ps1 - Watches summer-cut for changes and pushes to GitHub
# Usage: powershell -ExecutionPolicy Bypass -File auto-push.ps1
# To run on startup: Win+R > shell:startup > paste a shortcut to this script
#
# Detection: FileSystemWatcher for normal edits + git-status polling every
# 30s for writes that bypass FS events (e.g. Cowork / mounted-folder syncs).

Import-Module BurntToast -ErrorAction SilentlyContinue

$repoPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debounceSeconds = 8
$pollSeconds = 30
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
            $age = (Get-Date) - (Get-Item $lockPath).LastWriteTime
            if ($age.TotalSeconds -gt 5) {
                Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
                Write-Host "  Cleaned stale $lockName" -ForegroundColor Yellow
            }
        }
    }
}

function Push-IfDirty($source) {
    Push-Location $repoPath
    try {
        Clear-GitLocks

        $status = git status --porcelain $watchFiles 2>&1
        if (-not $status) { return $false }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

        git add $watchFiles 2>&1 | Out-Null

        $commitOut = git commit -m "auto: dashboard update $timestamp" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[$timestamp] Commit failed, retrying in 3s..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
            Clear-GitLocks
            $commitOut = git commit -m "auto: dashboard update $timestamp" 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            $committed = ($commitOut | Select-String "^\s" | ForEach-Object { $_.Line.Trim() }) -join ", "
            git push 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$timestamp] Pushed ($source): $committed" -ForegroundColor Green
                Send-Notification "Dashboard Updated" "Pushed at $timestamp"
            } else {
                Write-Host "[$timestamp] Push failed, will retry on next change" -ForegroundColor Red
                Send-Notification "Push FAILED" "Commit OK but push failed. Will retry." $true
            }
        } else {
            Write-Host "[$timestamp] Commit failed after retry: $commitOut" -ForegroundColor Red
        }
        return $true
    } finally {
        Pop-Location
    }
}

Send-Notification "Summer Cut" "Watcher started. Monitoring data.json, briefing.md, index.html"
Write-Host "Watching $repoPath for changes to: $($watchFiles -join ', ')" -ForegroundColor Cyan
Write-Host "Debounce: ${debounceSeconds}s | Poll: ${pollSeconds}s | Press Ctrl+C to stop" -ForegroundColor DarkGray

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $repoPath
$watcher.Filter = "*.*"
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite
$watcher.EnableRaisingEvents = $false

$lastPush = [DateTime]::MinValue
$lastPoll = [DateTime]::UtcNow

while ($true) {
    # Wait up to 2s for a filesystem event
    $result = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Changed, 2000)

    $now = Get-Date

    # --- Path 1: FileSystemWatcher event ---
    if (-not $result.TimedOut) {
        $changed = $result.Name
        if ($changed -in $watchFiles) {
            Start-Sleep -Seconds $debounceSeconds

            # Drain queued events
            do {
                $extra = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Changed, 500)
            } while (-not $extra.TimedOut)

            if (($now - $lastPush).TotalSeconds -ge 10) {
                if (Push-IfDirty "watcher") {
                    $lastPush = $now
                    $lastPoll = [DateTime]::UtcNow
                }
            }
        }
    }

    # --- Path 2: Polling fallback for writes that bypass FS events ---
    if (([DateTime]::UtcNow - $lastPoll).TotalSeconds -ge $pollSeconds) {
        $lastPoll = [DateTime]::UtcNow
        if (($now - $lastPush).TotalSeconds -ge 10) {
            if (Push-IfDirty "poll") {
                $lastPush = $now
            }
        }
    }
}
