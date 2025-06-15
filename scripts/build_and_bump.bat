@echo off
setlocal enabledelayedexpansion

:: Change to project root directory
cd /d "%~dp0\.."

:: Parse command line arguments
set BUILD_TYPE=apk
set VERSION_TYPE=build
set SIGN_RELEASE=false

:parse_args
if "%~1"=="" goto :done_parsing
if /i "%~1"=="--aab" (
    set BUILD_TYPE=appbundle
    shift
    goto :parse_args
)
if /i "%~1"=="--apk" (
    set BUILD_TYPE=apk
    shift
    goto :parse_args
)
if /i "%~1"=="--release" (
    set SIGN_RELEASE=true
    shift
    goto :parse_args
)
if /i "%~1"=="--version" (
    set VERSION_TYPE=%~2
    shift
    shift
    goto :parse_args
)
shift
goto :parse_args

:done_parsing

echo ========================================
echo Flutter Build and Version Bump Script
echo ========================================
echo Build Type: %BUILD_TYPE%
echo Version Type: %VERSION_TYPE%
echo Sign Release: %SIGN_RELEASE%
echo ========================================

:: Bump version first
echo.
echo [1/5] Bumping %VERSION_TYPE% version...
dart run scripts/bump_version.dart %VERSION_TYPE%
if %ERRORLEVEL% NEQ 0 (
    echo Error: Version bump failed!
    exit /b 1
)

:: Get dependencies
echo.
echo [2/5] Getting Flutter dependencies...
flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to get dependencies!
    exit /b 1
)

:: Clean previous builds
echo.
echo [3/5] Cleaning previous builds...
flutter clean
flutter pub get

:: Build the app
echo.
echo [4/5] Building Flutter app...
if "%SIGN_RELEASE%"=="true" (
    if "%BUILD_TYPE%"=="appbundle" (
        flutter build appbundle --release
    ) else (
        flutter build apk --release
    )
) else (
    if "%BUILD_TYPE%"=="appbundle" (
        flutter build appbundle --debug
    ) else (
        flutter build apk --debug
    )
)

if %ERRORLEVEL% NEQ 0 (
    echo Error: Build failed!
    exit /b 1
)

:: Show build location
echo.
echo [5/5] Build completed successfully!
echo.
if "%BUILD_TYPE%"=="appbundle" (
    echo App bundle location: build\app\outputs\bundle\release\app-release.aab
) else (
    if "%SIGN_RELEASE%"=="true" (
        echo APK location: build\app\outputs\flutter-apk\app-release.apk
    ) else (
        echo APK location: build\app\outputs\flutter-apk\app-debug.apk
    )
)

echo.
echo Usage examples:
echo   scripts\build_and_bump.bat                           ^(debug APK, bump build^)
echo   scripts\build_and_bump.bat --release                 ^(release APK, bump build^)
echo   scripts\build_and_bump.bat --aab --release           ^(release AAB, bump build^)
echo   scripts\build_and_bump.bat --version patch --release ^(release APK, bump patch^)

endlocal 