param([ValidateSet('compare','normal')][string]$Mode='compare',[switch]$ExpectFullResolution)
$ErrorActionPreference='Stop'
$taskRoot='C:\godot\greenvader'
$taskOut=Join-Path $taskRoot 'evidence\poc3\reflection\self'
$taskProfile=Join-Path $taskOut 'profile'
$taskOverride=Join-Path $taskRoot 'override.cfg'
$taskExe='C:\godot\Godot_v4.7.2-stable_win64_console.exe'
$taskSettings="[display]`nwindow/size/no_focus=true`nwindow/size/mode=1`n"
$taskOldApp=$env:APPDATA
$taskOldLocal=$env:LOCALAPPDATA
$taskCreated=$false
$taskFile=$null
$taskExit=1
New-Item -ItemType Directory -Force -Path (Join-Path $taskProfile 'roaming'),(Join-Path $taskProfile 'local') | Out-Null
try {
 # Never overwrite an override owned by another task. Permission to run remains a parent decision.
 $taskFile=[System.IO.File]::Open($taskOverride,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
 $taskCreated=$true
 $taskBytes=[System.Text.UTF8Encoding]::new($false).GetBytes($taskSettings)
 $taskFile.Write($taskBytes,0,$taskBytes.Length)
 $taskFile.Dispose(); $taskFile=$null
 [System.IO.File]::WriteAllText((Join-Path $taskOut 'startup_override.cfg'),$taskSettings,[System.Text.UTF8Encoding]::new($false))
 $env:APPDATA=Join-Path $taskProfile 'roaming'
 $env:LOCALAPPDATA=Join-Path $taskProfile 'local'
 $taskArgs=@('--path',$taskRoot,'--audio-driver','Dummy','--script','res://tests/poc3/reflection/self_compare.gd')
 $taskUserArgs=@()
 if($ExpectFullResolution){$taskUserArgs+='--expect-divisor=1'}
 if($Mode -eq 'normal'){$taskUserArgs+='--normal-only'}
 if($taskUserArgs.Count -gt 0){$taskArgs+='--'; $taskArgs+=$taskUserArgs}
 & $taskExe @taskArgs 2>&1 | Tee-Object -FilePath (Join-Path $taskOut ($Mode+'.log'))
 $taskExit=$LASTEXITCODE
} finally {
 if($null -ne $taskFile){$taskFile.Dispose()}
 if($taskCreated -and (Test-Path -LiteralPath $taskOverride) -and [System.IO.File]::ReadAllText($taskOverride) -eq $taskSettings){Remove-Item -LiteralPath $taskOverride}
 $env:APPDATA=$taskOldApp
 $env:LOCALAPPDATA=$taskOldLocal
}
exit $taskExit
