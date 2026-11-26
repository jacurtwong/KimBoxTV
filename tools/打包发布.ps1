# 打包 KimBoxTV 便携版 zip（已排除运行缓存与隐私数据，含全部运行库 DLL）
# 用法：双击「打包发布.bat」，或执行：
#   powershell -ExecutionPolicy Bypass -File tools\打包发布.ps1 [-SkipBuild]

param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_stage-release.ps1')

$root = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $env:TEMP 'KimBoxTV_pkg_stage'
$pkgDir = Join-Path $stage 'KimBoxTV'

$info = Invoke-KimBoxStageRelease -Root $root -TargetDir $pkgDir -SkipBuild:$SkipBuild
$ver = $info.Version
$distDir = $info.DistDir
$out = Join-Path $distDir "KimBoxTV_v$ver.zip"

Write-Host "[打包] KimBoxTV 便携版 v$ver" -ForegroundColor Cyan

if (Test-Path $out) { Remove-Item -Force $out }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$level = [System.IO.Compression.CompressionLevel]::Optimal
$zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $baseLen = $pkgDir.Length + 1
    Get-ChildItem $pkgDir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($baseLen).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, "KimBoxTV/$rel", $level)
    }
} finally {
    $zip.Dispose()
}

Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
$f = Get-Item $out
$sha = (Get-FileHash $out -Algorithm SHA256).Hash
Write-Host ''
Write-Host '[完成] 便携版打包成功' -ForegroundColor Green
Write-Host "  文件：$($f.FullName)"
Write-Host "  大小：$([math]::Round($f.Length/1MB,1)) MB"
Write-Host "  SHA256：$sha"
