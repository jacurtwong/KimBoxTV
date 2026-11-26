# 打包 KimBoxTV 安装版（Inno Setup）
# 用法：双击「制作安装包.bat」，或执行：
#   powershell -ExecutionPolicy Bypass -File tools\build-installer.ps1 [-SkipBuild]
#
# 产物：dist\KimBoxTV_v<version>_Setup.exe（已排除开发/运行缓存与隐私数据，并补齐全部运行库 DLL）

param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_stage-release.ps1')

$root = Split-Path -Parent $PSScriptRoot
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) { $iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' }
if (-not (Test-Path $iscc)) { $iscc = 'C:\Program Files\Inno Setup 6\ISCC.exe' }
if (-not (Test-Path $iscc)) {
    Write-Host '[错误] 未找到 Inno Setup 编译器（ISCC.exe）' -ForegroundColor Red
    Write-Host '       安装：winget install --id JRSoftware.InnoSetup -e' -ForegroundColor Yellow
    exit 1
}

$stage = Join-Path $env:TEMP 'KimBoxTV_setup_stage'
$appDir = Join-Path $stage 'app'

$info = Invoke-KimBoxStageRelease -Root $root -TargetDir $appDir -SkipBuild:$SkipBuild
$ver = $info.Version
$distDir = $info.DistDir
$iconSrc = $info.IconSrc
$out = Join-Path $distDir "KimBoxTV_v${ver}_Setup.exe"

Write-Host "[打包] KimBoxTV 安装版 v$ver" -ForegroundColor Cyan

$iss = Join-Path $stage 'kimboxtv.iss'
$issText = @"
; 由 tools\build-installer.ps1 自动生成
#define AppName "KimBoxTV"
#define AppVersion "$ver"
#define AppPublisher "KimBoxTV"
#define AppExe "KimBoxTV.exe"

[Setup]
AppId={{A4E9C3D1-7B2F-4E8A-9C14-3F6D2A8B5E12}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\KimBoxTV
DefaultGroupName=KimBoxTV
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=$distDir
OutputBaseFilename=$([IO.Path]::GetFileNameWithoutExtension($out))
SetupIconFile=$iconSrc
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/normal
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableDirPage=no
UsePreviousAppDir=yes
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "$appDir\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\KimBoxTV"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon.ico"
Name: "{autodesktop}\KimBoxTV"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon.ico"

[Run]
Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Description: "启动 KimBoxTV"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data\cache"
Type: filesandordirs; Name: "{app}\data\jvm"
Type: filesandordirs; Name: "{app}\data\updates"
Type: files; Name: "{app}\data\window-state.json"
Type: files; Name: "{app}\data\app.log"
Type: files; Name: "{app}\data\app.log.1"
Type: dirifempty; Name: "{app}\data"
Type: dirifempty; Name: "{app}"
"@
[System.IO.File]::WriteAllText($iss, $issText, (New-Object System.Text.UTF8Encoding($true)))

Write-Host '[编译] 正在压缩生成安装包...' -ForegroundColor Cyan
if (Test-Path $out) { Remove-Item -Force $out }
& $iscc $iss
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) {
    Write-Host '[错误] Inno Setup 编译失败' -ForegroundColor Red
    exit 1
}

Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
$f = Get-Item $out
$sha = (Get-FileHash $out -Algorithm SHA256).Hash
Write-Host ''
Write-Host '[完成] 安装包已生成（已排除运行缓存/用户数据，已包含全部 VC++ / UCRT / 解码运行库）' -ForegroundColor Green
Write-Host "  文件：$($f.FullName)"
Write-Host "  大小：$([math]::Round($f.Length/1MB,1)) MB"
Write-Host "  SHA256：$sha"
