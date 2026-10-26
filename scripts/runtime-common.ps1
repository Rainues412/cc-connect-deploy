$script:CcRoot = 'D:\coding\cc-connect-deploy'
$script:CcRuntime = 'D:\Software\AI\Codex\04_Codex工具与记录\cc-connect运行记录'
$script:CcConfig = Join-Path $env:USERPROFILE '.claude\skills\cc-connect\config.toml'
$script:CcNode = Join-Path $env:ProgramFiles 'nodejs\node.exe'
$script:CcPm2 = Join-Path $env:APPDATA 'npm\node_modules\pm2\bin\pm2'

function Get-CcAccounts {
    $text = Get-Content -LiteralPath $script:CcConfig -Raw -Encoding UTF8
    foreach ($section in ([regex]::Split($text, '(?m)^\s*\[\[projects\]\]\s*$') | Select-Object -Skip 1)) {
        $values = @{}
        foreach ($key in @('name','account_id','token','base_url','allow_from','work_dir')) {
            $match = [regex]::Match($section, '(?m)^\s*' + $key + '\s*=\s*("(?:[^"\\]|\\.)*")\s*(?:#.*)?$')
            if ($match.Success) { $values[$key] = $match.Groups[1].Value | ConvertFrom-Json }
        }
        if (-not $values.name -or -not $values.account_id -or -not $values.token) { throw 'Missing WeChat project/account credentials in config.' }
        [pscustomobject]$values
    }
}

function Invoke-CcNode([string[]]$Arguments, [int]$TimeoutSeconds = 20) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:CcNode
    $info.Arguments = (@($Arguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }) -join ' ')
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill(); throw 'Node/PM2 operation timed out.' }
        $output = $stdout.GetAwaiter().GetResult(); $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('Node/PM2 operation failed: ' + $errorText.Substring(0,[Math]::Min(300,$errorText.Length))) }
        return $output
    } finally { $process.Dispose() }
}

function Get-CcProcesses {
    $pidFile = Join-Path $env:USERPROFILE '.pm2\pm2.pid'
    if (-not (Test-Path -LiteralPath $pidFile)) { return }
    $daemonId = 0
    if (-not [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$daemonId)) { return }
    $daemon = Get-CimInstance Win32_Process -Filter "ProcessId=$daemonId" -ErrorAction SilentlyContinue
    if (-not $daemon -or $daemon.Name -ne 'node.exe' -or $daemon.CommandLine -notmatch 'pm2.*Daemon\.js') { return }
    $json = Invoke-CcNode -Arguments @((Join-Path $script:CcRoot 'scripts\pm2-status.cjs'))
    $items = $json | ConvertFrom-Json
    foreach ($item in $items) { Write-Output $item }
}

function Write-CcJson([string]$Path, $Value) {
    $json = $Value | ConvertTo-Json -Depth 12
    $temp = $Path + '.' + $PID + '.tmp'
    [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [IO.File]::Move($temp, $Path) }
}
