#requires -Version 7.0
# Repair the existing local deployment. Never bind accounts or recreate live entries.
$ErrorActionPreference='Stop'
. 'D:\coding\cc-connect-deploy\scripts\runtime-common.ps1'
foreach($file in @($script:CcNode,$script:CcPm2,$script:CcConfig)){
    if(-not(Test-Path -LiteralPath $file)){throw "Required existing installation/config is missing: $file. Install dependencies and bind accounts explicitly; this repair script does not do so."}
}
$accounts=@(Get-CcAccounts)
if($accounts.Count -ne 2){throw 'Expected the existing two-account configuration.'}
& 'D:\coding\cc-connect-deploy\scripts\build-launcher.ps1'
& 'D:\coding\cc-connect-deploy\scripts\register-monitor.ps1'
$command='"D:\coding\cc-connect-deploy\bin\BackgroundLauncher.exe" startup'
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if((Get-ItemProperty -LiteralPath $runKey -Name CCConnect -ErrorAction SilentlyContinue).CCConnect -ne $command){
    New-ItemProperty -LiteralPath $runKey -Name CCConnect -PropertyType String -Value $command -Force|Out-Null
}
& 'D:\coding\cc-connect-deploy\startup\start-cc-connect.ps1'
exit $LASTEXITCODE
