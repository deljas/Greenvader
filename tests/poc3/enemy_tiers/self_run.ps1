param([ValidateSet('import','pure','integration','save_followup','validation_followup')][string]$Mode='pure')
$ErrorActionPreference='Stop'
$taskRoot='C:\godot\greenvader'
$taskOut=Join-Path $taskRoot 'evidence\poc3\enemy_tiers\self'
$taskProfile=Join-Path $taskOut 'profile'
$taskExe='C:\godot\Godot_v4.7.2-stable_win64_console.exe'
$taskOldApp=$env:APPDATA
$taskOldLocal=$env:LOCALAPPDATA
New-Item -ItemType Directory -Force -Path (Join-Path $taskProfile 'roaming'),(Join-Path $taskProfile 'local') | Out-Null
try {
 $env:APPDATA=Join-Path $taskProfile 'roaming'
 $env:LOCALAPPDATA=Join-Path $taskProfile 'local'
 $taskArgs=@('--path',$taskRoot,'--audio-driver','Dummy','--headless')
 if($Mode -eq 'import'){$taskArgs+=@('--editor','--import')}
 elseif($Mode -eq 'save_followup'){$taskArgs+=@('--script','res://tests/poc3/enemy_tiers/self_integration.gd','--','--save-followup')}
 elseif($Mode -eq 'validation_followup'){$taskArgs+=@('--script','res://tests/poc3/enemy_tiers/self_integration.gd','--','--validation-followup')}
 else{$taskArgs+=@('--script',('res://tests/poc3/enemy_tiers/self_'+$Mode+'.gd'))}
 & $taskExe @taskArgs 2>&1 | Tee-Object -FilePath (Join-Path $taskOut ($Mode+'.log'))
 $taskExit=$LASTEXITCODE
} finally {
 $env:APPDATA=$taskOldApp
 $env:LOCALAPPDATA=$taskOldLocal
}
exit $taskExit
