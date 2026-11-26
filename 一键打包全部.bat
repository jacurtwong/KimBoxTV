@echo off
chcp 65001 >nul
setlocal

echo ========================================
echo   KimBoxTV 一键打包（安装版 + 便携版）
echo ========================================
echo.

echo [1/2] 正在构建并打包安装版...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build-installer.ps1" %*
if errorlevel 1 (
    echo.
    echo [失败] 安装版打包失败，已终止。
    goto :end
)

echo.
echo [2/2] 正在打包便携版（复用本次 Release 构建）...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\打包发布.ps1" -SkipBuild
if errorlevel 1 (
    echo.
    echo [失败] 便携版打包失败。
    goto :end
)

echo.
echo [全部完成] 安装版和便携版均已生成到 "%~dp0dist" 目录。

:end
echo.
pause
endlocal
