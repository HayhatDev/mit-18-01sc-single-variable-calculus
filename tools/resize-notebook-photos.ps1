<#
.SYNOPSIS
  Resize notebook photos down to something reasonable for committing to git.

.DESCRIPTION
  Phone photos are usually 4MB or more. A repo full of those gets slow to
  clone and slow for anyone reading it. Resized to 1600px wide and saved as
  JPEG at quality 82, a legible notebook page lands around 300KB.

  Images already under the width limit are copied through untouched.

.EXAMPLE
  .\resize-notebook-photos.ps1 -Source "C:\Users\HP\Pictures\ps1" -Dest .\ps\unit-1

.EXAMPLE
  Get-ChildItem "C:\Users\HP\Pictures\ps1\*.HEIC" | ForEach-Object {
    & .\resize-notebook-photos.ps1 -Source $_.FullName
  }
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$Source,

  [string]$Dest = ".",

  [int]$MaxWidth = 1600,

  [int]$Quality = 82
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $Source)) {
  throw "Source not found: $Source"
}

$destPath = if ([System.IO.Path]::IsPathRooted($Dest)) { $Dest } else { Join-Path (Get-Location) $Dest }
if (-not (Test-Path -LiteralPath $destPath)) {
  New-Item -ItemType Directory -Path $destPath -Force | Out-Null
}

if (Test-Path -LiteralPath $Source -PathType Container) {
  $files = Get-ChildItem -LiteralPath $Source -File |
    Where-Object { $_.Extension.ToLower() -in @(".jpg", ".jpeg", ".png") }
}
else {
  $files = @(Get-Item -LiteralPath $Source)
}

if (Test-Path -LiteralPath $Source -PathType Container) {
  $skipped = Get-ChildItem -LiteralPath $Source -File |
    Where-Object { $_.Extension.ToLower() -notin @(".jpg", ".jpeg", ".png") }
  if ($skipped) {
    Write-Warning ("Skipped {0} file(s) this script cannot read: {1}" -f `
      $skipped.Count, (($skipped | ForEach-Object { $_.Name }) -join ", "))
    Write-Warning "If those are HEIC, set your phone camera to Most Compatible (JPEG) and retake, or convert them first."
  }
}

if (-not $files) {
  Write-Output "No readable images found in $Source"
  return
}

$before = 0
$after = 0
$failed = 0

foreach ($f in $files) {
  $before += $f.Length
  $img = $null
  $bmp = $null

  try {
    $img = [System.Drawing.Image]::FromFile($f.FullName)

    if ($img.Width -le $MaxWidth) {
      Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $destPath $f.Name) -Force
      $after += $f.Length
      Write-Output ("{0,-30} {1,7:N0} KB  already small enough" -f $f.Name, ($f.Length / 1KB))
      continue
    }

    $newHeight = [int][Math]::Round($img.Height * ($MaxWidth / $img.Width))
    $bmp = New-Object System.Drawing.Bitmap($MaxWidth, $newHeight)

    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.SmoothingMode    = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $g.PixelOffsetMode  = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $g.Clear([System.Drawing.Color]::White)
      $g.DrawImage($img, 0, 0, $MaxWidth, $newHeight)
    }
    finally { $g.Dispose() }

    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
      Where-Object { $_.MimeType -eq "image/jpeg" }

    $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
      [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality
    )

    $outName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) + ".jpg"
    $outPath = Join-Path $destPath $outName
    $bmp.Save($outPath, $codec, $encParams)

    $len = (Get-Item -LiteralPath $outPath).Length
    $after += $len
    Write-Output ("{0,-30} {1,7:N0} KB -> {2,6:N0} KB" -f $f.Name, ($f.Length / 1KB), ($len / 1KB))
  }
  catch {
    $failed++
    $after += $f.Length
    Write-Warning ("{0} could not be read: {1}" -f $f.Name, $_.Exception.Message)
  }
  finally {
    if ($bmp) { $bmp.Dispose() }
    if ($img) { $img.Dispose() }
  }
}

Write-Output ""
Write-Output ("{0} image(s), {1:N1} MB -> {2:N1} MB{3}" -f `
  $files.Count, ($before / 1MB), ($after / 1MB),
  $(if ($failed) { "  ({0} unreadable, copied as-is)" -f $failed } else { "" }))
