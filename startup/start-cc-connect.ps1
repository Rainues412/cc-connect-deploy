#requires -Version 7.0
$ErrorActionPreference='Stop'
. 'D:\coding\cc-connect-deploy\scripts\runtime-common.ps1'
$binary=Join-Path $env:APPDATA 'npm\node_modules\cc-connect\bin\cc-connect.exe'
$powerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$monitor=Join-Path $script:CcRoot 'monitor\token-monitor.ps1'
$env:PATH=(Split-Path $script:CcNode)+';'+(Join-Path $env:APPDATA 'npm')+';'+$env:PATH
if(-not(Test-Path -LiteralPath $script:CcRuntime)){New-Item -ItemType Directory -Path $script:CcRuntime|Out-Null}
$log=Join-Path $script:CcRuntime 'startup.log'
function Ensure-CcProcess([string]$Name,[string]$Binary,[string[]]$ProcessArgs){
    $entries=@(Get-CcProcesses|Where-Object name -eq $Name)
    if($entries.Count -gt 1){throw "Duplicate PM2 entry: $Name"}
    if($entries.Count -eq 1){
        $entry=$entries[0]
        if($entry.pm2_env.pm_exec_path -ne $Binary -or ($entry.pm2_env.args -join ' ') -ne ($ProcessArgs -join ' ')){throw "Unexpected PM2 command for $Name; existing entry left intact."}
        if($entry.pm2_env.status -ne 'online'){Invoke-CcNode -Arguments @($script:CcPm2,'restart',$Name) | Out-Null}
    }else{
        $arguments=@($script:CcPm2,'start',$Binary,'--name',$Name,'--interpreter','none','--cwd',$env:USERPROFILE,'--exp-backoff-restart-delay','2000')
        Invoke-CcNode -Arguments ($arguments+@('--')+$ProcessArgs)|Out-Null
    }
}
$mutex=New-Object Threading.Mutex($false,'Local\CCConnectStartup');$owns=$false
try{
    try{$owns=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owns=$true}
    if(-not $owns){exit 0}
    foreach($file in @($binary,$powerShell,$monitor,$script:CcConfig,$script:CcPm2)){if(-not(Test-Path -LiteralPath $file)){throw "Required file missing: $file"}}
    $lastFailure=$null
    for($attempt=1;$attempt -le 3;$attempt++){
        try{
            Invoke-CcNode -Arguments @($script:CcPm2,'ping')|Out-Null
            Ensure-CcProcess 'wechat' $binary @('--config',$script:CcConfig)
            $task=Get-ScheduledTask -TaskName 'CCConnect-Monitor' -ErrorAction Stop
            if($task.State -ne 'Running'){Start-ScheduledTask -TaskName 'CCConnect-Monitor'}
            Invoke-CcNode -Arguments @($script:CcPm2,'save')|Out-Null
            $deadline=(Get-Date).AddSeconds(45);$healthy=$false
            do{
                if(Test-Path -LiteralPath (Join-Path $script:CcRuntime 'monitor-status.json')){
                    try{
                        $state=Get-Content -LiteralPath (Join-Path $script:CcRuntime 'monitor-status.json') -Raw|ConvertFrom-Json
                        $entries=@(Get-CcProcesses);$task=Get-ScheduledTask -TaskName 'CCConnect-Monitor'
                        $monProcess=Get-CimInstance Win32_Process -Filter ('ProcessId='+$state.Pid) -ErrorAction SilentlyContinue
                        $bridge=@($entries|Where-Object name -eq 'wechat')
                        $healthy=($task.State -eq 'Running' -and $monProcess -and $monProcess.CommandLine -match 'cc-connect-deploy.*token-monitor.ps1' -and $bridge.Count -eq 1 -and $state.BridgePid -eq $bridge[0].pid -and ((Get-Date)-[DateTime]$state.CheckedAt).TotalSeconds -lt 45 -and -not $state.Error -and $state.BridgeState -eq 'online')
                    }catch{}
                }
                if(-not $healthy){Start-Sleep -Seconds 1}
            }while(-not $healthy -and (Get-Date) -lt $deadline)
            if(-not $healthy){throw 'Monitor did not publish a fresh healthy handshake.'}
            Add-Content -LiteralPath $log -Encoding UTF8 -Value "$(Get-Date -Format o) wechat and supervised monitor healthy; attempt=$attempt."
            exit 0
        }catch{
            $lastFailure=$_.Exception.Message
            Add-Content -LiteralPath $log -Encoding UTF8 -Value "$(Get-Date -Format o) attempt=$attempt failed: $lastFailure"
            if($attempt -lt 3){Start-Sleep -Seconds (3*$attempt)}
        }
    }
    throw $lastFailure
}catch{
    Add-Content -LiteralPath $log -Encoding UTF8 -Value "$(Get-Date -Format o) startup failed: $($_.Exception.Message)"
    exit 1
}finally{if($owns){$mutex.ReleaseMutex()};$mutex.Dispose()}
