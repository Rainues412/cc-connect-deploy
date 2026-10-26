# Repair the existing local deployment. Never bind accounts or recreate live entries.
$ErrorActionPreference='Stop'
. 'D:\coding\cc-connect-deploy\scripts\runtime-common.ps1'
foreach($file in @($script:CcNode,$script:CcPm2,$script:CcConfig)){
    if(-not(Test-Path -LiteralPath $file)){throw "Required existing installation/config is missing: $file. Install dependencies and bind accounts explicitly; this repair script does not do so."}
}
$accounts=@(Get-CcAccounts)
if($accounts.Count -ne 2){throw 'Expected the existing two-account configuration.'}
if(-not(Test-Path -LiteralPath 'D:\coding\cc-connect-deploy\bin\ClaudeGuardLauncher.exe')){& 'D:\coding\cc-connect-deploy\scripts\build-launcher.ps1'}
& 'D:\coding\cc-connect-deploy\scripts\register-monitor.ps1'
$command='"'+(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')+'" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\coding\cc-connect-deploy\startup\start-cc-connect.ps1"'
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if((Get-ItemProperty -LiteralPath $runKey -Name CCConnect -ErrorAction SilentlyContinue).CCConnect -ne $command){
    New-ItemProperty -LiteralPath $runKey -Name CCConnect -PropertyType String -Value $command -Force|Out-Null
}
& 'D:\coding\cc-connect-deploy\startup\start-cc-connect.ps1'
exit $LASTEXITCODE
