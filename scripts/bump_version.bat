@echo off
setlocal

:: Change to project root directory
cd /d "%~dp0\.."

:: Check if argument is provided, default to 'build'
set VERSION_TYPE=%1
if "%VERSION_TYPE%"=="" set VERSION_TYPE=build

echo Bumping %VERSION_TYPE% version...
dart run scripts/bump_version.dart %VERSION_TYPE%

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Version bump completed successfully!
    echo.
    echo Usage examples:
    echo   scripts\bump_version.bat          ^(bumps build number^)
    echo   scripts\bump_version.bat build    ^(bumps build number^)
    echo   scripts\bump_version.bat patch    ^(bumps patch version^)
    echo   scripts\bump_version.bat minor    ^(bumps minor version^)
    echo   scripts\bump_version.bat major    ^(bumps major version^)
) else (
    echo Version bump failed!
    exit /b 1
)

endlocal 