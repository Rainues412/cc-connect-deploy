# cc-connect token expiry auto-monitor
# Watches pm2 logs, detects token expiry, sends toast notification, opens QR scan window
# Also detects 400 API errors and auto-clears corrupted sessions
# Supports dual WeChat accounts (wechat-claude + wechat-claude-2)

$ConfigPath = "$env:USERPROFILE\.claude\skills\cc-connect\config.toml"
$AllProjects = @("wechat-claude", "wechat-claude-2")
$CheckInterval = 30
$ErrLogPath = "$env:USERPROFILE\.pm2\logs\wechat-error.log"
$OutLogPath = "$env:USERPROFILE\.pm2\logs\wechat-out.log"
$SessionDir = "$env:USERPROFILE\.cc-connect\sessions"
$MaxHistoryLength = 100

function Show-Toast {
    param([string]$Title, [string]$Body)
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $tpl = '<toast><visual><binding template="ToastGeneric"><text>' + $Title + '</text><text>' + $Body + '</text></binding></visual><audio src="ms-winsoundevent:Notification.Default"/></toast>'
        $xml.LoadXml($tpl)
        $notif = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("cc-connect").Show($notif)
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($Body, $Title, "OK", "Warning") | Out-Null
    }
}

$expirePatterns = @(
    'token.*expir',
    'token.*invalid',
    'token.*expired',
    'session.*expired',
    'session.*invalid',
    'HTTP 401',
    'auth.*fail',
    'login.*expired',
    'login.*required',
    'need.*relogin',
    'need.*rescan',
    'qrcode.*expired',
    're-login',
    're-scan',
    'relogin',
    'platform.*error',
    'poll.*error',
    'ilink.*error',
    'ilink.*fail'
)

$falsePositivePatterns = @(
    'acquired instance lock',
    'another cc-connect instance'
)

$corruptPatterns = @(
    'API Error.*400',
    'bad response status code 400',
    'HTTP 400'
)

function Repair-CorruptedSessions {
    param([string]$Project)

    $sessionFile = Join-Path $SessionDir "$Project.json"
    if (-not (Test-Path $sessionFile)) { return }

    try {
        $content = Get-Content $sessionFile -Raw -Encoding UTF8
        $json = $content | ConvertFrom-Json

        $corrupted = $false
        $totalHistory = 0

        foreach ($sessionKey in $json.sessions.PSObject.Properties.Name) {
            $session = $json.sessions.$sessionKey
            if ($session.history) {
                $totalHistory += $session.history.Count
                foreach ($msg in $session.history) {
                    if ($msg.role -eq "assistant" -and $msg.content -match "API Error.*400") {
                        $corrupted = $true
                        break
                    }
                    if ($msg.role -eq "user" -and $msg.content -eq "") {
                        $corrupted = $true
                        break
                    }
                }
            }
            if ($corrupted) { break }
        }

        if ($corrupted) {
            $ts1 = Get-Date
            Write-Host "[$ts1] Corrupted session in $Project! Clearing..." -ForegroundColor Yellow

            $json.sessions = @{}
            $json.active_session = @{}
            $json.user_sessions = @{}
            $json.counter = 0

            $json | ConvertTo-Json -Depth 10 | Set-Content $sessionFile -Encoding UTF8

            Show-Toast -Title "Session Auto-Repaired" -Body "$Project - Corrupted history cleared"
            $ts2 = Get-Date
            Write-Host "[$ts2] Session repaired: $Project" -ForegroundColor Green
        }

        if (-not $corrupted -and $totalHistory -gt $MaxHistoryLength) {
            $ts3 = Get-Date
            Write-Host "[$ts3] History too long ($totalHistory > $MaxHistoryLength) in $Project, trimming..." -ForegroundColor Yellow

            foreach ($sk in @($json.sessions.PSObject.Properties.Name)) {
                $s = $json.sessions.$sk
                if ($s.history -and $s.history.Count -gt $MaxHistoryLength) {
                    $s.history = @($s.history | Select-Object -Last 50)
                }
            }

            $json | ConvertTo-Json -Depth 10 | Set-Content $sessionFile -Encoding UTF8
            Show-Toast -Title "Session Trimmed" -Body "$Project - History limited"
        }
    } catch {
        $ts4 = Get-Date
        Write-Host "[$ts4] Failed to repair $Project : $_" -ForegroundColor Red
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " cc-connect Token Monitor" -ForegroundColor Cyan
Write-Host " Error log: $ErrLogPath" -ForegroundColor Cyan
Write-Host " Projects: $($AllProjects -join ', ')" -ForegroundColor Cyan
Write-Host " Checking every ${CheckInterval}s" -ForegroundColor Cyan
Write-Host " Press Ctrl+C to stop" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$lastAlertTime = [DateTime]::MinValue
$lastReadPos = 0

while ($true) {
    try {
        $newLogs = ""

        if (Test-Path $ErrLogPath) {
            $sz = (Get-Item $ErrLogPath).Length
            if ($sz -lt $lastReadPos) { $lastReadPos = 0 }
            if ($sz -gt $lastReadPos) {
                $fs = [System.IO.File]::Open($ErrLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $fs.Seek($lastReadPos, [System.IO.SeekOrigin]::Begin) | Out-Null
                $sr = New-Object System.IO.StreamReader($fs)
                $newLogs = $sr.ReadToEnd()
                $sr.Close()
                $fs.Close()
                $lastReadPos = $sz
            }
        }

        if (Test-Path $OutLogPath) {
            $recent = Get-Content $OutLogPath -Tail 50 -ErrorAction SilentlyContinue
            if ($recent) { $newLogs += ($recent -join "`n") }
        }

        if ($newLogs.Length -eq 0) {
            Start-Sleep -Seconds $CheckInterval
            continue
        }

        $expired = $false
        $matchedLine = ""
        $matchedPattern = ""
        $expiredProject = ""
        $corruptDetected = $false

        $lines = $newLogs -split "`n"
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if ($trimmed.Length -eq 0) { continue }

            $lineIsFP = $false
            foreach ($fp in $falsePositivePatterns) {
                if ($trimmed -imatch $fp) { $lineIsFP = $true; break }
            }
            if ($lineIsFP) { continue }

            foreach ($cpat in $corruptPatterns) {
                if ($trimmed -imatch $cpat) {
                    $corruptDetected = $true
                    $corruptProject = ""

                    foreach ($proj in $AllProjects) {
                        if ($trimmed -imatch [regex]::Escape($proj)) {
                            $corruptProject = $proj
                            break
                        }
                    }
                    if (-not $corruptProject) { $corruptProject = $AllProjects[0] }

                    $ts5 = Get-Date
                    Write-Host "[$ts5] 400 error detected for $corruptProject" -ForegroundColor Red
                    Write-Host "  Log: $trimmed" -ForegroundColor DarkGray

                    Repair-CorruptedSessions -Project $corruptProject

                    pm2 restart wechat 2>&1 | Out-Null
                    break
                }
            }
            if ($corruptDetected) { break }

            foreach ($pat in $expirePatterns) {
                if ($trimmed -imatch $pat) {
                    $expired = $true
                    $matchedLine = $trimmed
                    $matchedPattern = $pat
                    break
                }
            }
            if ($expired) { break }
        }

        if ($expired) {
            foreach ($proj in $AllProjects) {
                if ($matchedLine -imatch [regex]::Escape($proj)) {
                    $expiredProject = $proj
                    break
                }
            }
            if (-not $expiredProject) { $expiredProject = $AllProjects[0] }

            $ts6 = Get-Date
            Write-Host "[$ts6] Matched '$matchedPattern' in: $matchedLine" -ForegroundColor DarkYellow
            Write-Host "[$ts6] Expired project: $expiredProject" -ForegroundColor DarkYellow
        }

        if (-not $expired) {
            try {
                $sj = pm2 jlist 2>$null
                if ($sj) {
                    $procs = $sj | ConvertFrom-Json
                    if ($procs -and $procs.Count -gt 0) {
                        $st = $procs[0].pm2_env.status
                        if ($st -eq "errored" -or $st -eq "stopped") {
                            $expired = $true
                            $expiredProject = $AllProjects[0]
                        }
                    }
                }
            } catch { }
        }

        $now = Get-Date
        if ($expired -and ($now - $lastAlertTime).TotalMinutes -gt 5) {
            $lastAlertTime = $now
            Write-Host "[$now] Token expired for '$expiredProject'!" -ForegroundColor Yellow

            Show-Toast -Title "cc-connect Token Expired" -Body "$expiredProject - Opening QR scan window..."

            pm2 stop wechat 2>&1 | Out-Null

            $tmpBat = Join-Path $env:TEMP "cc-connect-rescan.bat"
            $batLines = @()
            $batLines += "@echo off"
            $batLines += "title cc-connect WeChat Re-login"
            $batLines += "echo."
            $batLines += "echo ========================================"
            $batLines += "echo  cc-connect Token Expired"
            $batLines += "echo  Project: $expiredProject"
            $batLines += "echo  Please scan the QR code below"
            $batLines += "echo ========================================"
            $batLines += "echo."
            $batLines += ('cc-connect weixin setup --project {0} --config "{1}"' -f $expiredProject, $ConfigPath)
            $batLines += "echo."
            $batLines += "echo Scan complete! Restarting..."
            $batLines += "pm2 restart wechat"
            $batLines += "echo."
            $batLines += "echo Done! Closing in 5s..."
            $batLines += "timeout /t 5"
            $batLines -join "`r`n" | Out-File -FilePath $tmpBat -Encoding ASCII

            Start-Process cmd.exe -ArgumentList ("/c", "`"$tmpBat`"") -WindowStyle Normal

            Write-Host "[$now] Scan window opened. Waiting..." -ForegroundColor Green

            $waited = 0
            while ($waited -lt 120) {
                Start-Sleep -Seconds 5
                $waited += 5
                try {
                    $cj = pm2 jlist 2>$null
                    if ($cj) {
                        $cp = $cj | ConvertFrom-Json
                        if ($cp -and $cp.Count -gt 0 -and $cp[0].pm2_env.status -eq "online") {
                            $ts7 = Get-Date
                            Write-Host "[$ts7] Back online!" -ForegroundColor Green
                            Show-Toast -Title "cc-connect Reconnected" -Body "$expiredProject restored."
                            if (Test-Path $ErrLogPath) { $lastReadPos = (Get-Item $ErrLogPath).Length }
                            break
                        }
                    }
                } catch { }
            }
        }
    } catch {
        $ts8 = Get-Date
        Write-Host "[$ts8] Error: $_" -ForegroundColor Red
    }

    Start-Sleep -Seconds $CheckInterval
}
