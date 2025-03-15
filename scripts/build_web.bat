@echo off
REM This script builds the Flutter web app with secure API keys
REM Usage: .\scripts\build_web.bat

REM Check if .env file exists
if not exist .env (
  echo Error: .env file not found!
  echo Please create a .env file with your API keys first.
  exit /b 1
)

REM Read Google Maps API key from .env file
for /f "tokens=2 delims==" %%a in ('findstr "GOOGLE_MAPS_API_KEY_WEB" .env') do set MAPS_API_KEY=%%a

REM Check if we got a valid API key
if "%MAPS_API_KEY%"=="" (
  echo Error: Could not find GOOGLE_MAPS_API_KEY_WEB in .env file!
  exit /b 1
)

REM Replace the placeholder with the actual API key
echo Replacing API key placeholder...
powershell -Command "(Get-Content web\index.html) -replace 'YOUR_WEB_API_KEY_HERE', '%MAPS_API_KEY%' | Set-Content web\index.html"

REM Build the Flutter web app
echo Building Flutter web app...
flutter build web

echo Build completed successfully!
