@echo off
setlocal enabledelayedexpansion

echo ============================================
echo   GuiltyAtomeis V10 -- Windows Build
echo ============================================

set SRC_DIR=%~dp0
cd /d "%SRC_DIR%"

echo [1/3] Building atomeis_runtime...
nim cpp -f -o:atomeis_runtime.exe -d:release --app:console ^
    --path:src ^
    src/atomeis_runtime.nim
if %errorlevel% neq 0 exit /b %errorlevel%

echo [2/3] Building atmc...
nim cpp -f -o:atmc.exe -d:release --app:console ^
    --path:src ^
    src/atmc.nim
if %errorlevel% neq 0 exit /b %errorlevel%

echo.
echo ============================================
echo   Build Complete!
echo ============================================
echo   atomeis_runtime.exe  - Runtime stub
echo   atmc.exe             - Compiler
echo ============================================
