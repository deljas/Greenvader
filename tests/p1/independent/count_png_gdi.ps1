# Independent PNG colour count via .NET System.Drawing (no Godot, no implementer's Python).
param([string]$Path, [string]$Out)
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($Path)
$w=$bmp.Width; $h=$bmp.Height
$rect = New-Object System.Drawing.Rectangle(0,0,$w,$h)
$data = $bmp.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride*$h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0,$bytes,0,$bytes.Length)
$bmp.UnlockBits($data)
$counts=@{}; $alphaBad=0
for($y=0;$y -lt $h;$y++){ for($x=0;$x -lt $w;$x++){ $o=$y*$data.Stride+$x*4
 $k='{0:x2}{1:x2}{2:x2}' -f $bytes[$o+2],$bytes[$o+1],$bytes[$o]
 if($bytes[$o+3] -ne 255){$alphaBad++}
 $counts[$k]=1+[int]$counts[$k] } }
$res=[ordered]@{width=$w;height=$h;alpha_not_255=$alphaBad;counts=$counts}
$res | ConvertTo-Json | Set-Content -Encoding utf8 $Out
$res | ConvertTo-Json
