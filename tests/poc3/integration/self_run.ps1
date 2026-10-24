param([switch]$Authorized, [ValidateSet('import','core','movement','journey','gpu','water','startup')][string]$Mode='core', [ValidatePattern('^[a-z0-9_]*$')][string]$LogTag='')
$ErrorActionPreference='Stop'
if(-not $Authorized){throw 'Preparation only. Parent must authorize runtime ownership before using -Authorized.'}
$taskRoot='C:\godot\greenvader'
$taskOut=Join-Path $taskRoot 'evidence\poc3\integration\self'
$taskProfile=Join-Path $taskOut 'profile'
$taskExe='C:\godot\Godot_v4.7.2-stable_win64_console.exe'
$taskOldApp=$env:APPDATA
$taskOldLocal=$env:LOCALAPPDATA
$taskOverride=Join-Path $taskRoot 'override.cfg'
$taskOwnedOverride=$false
$taskSettings="[display]`nwindow/size/no_focus=true`nwindow/size/mode=1`n"
if($LogTag -eq ''){$LogTag=$Mode}
New-Item -ItemType Directory -Force -Path (Join-Path $taskProfile 'roaming'),(Join-Path $taskProfile 'local') | Out-Null
try {
 if($Mode -in @('gpu','water')){
  $taskFile=[System.IO.File]::Open($taskOverride,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
  try{$taskBytes=[System.Text.UTF8Encoding]::new($false).GetBytes($taskSettings); $taskFile.Write($taskBytes,0,$taskBytes.Length)}finally{$taskFile.Dispose()}
  $taskOwnedOverride=$true
 }
 $env:APPDATA=Join-Path $taskProfile 'roaming'
 $env:LOCALAPPDATA=Join-Path $taskProfile 'local'
 $taskArgs=@('--path',$taskRoot,'--audio-driver','Dummy')
 if($Mode -notin @('gpu','water')){$taskArgs+='--headless'}
 if($Mode -eq 'import'){$taskArgs+=@('--editor','--import')}
 elseif($Mode -eq 'movement'){$taskArgs+=@('--script','res://tests/poc3/integration/self_core.gd','--','--integration-authorized','--movement-followup')}
 elseif($Mode -eq 'water'){$taskArgs+=@('--script','res://tests/poc3/integration/self_gpu.gd','--','--integration-authorized','--water-sequence-followup')}
 elseif($Mode -in @('core','journey','gpu')){$taskArgs+=@('--script',('res://tests/poc3/integration/self_'+$Mode+'.gd'),'--','--integration-authorized')}
 else{$taskArgs+=@('--quit-after','2','--','--no-title')}
 $taskStdout=Join-Path $taskOut ($LogTag+'.stdout.log')
 $taskStderr=Join-Path $taskOut ($LogTag+'.stderr.log')
 $taskProcess=Start-Process -FilePath $taskExe -ArgumentList $taskArgs -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
 $taskHandle=$taskProcess.Handle
 if(-not $taskProcess.WaitForExit(240000)){$taskProcess.Kill(); $taskProcess.WaitForExit(); throw 'Owned test process exceeded 240 second guard'}
 $taskExit=$taskProcess.ExitCode
 if($null -eq $taskExit){throw 'Owned process exited but native exit code was unavailable; not treating it as success'}
 Get-Content -LiteralPath $taskStdout,$taskStderr | Tee-Object -FilePath (Join-Path $taskOut ($LogTag+'.log'))
 if($taskExit -eq 0 -and (Select-String -LiteralPath $taskStdout,$taskStderr -Pattern 'SCRIPT ERROR|Parse Error|ERROR:' -Quiet)){$taskExit=1}
 @{exit=$taskExit; mode=$Mode; process=$taskProcess.Id} | ConvertTo-Json | Set-Content (Join-Path $taskOut ($LogTag+'.exit.json'))
} finally {
 if($taskOwnedOverride -and (Test-Path -LiteralPath $taskOverride) -and [System.IO.File]::ReadAllText($taskOverride) -eq $taskSettings){Remove-Item -LiteralPath $taskOverride}
 $env:APPDATA=$taskOldApp
 $env:LOCALAPPDATA=$taskOldLocal
}
exit $taskExit
