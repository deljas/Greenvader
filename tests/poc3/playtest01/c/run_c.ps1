param([ValidateSet('import','logic','headless','gpu')][string]$Mode='gpu',[string]$Tag='',[string]$Script='res://tests/poc3/playtest01/c/self_gpu_c.gd',[string]$Out='evidence\poc3\playtest01\self\c_gpu')
$ErrorActionPreference='Stop'
$taskRoot='C:\godot\greenvader'
$taskOut=Join-Path $taskRoot $Out
$taskProfile=Join-Path $taskOut 'profile'
$taskOverride=Join-Path $taskRoot 'override.cfg'
$taskExe='C:\godot\Godot_v4.7.2-stable_win64_console.exe'
$taskOldApp=$env:APPDATA; $taskOldLocal=$env:LOCALAPPDATA
$taskSettings="[display]`nwindow/size/no_focus=true`nwindow/size/mode=1`n"
$taskCreated=$false; $taskFile=$null
New-Item -ItemType Directory -Force -Path (Join-Path $taskProfile 'roaming'),(Join-Path $taskProfile 'local') | Out-Null
try {
 if($Mode -eq 'gpu'){
  $taskFile=[System.IO.File]::Open($taskOverride,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
  $taskCreated=$true
  $taskBytes=[System.Text.UTF8Encoding]::new($false).GetBytes($taskSettings)
  $taskFile.Write($taskBytes,0,$taskBytes.Length); $taskFile.Dispose(); $taskFile=$null
 }
 $env:APPDATA=Join-Path $taskProfile 'roaming'; $env:LOCALAPPDATA=Join-Path $taskProfile 'local'
 $taskArgs=@('--path',$taskRoot,'--audio-driver','Dummy')
 if($Mode -eq 'import'){$taskArgs+=@('--headless','--editor','--import')}
 elseif($Mode -eq 'headless'){$taskArgs+=@('--headless','--script',$Script,'--','--integration-authorized')}
 elseif($Mode -eq 'logic'){$taskArgs+=@('--headless','--script',$Script,'--','--logic')}
 else{$taskArgs+=@('--script',$Script,'--','--integration-authorized')}
 & $taskExe @taskArgs 2>&1 | Tee-Object -FilePath (Join-Path $taskOut (($(if($Tag){$Tag}else{$Mode}))+'.log'))
 $taskExit=$LASTEXITCODE
} finally {
 if($null -ne $taskFile){$taskFile.Dispose()}
 if($taskCreated -and (Test-Path -LiteralPath $taskOverride) -and [System.IO.File]::ReadAllText($taskOverride) -eq $taskSettings){Remove-Item -LiteralPath $taskOverride}
 $env:APPDATA=$taskOldApp; $env:LOCALAPPDATA=$taskOldLocal
}
exit $taskExit
