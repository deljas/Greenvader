param([string]$Script,[string]$Log,[string]$Mode='',[switch]$Gpu,[switch]$Headless)
$ErrorActionPreference='Stop'
$r='C:\godot\greenvader'; $prof="$r\evidence\poc3\playtest01\independent\profile_$Log"
$ov="$r\override.cfg"; $made=$false
$old=@($env:APPDATA,$env:LOCALAPPDATA)
New-Item -ItemType Directory -Force "$prof\roaming","$prof\local" | Out-Null
try{
 if($Gpu){ if(Test-Path $ov){throw 'override.cfg exists'}; [IO.File]::WriteAllText($ov,"[display]`nwindow/size/no_focus=true`nwindow/size/mode=1`n",[Text.UTF8Encoding]::new($false)); $made=$true }
 $env:APPDATA="$prof\roaming"; $env:LOCALAPPDATA="$prof\local"
 $a=@('--path',$r,'--audio-driver','Dummy')
 if($Headless){$a+='--headless'}
 $a+=@('--script',$Script,'--','--integration-authorized'); if($Mode){$a+=$Mode}
 & 'C:\godot\Godot_v4.7.2-stable_win64_console.exe' @a 2>&1 | Tee-Object -FilePath "$r\evidence\poc3\playtest01\independent\$Log"
}finally{
 if($made -and (Test-Path $ov)){Remove-Item $ov}
 $env:APPDATA=$old[0];$env:LOCALAPPDATA=$old[1]
}
