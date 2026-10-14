# Cross-check capture: Win32 PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT) of one window's client area. Read-only; no input, no focus change.
param([Parameter(Mandatory = $true)][Int64]$Hwnd, [Parameter(Mandatory = $true)][string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class PWNative {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, ref RECT r);
  public struct RECT { public int l, t, r, b; }
}
"@
$h = [IntPtr]$Hwnd
$rc = New-Object PWNative+RECT
[void][PWNative]::GetClientRect($h, [ref]$rc)
$w = $rc.r - $rc.l; $ht = $rc.b - $rc.t
$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [PWNative]::PrintWindow($h, $hdc, 3)
$g.ReleaseHdc($hdc)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "PW ok=$ok size=${w}x${ht}"
