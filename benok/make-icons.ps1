# Benok Reach - generates every icon the Windows and Android builds use from the Benok "b" mark.
# The mark is drawn as vector polygons (traced from the Benok IT Consult logo), so every size is sharp.
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File make-icons.ps1 -Src <path to rustdesk source>
param([Parameter(Mandatory = $true)][string]$Src)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Navy   = [Drawing.Color]::FromArgb(255, 0x0B, 0x4C, 0x8E)
$Yellow = [Drawing.Color]::FromArgb(255, 0xFE, 0xC2, 0x0E)
$White  = [Drawing.Color]::White

# Mark geometry (logo coordinates; bounding box x 13..533, y 4..812)
$NavyPts   = @(13,4, 175,4, 175,607, 352,508, 533,407, 533,607, 175,812, 13,727)
$YellowPts = @(199,218, 533,407, 352,508, 199,424)
$MX = 13; $MY = 4; $MW = 520; $MH = 808

function Pts($arr, [double]$s, [double]$ox, [double]$oy) {
  $p = New-Object 'Drawing.PointF[]' ($arr.Count / 2)
  for ($i = 0; $i -lt $arr.Count; $i += 2) { $p[$i / 2] = New-Object Drawing.PointF (($arr[$i] - $MX) * $s + $ox), (($arr[$i + 1] - $MY) * $s + $oy) }
  return ,$p
}

# Draws the mark with height h centred at (cx, cy)
function Draw-Mark($g, [double]$cx, [double]$cy, [double]$h, $cNavy, $cYellow) {
  $s = $h / $MH; $w = $MW * $s
  $ox = $cx - $w / 2; $oy = $cy - $h / 2
  $pw = [Math]::Max(0.6, $h / 400)   # hairline outline closes the anti-aliasing seam between the two shapes
  $np = Pts $NavyPts $s $ox $oy; $yp = Pts $YellowPts $s $ox $oy
  $g.FillPolygon((New-Object Drawing.SolidBrush $cNavy), $np)
  $g.DrawPolygon((New-Object Drawing.Pen $cNavy, $pw), $np)
  $g.FillPolygon((New-Object Drawing.SolidBrush $cYellow), $yp)
  $g.DrawPolygon((New-Object Drawing.Pen $cYellow, $pw), $yp)
}

function New-Canvas([int]$size) {
  $b = New-Object Drawing.Bitmap $size, $size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($b)
  $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
  $g.Clear([Drawing.Color]::Transparent)
  return @($b, $g)
}

function Rounded($g, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r, $color) {
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  $g.FillPath((New-Object Drawing.SolidBrush $color), $p)
}

# kind: tile (white rounded square + mark), round (white circle + mark), mark (transparent), fg (adaptive foreground), stat (white silhouette)
function Render([string]$kind, [int]$size) {
  $bg = New-Canvas $size; $b = $bg[0]; $g = $bg[1]
  switch ($kind) {
    'tile'  { $m = [Math]::Max(1, $size * 0.04); Rounded $g $m $m ($size - 2 * $m) ($size - 2 * $m) ($size * 0.22) $White
              Draw-Mark $g ($size / 2) ($size / 2) ($size * 0.66) $Navy $Yellow }
    'round' { $g.FillEllipse((New-Object Drawing.SolidBrush $White), 0, 0, $size - 1, $size - 1)
              Draw-Mark $g ($size / 2) ($size / 2) ($size * 0.58) $Navy $Yellow }
    'mark'  { Draw-Mark $g ($size / 2) ($size / 2) ($size * 0.96) $Navy $Yellow }
    'fg'    { Draw-Mark $g ($size / 2) ($size / 2) ($size * 0.52) $Navy $Yellow }
    'stat'  { Draw-Mark $g ($size / 2) ($size / 2) ($size * 0.86) $White $White }
  }
  $g.Dispose(); return $b
}

function Save-Png([string]$kind, [int]$size, [string]$path) {
  $b = Render $kind $size; $b.Save($path, [Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
}

# ICO with PNG-compressed entries (Windows Vista+)
function Save-Ico([string]$kind, [int[]]$sizes, [string]$path) {
  $pngs = foreach ($s in $sizes) { $b = Render $kind $s; $ms = New-Object IO.MemoryStream; $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); ,$ms.ToArray() }
  $out = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $out
  $w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]$sizes.Count)
  $offset = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $d = $pngs[$i]
    $w.Write([byte]($(if ($s -ge 256) { 0 } else { $s }))); $w.Write([byte]($(if ($s -ge 256) { 0 } else { $s })))
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([UInt16]1); $w.Write([UInt16]32)
    $w.Write([UInt32]$d.Length); $w.Write([UInt32]$offset); $offset += $d.Length
  }
  foreach ($d in $pngs) { $w.Write($d) }
  $w.Flush(); [IO.File]::WriteAllBytes($path, $out.ToArray()); $w.Dispose()
}

$res = Join-Path $Src 'res'
# Windows / shared app icons
Save-Ico 'tile' @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256) (Join-Path $res 'icon.ico')
Save-Ico 'tile' @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256) (Join-Path $Src 'flutter\windows\runner\resources\app_icon.ico')
Save-Ico 'mark' @(16, 20, 24, 32, 40, 48, 64) (Join-Path $res 'tray-icon.ico')
Save-Png 'tile' 1024 (Join-Path $res 'icon.png')
Save-Png 'tile' 32 (Join-Path $res '32x32.png')
Save-Png 'tile' 64 (Join-Path $res '64x64.png')
Save-Png 'tile' 128 (Join-Path $res '128x128.png')
Save-Png 'tile' 256 (Join-Path $res '128x128@2x.png')

# Android
$a = Join-Path $Src 'flutter\android\app\src\main\res'
$dens = @{ 'mdpi' = 1.0; 'hdpi' = 1.5; 'xhdpi' = 2.0; 'xxhdpi' = 3.0; 'xxxhdpi' = 4.0 }
foreach ($k in $dens.Keys) {
  $f = $dens[$k]; $dir = Join-Path $a "mipmap-$k"
  Save-Png 'tile'  ([int](48 * $f))  (Join-Path $dir 'ic_launcher.png')
  Save-Png 'round' ([int](48 * $f))  (Join-Path $dir 'ic_launcher_round.png')
  Save-Png 'fg'    ([int](108 * $f)) (Join-Path $dir 'ic_launcher_foreground.png')
  Save-Png 'stat'  ([int](24 * $f))  (Join-Path $dir 'ic_stat_logo.png')
}

# Flutter UI wordmark (assets/logo_light.png / logo_dark.png, shown top-left of the desktop home page, max 300x60 -> drawn at 2x)
function Save-Wordmark([string]$path, [bool]$dark) {
  $W = 600; $H = 120
  $b = New-Object Drawing.Bitmap $W, $H, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($b)
  $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.Clear([Drawing.Color]::Transparent)
  $markNavy = $(if ($dark) { $White } else { $Navy })
  Draw-Mark $g 40 ($H / 2) 100 $markNavy $Yellow
  $fam = New-Object Drawing.FontFamily 'Poppins SemiBold'
  $font = New-Object Drawing.Font $fam, 54, ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
  $c1 = $(if ($dark) { $White } else { $Navy })
  $c2 = $(if ($dark) { $Yellow } else { [Drawing.Color]::FromArgb(255, 0x1E, 0x6E, 0xC0) })
  $fmt = [Drawing.StringFormat]::GenericTypographic
  $x = 96; $y = 18
  $g.DrawString('Benok', $font, (New-Object Drawing.SolidBrush $c1), $x, $y, $fmt)
  $w1 = $g.MeasureString('Benok ', $font, 1000, $fmt).Width
  $g.DrawString('Reach', $font, (New-Object Drawing.SolidBrush $c2), ($x + $w1 + 16), $y, $fmt)
  $g.Dispose(); $b.Save($path, [Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
}
Save-Wordmark (Join-Path $Src 'flutter\assets\logo_light.png') $false
Save-Wordmark (Join-Path $Src 'flutter\assets\logo_dark.png') $true

# Flutter UI logo (vector)
$svg = @"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="13 4 520 808" width="520" height="808">
  <polygon fill="#0B4C8E" points="$((0..($NavyPts.Count/2-1) | ForEach-Object { "$($NavyPts[2*$_]),$($NavyPts[2*$_+1])" }) -join ' ')"/>
  <polygon fill="#FEC20E" points="$((0..($YellowPts.Count/2-1) | ForEach-Object { "$($YellowPts[2*$_]),$($YellowPts[2*$_+1])" }) -join ' ')"/>
</svg>
"@
[IO.File]::WriteAllText((Join-Path $Src 'flutter\assets\icon.svg'), $svg)
Write-Output 'icons written'
