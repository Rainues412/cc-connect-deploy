$ErrorActionPreference='Stop'
$taskName='CCConnect-Monitor'
$binary='D:\coding\cc-connect-deploy\bin\BackgroundLauncher.exe'
$arguments='monitor'
if(-not(Test-Path -LiteralPath $binary)){throw 'Build the background launcher before registering the monitor.'}
$oldBinary=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$oldArguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\coding\cc-connect-deploy\monitor\token-monitor.ps1"'
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($existing){
    $current=($existing.Actions.Count -eq 1 -and $existing.Actions.Execute -eq $binary -and $existing.Actions.Arguments -eq $arguments)
    $legacy=($existing.Actions.Count -eq 1 -and $existing.Actions.Execute -eq $oldBinary -and $existing.Actions.Arguments -eq $oldArguments)
    if(-not $current -and -not $legacy){throw 'The monitor task name belongs to another command; existing task left intact.'}
    $periodic=@($existing.Triggers|Where-Object {$_.Repetition.Interval -eq 'PT1M'})
    if($current -and $existing.Settings.RestartCount -eq 99 -and $existing.Settings.ExecutionTimeLimit -eq 'PT0S' -and $periodic.Count -eq 1){return}
}
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$action=New-ScheduledTaskAction -Execute $binary -Argument $arguments -WorkingDirectory 'D:\coding\cc-connect-deploy'
$trigger=@(
    (New-ScheduledTaskTrigger -AtLogOn -User $user),
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10) -RepetitionInterval ([TimeSpan]::FromMinutes(1)))
)
$settings=New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 99 -RestartInterval ([TimeSpan]::FromMinutes(1)) -MultipleInstances IgnoreNew
$principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'cc-connect per-account health and token monitor. No session deletion or rewriting.' -Force|Out-Null
