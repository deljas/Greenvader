$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Runtime -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class Art03Export {
  public static Bitmap Sample(Bitmap source, int width, int height) {
    var result = new Bitmap(width, height, PixelFormat.Format32bppArgb);
    for (int y=0; y<height; y++) for (int x=0; x<width; x++)
      result.SetPixel(x,y,source.GetPixel(Math.Min(source.Width-1,(int)((x+0.5)*source.Width/width)),Math.Min(source.Height-1,(int)((y+0.5)*source.Height/height))));
    return result;
  }
  public static Bitmap Expand(Bitmap source, int scale) {
    var result = new Bitmap(source.Width*scale,source.Height*scale,PixelFormat.Format32bppArgb);
    for (int y=0;y<result.Height;y++) for (int x=0;x<result.Width;x++) result.SetPixel(x,y,source.GetPixel(x/scale,y/scale));
    return result;
  }
  public static long Check(Bitmap source,Bitmap result,int scale) {
    long errors=0;
    for(int y=0;y<result.Height;y++) for(int x=0;x<result.Width;x++)
      if(result.GetPixel(x,y).ToArgb()!=source.GetPixel(x/scale,y/scale).ToArgb()) errors++;
    return errors;
  }
}
'@
$artDir = $PSScriptRoot
$source = [System.Drawing.Bitmap]::new((Join-Path $artDir 'pixel-study-master.png'))
$results = @()
foreach ($width in @(960,640)) {
  $height = [int]($width*9/16)
  $scale = [int](1920/$width)
  $logical = [Art03Export]::Sample($source,$width,$height)
  $name = "study-${width}x${height}"
  $logical.Save((Join-Path $artDir "$name.png"),[System.Drawing.Imaging.ImageFormat]::Png)
  $expanded = [Art03Export]::Expand($logical,$scale)
  $displayPath = Join-Path $artDir "$name-at-1080p.png"
  $expanded.Save($displayPath,[System.Drawing.Imaging.ImageFormat]::Png)
  $saved = [System.Drawing.Bitmap]::new($displayPath)
  $errors = [Art03Export]::Check($logical,$saved,$scale)
  $results += [pscustomobject]@{logicalWidth=$width;logicalHeight=$height;scale=$scale;outputWidth=$saved.Width;outputHeight=$saved.Height;mismatchedPixels=$errors}
  $saved.Dispose()
  $expanded.Dispose()
  $logical.Dispose()
}
$report = [pscustomobject]@{sourceWidth=$source.Width;sourceHeight=$source.Height;method='Same source, nearest centre sampling to each logical raster, exact pixel replication to 1920x1080. No palette quantization or hand pixel cleanup.';results=$results}
$report | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $artDir 'export-checks.json') -Encoding UTF8
$source.Dispose()
$report | ConvertTo-Json -Depth 4
