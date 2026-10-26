$ErrorActionPreference='Stop'
$root='D:\coding\cc-connect-deploy'
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath $compiler)){throw 'The existing Windows .NET Framework compiler is missing.'}
$bin=Join-Path $root 'bin'
if(-not(Test-Path -LiteralPath $bin)){New-Item -ItemType Directory -Path $bin|Out-Null}
$installed=Get-AppxPackage -Name Microsoft.PowerShell|Sort-Object Version -Descending|Select-Object -First 1
$hostPath=if($installed){Join-Path $installed.InstallLocation 'pwsh.exe'}else{Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'}
if(-not(Test-Path -LiteralPath $hostPath)){throw 'The existing PowerShell 7 installation is required; no software is installed automatically.'}
$hostSource=Join-Path $bin 'BackgroundHostPath.cs'
$hostText='internal static class BackgroundHostPath { internal const string PowerShell = @"'+$hostPath.Replace('"','""')+'"; }'
if(-not(Test-Path -LiteralPath $hostSource) -or [IO.File]::ReadAllText($hostSource) -ne $hostText){[IO.File]::WriteAllText($hostSource,$hostText)}
foreach($name in @('ClaudeGuardLauncher','BackgroundLauncher')){
    $output=Join-Path $bin ($name+'.exe')
    $source=Join-Path $root ('scripts\'+$name+'.cs')
    $inputs=@($source);if($name -eq 'BackgroundLauncher'){$inputs+=@($hostSource)}
    $newest=($inputs|ForEach-Object{(Get-Item -LiteralPath $_).LastWriteTimeUtc}|Sort-Object -Descending|Select-Object -First 1)
    if((Test-Path -LiteralPath $output) -and (Get-Item -LiteralPath $output).LastWriteTimeUtc -ge $newest){continue}
    & $compiler /nologo /target:winexe /platform:anycpu /optimize ('/out:'+$output) @inputs
    if($LASTEXITCODE -ne 0){throw "Hidden launcher build failed: $name"}
}
