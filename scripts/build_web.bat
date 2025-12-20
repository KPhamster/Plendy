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

REM Copy static pages and association files into hosting output.
echo Copying static web files...
if not exist build\web\.well-known mkdir build\web\.well-known
copy /Y web\privacy.html build\web\privacy.html
copy /Y web\delete_account.html build\web\delete_account.html
copy /Y web\oembed-demo.html build\web\oembed-demo.html
copy /Y web\apple-app-site-association build\web\apple-app-site-association
copy /Y web\.well-known\apple-app-site-association build\web\.well-known\apple-app-site-association

echo Build completed successfully!
