@echo off
setlocal EnableDelayedExpansion

where 7z >nul 2>&1
if errorlevel 1 (
    echo 7z nincs telepitve!
    exit /b 1
)

where julia >nul 2>&1
if errorlevel 1 (
    echo julia nincs telepitve!
    exit /b 1
)

if exist build rmdir /s /q build

julia build_app.jl
if errorlevel 1 exit /b 1

for /f "tokens=2 delims==" %%A in ('findstr /b /c:"version =" Project.toml') do set "version=%%~A"
set "version=!version:"=!"
set "version=!version: =!"
set "zip_name=Chaos-windows-x64-v!version!.zip"

pushd build
7z a -tzip -mx=9 -mmt=on "!zip_name!" Chaos
popd
if errorlevel 1 exit /b 1
