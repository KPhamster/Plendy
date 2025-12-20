#!/bin/bash

# This script builds the Flutter web app with secure API keys
# Usage: ./scripts/build_web.sh

# Check if .env file exists
if [ ! -f .env ]; then
  echo "Error: .env file not found!"
  echo "Please create a .env file with your API keys first."
  exit 1
fi

# Read Google Maps API key from .env file
MAPS_API_KEY=$(grep GOOGLE_MAPS_API_KEY_WEB .env | cut -d '=' -f2-)

# Check if we got a valid API key
if [ -z "$MAPS_API_KEY" ]; then
  echo "Error: Could not find GOOGLE_MAPS_API_KEY_WEB in .env file!"
  exit 1
fi

# Replace the placeholder with the actual API key
echo "Replacing API key placeholder..."
sed -i "s/YOUR_WEB_API_KEY_HERE/$MAPS_API_KEY/g" web/index.html

# Build the Flutter web app
echo "Building Flutter web app..."
flutter build web

# Copy static pages and association files into hosting output.
echo "Copying static web files..."
mkdir -p build/web/.well-known
cp web/privacy.html build/web/privacy.html
cp web/delete_account.html build/web/delete_account.html
cp web/oembed-demo.html build/web/oembed-demo.html
cp web/apple-app-site-association build/web/apple-app-site-association
cp web/.well-known/apple-app-site-association build/web/.well-known/apple-app-site-association

echo "Build completed successfully!"
