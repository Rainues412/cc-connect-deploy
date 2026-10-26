param([string]$OutputDirectory='D:\Software\AI\Codex\04_Codex工具与记录\cc-connect监控无窗口修复_2026-10-26\logs')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$fixture=Join-Path $OutputDirectory ('launcher-fixture-'+[Guid]::NewGuid().ToString('N')+' 中文 path')
$results=New-Object 'Collections.Generic.List[object]'
$active=New-Object 'Collections.Generic.List[Diagnostics.Process]'
function Assert-Test([bool]$Passed,[string]$Name){
    $results.Add([pscustomobject]@{Name=$Name;Passed=$Passed})
    if(-not $Passed){throw "Failed: $Name"}
}
function Start-Launcher([string]$Mode){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $fixture 'bin\BackgroundLauncher.exe'
    $info.Arguments=$Mode;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.EnvironmentVariables['TEMP']=Join-Path $fixture 'tmp'
    $info.EnvironmentVariables['TMP']=Join-Path $fixture 'tmp'
    $process=[Diagnostics.Process]::Start($info);$active.Add($process)
    return $process
}
function Wait-Exit($Process,[int]$Code,[string]$Name){
    if(-not $Process.WaitForExit(15000)){throw "Timed out: $Name"}
    Assert-Test ($Process.ExitCode -eq $Code) $Name
}
function Wait-File([string]$Path){
    $deadline=(Get-Date).AddSeconds(15)
    while(-not(Test-Path -LiteralPath $Path)){
        if((Get-Date) -gt $deadline){throw "Timed out waiting for $Path"}
        Start-Sleep -Milliseconds 100
    }
    Start-Sleep -Milliseconds 200
}
try{
    foreach($dir in @('bin','monitor','startup','tmp')){New-Item -ItemType Directory -Path (Join-Path $fixture $dir)|Out-Null}
    Copy-Item -LiteralPath (Join-Path $root 'bin\BackgroundLauncher.exe') -Destination (Join-Path $fixture 'bin\BackgroundLauncher.exe')
    $bytes=[IO.File]::ReadAllBytes((Join-Path $fixture 'bin\BackgroundLauncher.exe'))
    $pe=[BitConverter]::ToInt32($bytes,60)
    Assert-Test ([BitConverter]::ToUInt16($bytes,$pe+92) -eq 2) 'GUI subsystem does not allocate a console'
    Wait-Exit (Start-Launcher 'invalid') 2 'Reject unknown entry point'
    Wait-Exit (Start-Launcher 'monitor extra') 2 'Reject extra arguments'
    Wait-Exit (Start-Launcher 'notice') 2 'Reject notice without body'
    Wait-Exit (Start-Launcher 'monitor') 3 'Missing script produces failure'
    $monitor=Join-Path $fixture 'monitor\token-monitor.ps1'
    Set-Content -LiteralPath $monitor -Encoding UTF8 -Value 'exit 37'
    Wait-Exit (Start-Launcher 'monitor') 37 'Forward monitor exit code'
    Set-Content -LiteralPath (Join-Path $fixture 'startup\start-cc-connect.ps1') -Encoding UTF8 -Value 'exit 19'
    Wait-Exit (Start-Launcher 'startup') 19 'Forward startup exit code'
    $notice=@'
param([string]$Body)
$Body|ConvertTo-Json|Set-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'notice.json') -Encoding UTF8
exit 23
'@
    Set-Content -LiteralPath (Join-Path $fixture 'monitor\show-notice.ps1') -Encoding UTF8 -Value $notice
    # Replace the toast with a harmless fixture: testing sends no notification.
    Wait-Exit (Start-Launcher 'notice "notice \"quoted\" C:\folder\\"') 23 'Forward notice exit code'
    Assert-Test ((Get-Content -LiteralPath (Join-Path $fixture 'notice.json') -Raw|ConvertFrom-Json) -eq 'notice "quoted" C:\folder\') 'Notice body preserves quotes and trailing backslash'
    # Generate more than a pipe buffer on both streams; the launcher must keep draining.
    Set-Content -LiteralPath $monitor -Encoding UTF8 -Value '1..2048|ForEach-Object{[Console]::Out.WriteLine(("x"*1024));[Console]::Error.WriteLine(("y"*1024))};exit 0'
    Wait-Exit (Start-Launcher 'monitor') 0 'Drain stdout and stderr without deadlock'
    $probe=@'
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class HiddenProbe{[DllImport("kernel32.dll")]public static extern IntPtr GetConsoleWindow();}'
$value=@{Pid=$PID;Console=[HiddenProbe]::GetConsoleWindow().ToInt64()}
$value|ConvertTo-Json|Set-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'probe.json')
Start-Sleep -Seconds 120
'@
    Set-Content -LiteralPath $monitor -Encoding UTF8 -Value $probe
    $running=Start-Launcher 'monitor';$probePath=Join-Path $fixture 'probe.json';Wait-File $probePath
    $state=Get-Content -LiteralPath $probePath -Raw|ConvertFrom-Json
    Assert-Test ($state.Console -eq 0) 'PowerShell child has no console'
    Assert-Test (-not $running.HasExited) 'Launcher waits while monitor is running'
    $running.Kill();[void]$running.WaitForExit(5000)
    $deadline=(Get-Date).AddSeconds(5)
    while((Get-Process -Id $state.Pid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100}
    Assert-Test (-not(Get-Process -Id $state.Pid -ErrorAction SilentlyContinue)) 'Killed launcher leaves no monitor orphan'
    # Startup is intentionally outside the monitor job so new PM2 daemons survive.
    $startup=@'
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$info.Arguments='-NoProfile -NonInteractive -Command Start-Sleep -Seconds 120'
$info.UseShellExecute=$false;$info.CreateNoWindow=$true
$p=[Diagnostics.Process]::Start($info)
$p.Id|Set-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'persistent.pid')
exit 0
'@
    Set-Content -LiteralPath (Join-Path $fixture 'startup\start-cc-connect.ps1') -Encoding UTF8 -Value $startup
    Wait-Exit (Start-Launcher 'startup') 0 'Startup completes after spawning persistent service'
    $serviceId=[int](Get-Content -LiteralPath (Join-Path $fixture 'persistent.pid'))
    Assert-Test ([bool](Get-Process -Id $serviceId -ErrorAction SilentlyContinue)) 'Startup preserves persistent service'
}finally{
    foreach($process in $active){try{if(-not $process.HasExited){$process.Kill();[void]$process.WaitForExit(5000)}}catch{};$process.Dispose()}
    if(-not $serviceId -and (Test-Path -LiteralPath (Join-Path $fixture 'persistent.pid'))){$serviceId=[int](Get-Content -LiteralPath (Join-Path $fixture 'persistent.pid'))}
    if($serviceId){$service=Get-Process -Id $serviceId -ErrorAction SilentlyContinue;if($service){$service.Kill();[void]$service.WaitForExit(5000);$service.Dispose()}}
    if($state -and $state.Pid){Stop-Process -Id $state.Pid -ErrorAction SilentlyContinue}
    if(-not(Test-Path -LiteralPath $OutputDirectory)){New-Item -ItemType Directory -Path $OutputDirectory|Out-Null}
    $results|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputDirectory 'background-launcher-tests.json') -Encoding UTF8
    # This GUID fixture contains only this test's generated files, never deployment data.
    if((Test-Path -LiteralPath $fixture) -and (Split-Path $fixture) -eq [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')){Remove-Item -LiteralPath $fixture -Recurse}
}
$results|Format-Table -AutoSize
