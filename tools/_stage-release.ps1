# 共享的 Release 暂存、运行时数据排除与运行库 DLL 补齐逻辑
# 返回哈希表：@{ Version = ...; DistDir = ...; IconSrc = ... }

function Invoke-KimBoxStageRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [switch]$SkipBuild
    )

    $pubspecPath = Join-Path $Root 'pubspec.yaml'
    $pubText = [System.IO.File]::ReadAllText($pubspecPath, [System.Text.Encoding]::UTF8)
    $verMatch = [regex]::Match($pubText, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
    if (-not $verMatch.Success) {
        throw '无法从 pubspec.yaml 读取版本号'
    }
    $ver = $verMatch.Groups[1].Value

    $distDir = Join-Path $Root 'dist'
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    $releaseDir = Join-Path $Root 'build\windows\x64\runner\Release'
    $iconSrc = Join-Path $Root 'windows\runner\resources\app_icon.ico'

    # 1) Release 构建
    if (-not $SkipBuild) {
        Write-Host '[构建] 正在执行 flutter build windows --release ...' -ForegroundColor Cyan
        Push-Location $Root
        try {
            & flutter build windows --release
            if ($LASTEXITCODE -ne 0) {
                throw 'flutter build windows --release 失败'
            }
        } finally {
            Pop-Location
        }
    }

    if (-not (Test-Path (Join-Path $releaseDir 'KimBoxTV.exe'))) {
        throw "未找到 Release 产物：$releaseDir\KimBoxTV.exe"
    }

    # 2) 确保 JVM companion 与便携 JRE 存在（若 Release 下缺少则从相邻目录同步）
    $parentDir = Split-Path -Parent $Root
    $siblingCandidates = @((Join-Path $parentDir 'KimBoxTV'), (Join-Path $parentDir 'KimBoxPC'))
    foreach ($sub in @('jvm', 'runtime')) {
        $dstSub = Join-Path $releaseDir $sub
        if (-not (Test-Path $dstSub)) {
            $srcSub = $siblingCandidates | ForEach-Object { Join-Path $_ $sub } | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($srcSub) {
                Write-Host "[同步] 复制 $sub 到 Release 目录..." -ForegroundColor Cyan
                & robocopy $srcSub $dstSub /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
                if ($LASTEXITCODE -ge 8) { throw "复制 $sub 失败" }
            }
        }
    }

    # 3) 复制到干净暂存目录：保留 data\app.so / icudtl.dat / flutter_assets，
    #    严格排除本机运行产生的用户数据、缓存、日志、历史数据库及调试/冗余文件
    if (Test-Path $TargetDir) { Remove-Item -Recurse -Force $TargetDir }
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

    $xd = @(
        'data\backups',
        'data\cache',
        'data\jvm',
        'data\updates'
    ) | ForEach-Object { Join-Path $releaseDir $_ }

    $xf = @(
        'tvbox.db',
        'tvbox.db-shm',
        'tvbox.db-wal',
        'app.log',
        'app.log.*',
        'window-state.json',
        'boss-key.json',
        'settings.json',
        'KimBoxPC.exe',
        'zlib.dll',
        '*.lnk',
        '*.pdb',
        '*.lib',
        '*.exp',
        '*.iobj',
        '*.ipdb',
        '*.vcxproj',
        '*.vcxproj.filters',
        '*.sln',
        '*.log',
        '_*.js',
        '_*.log',
        '_*.json'
    )

    $rcArgs = @($releaseDir, $TargetDir, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/nc', '/ns', '/np', '/XD') + $xd + @('/XF') + $xf
    & robocopy @rcArgs | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw '复制 Release 文件到暂存目录失败'
    }
    # 仅剔除根目录可能存在的测试覆盖版 category-filter.json（保留 data\flutter_assets\assets\ 内的默认资源）
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $TargetDir 'category-filter.json')
    # 确保根目录也提供干净的预设分类基线，与内置 assets\category-baseline.json 保持一致
    Copy-Item -Path (Join-Path $Root 'assets\category-baseline.json') -Destination (Join-Path $TargetDir 'category-baseline.json') -Force
    Copy-Item -Path $iconSrc -Destination (Join-Path $TargetDir 'app_icon.ico') -Force

    # 4) 兜底补齐 VC++ / UCRT 运行库 DLL
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vcRedistDir = ''
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -all -products * -property installationPath | Select-Object -First 1
        if ($vsPath) {
            $crtDir = Get-ChildItem (Join-Path $vsPath 'VC\Redist\MSVC') -Recurse -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '\\x64\\Microsoft\.VC\d+\.CRT$' -and $_.FullName -notmatch 'onecore|debug_nonredist' } |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($crtDir) { $vcRedistDir = $crtDir.FullName }
        }
    }
    if ($vcRedistDir) {
        Get-ChildItem $vcRedistDir -Filter '*.dll' -File | ForEach-Object {
            $dst = Join-Path $TargetDir $_.Name
            if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst -Force }
        }
    }

    $ucrtDir = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Redist' -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\ucrt\\DLLs\\x64$' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($ucrtDir) {
        Get-ChildItem $ucrtDir.FullName -Filter '*.dll' -File | ForEach-Object {
            $dst = Join-Path $TargetDir $_.Name
            if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst -Force }
        }
    }

    # 5) 完整性与干净度双校验
    $must = @(
        'KimBoxTV.exe',
        'app_icon.ico',
        'flutter_windows.dll',
        'data\app.so',
        'data\icudtl.dat',
        'data\flutter_assets',
        'data\flutter_assets\assets\category-baseline.json',
        'data\flutter_assets\assets\category-filter.json',
        'data\flutter_assets\assets\icon.png',
        'data\flutter_assets\assets\logo.png',
        'category-baseline.json',
        'libmpv-2.dll',
        'libEGL.dll',
        'libGLESv2.dll',
        'd3dcompiler_47.dll',
        'vulkan-1.dll',
        'vk_swiftshader.dll',
        'sqlite3.dll',
        'dartjni.dll',
        'file_selector_windows_plugin.dll',
        'media_kit_libs_windows_video_plugin.dll',
        'media_kit_video_plugin.dll',
        'screen_retriever_plugin.dll',
        'sqlite3_flutter_libs_plugin.dll',
        'url_launcher_windows_plugin.dll',
        'volume_controller_plugin.dll',
        'window_manager_plugin.dll',
        'concrt140.dll',
        'msvcp140.dll',
        'msvcp140_1.dll',
        'msvcp140_2.dll',
        'msvcp140_atomic_wait.dll',
        'msvcp140_codecvt_ids.dll',
        'vccorlib140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'vcruntime140_threads.dll',
        'ucrtbase.dll',
        'api-ms-win-crt-runtime-l1-1-0.dll',
        'api-ms-win-crt-stdio-l1-1-0.dll',
        'api-ms-win-crt-string-l1-1-0.dll',
        'api-ms-win-crt-heap-l1-1-0.dll',
        'api-ms-win-crt-math-l1-1-0.dll',
        'api-ms-win-crt-locale-l1-1-0.dll',
        'api-ms-win-crt-convert-l1-1-0.dll',
        'api-ms-win-crt-environment-l1-1-0.dll',
        'api-ms-win-crt-filesystem-l1-1-0.dll',
        'api-ms-win-crt-time-l1-1-0.dll',
        'api-ms-win-crt-utility-l1-1-0.dll',
        'api-ms-win-crt-private-l1-1-0.dll',
        'jvm\companion-service.jar',
        'jvm\bcprov-jdk18on-1.78.1.jar',
        'jvm\lib-unidbg',
        'runtime\jre\bin\java.exe'
    )
    foreach ($m in $must) {
        if (-not (Test-Path (Join-Path $TargetDir $m))) {
            throw "缺少必要运行时文件：$m"
        }
    }

    $forbidden = @(
        'data\backups',
        'data\cache',
        'data\jvm',
        'data\updates',
        'data\tvbox.db',
        'data\app.log',
        'data\window-state.json',
        'data\boss-key.json',
        'data\settings.json',
        'category-filter.json',
        'KimBoxPC.exe',
        'zlib.dll'
    )
    foreach ($f in $forbidden) {
        if (Test-Path (Join-Path $TargetDir $f)) {
            throw "存在应排除的运行产物/冗余文件：$f"
        }
    }

    return @{
        Version = $ver
        DistDir = $distDir
        IconSrc = $iconSrc
    }
}
