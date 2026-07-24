@echo off
REM Build a minified release APK and rename it to fixit-release.apk
cd /d "%~dp0"

echo Cleaning...
call flutter clean

echo Getting dependencies...
call flutter pub get

echo Building release APK...
call flutter build apk --release
if errorlevel 1 (
    echo Build failed!
    exit /b 1
)

REM Flutter always outputs app-release.apk -- rename it
set "APK_DIR=build\app\outputs\flutter-apk"
set "SRC=%APK_DIR%\app-release.apk"
set "DST=%APK_DIR%\fixit-release.apk"

if exist "%SRC%" (
    move /y "%SRC%" "%DST%" >nul
    if exist "%APK_DIR%\app-release.apk.sha1" move /y "%APK_DIR%\app-release.apk.sha1" "%APK_DIR%\fixit-release.apk.sha1" >nul
    echo.
    echo Built: %DST%
    for %%A in ("%DST%") do echo Size: %%~zA bytes
) else (
    echo Build failed - app-release.apk not found
    exit /b 1
)