param([ValidateSet('import','pure','logic','markers','idle_followup','gpu')][string]$Mode='logic')
$ErrorActionPreference='Stop'
$taskRoot='C:\godot\greenvader'
$taskOut=Join-Path $taskRoot 'evidence\poc3\helpers\self'
$taskProfile=Join-Path $taskOut 'profile'
$taskOverride=Join-Path $taskRoot 'override.cfg'
$taskExe='C:\godot\Godot_v4.7.2-stable_win64_console.exe'
$taskOldApp=$env:APPDATA
$taskOldLocal=$env:LOCALAPPDATA
$taskSettings="[display]`nwindow/size/no_focus=true`nwindow/size/mode=1`n"
$taskCreated=$false
$taskFile=$null
New-Item -ItemType Directory -Force -Path (Join-Path $taskProfile 'roaming'),(Join-Path $taskProfile 'local') | Out-Null
try {
 if($Mode -eq 'gpu'){
  # CreateNew refuses any concurrent shared override instead of overwriting it.
  $taskFile=[System.IO.File]::Open($taskOverride,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
  $taskCreated=$true
  $taskBytes=[System.Text.UTF8Encoding]::new($false).GetBytes($taskSettings)
  $taskFile.Write($taskBytes,0,$taskBytes.Length)
  $taskFile.Dispose(); $taskFile=$null
  [System.IO.File]::WriteAllText((Join-Path $taskOut 'startup_override.cfg'),$taskSettings,[System.Text.UTF8Encoding]::new($false))
 }
 $env:APPDATA=Join-Path $taskProfile 'roaming'
 $env:LOCALAPPDATA=Join-Path $taskProfile 'local'
 $taskArgs=@('--path',$taskRoot,'--audio-driver','Dummy')
 if($Mode -eq 'import'){$taskArgs+=@('--headless','--editor','--import')}
 elseif($Mode -in @('logic','pure','markers')){$taskArgs+=@('--headless','--script',('res://tests/poc3/helpers/self_'+$Mode+'.gd'))}
 elseif($Mode -eq 'idle_followup'){$taskArgs+=@('--headless','--script','res://tests/poc3/helpers/self_logic.gd','--','--idle-followup')}
 else{$taskArgs+=@('--script','res://tests/poc3/helpers/self_gpu.gd')}
 & $taskExe @taskArgs 2>&1 | Tee-Object -FilePath (Join-Path $taskOut ($Mode+'.log'))
 $taskExit=$LASTEXITCODE
} finally {
 if($null -ne $taskFile){$taskFile.Dispose()}
 if($taskCreated -and (Test-Path -LiteralPath $taskOverride) -and [System.IO.File]::ReadAllText($taskOverride) -eq $taskSettings){Remove-Item -LiteralPath $taskOverride}
 $env:APPDATA=$taskOldApp
 $env:LOCALAPPDATA=$taskOldLocal
}
exit $taskExit

