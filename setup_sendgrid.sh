#!/bin/bash

# SendGrid Setup Script for Plendy
# This script helps you set up SendGrid for password reset emails

set -e  # Exit on error

echo "🚀 Plendy - SendGrid Setup Script"
echo "=================================="
echo ""

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    echo "   cd /Users/kevinpham/Documents/GitHub/Plendy"
    exit 1
fi

echo "✅ Found pubspec.yaml - we're in the right directory"
echo ""

# Step 1: Install Flutter dependencies
echo "📦 Step 1: Installing Flutter dependencies..."
flutter pub get
echo "✅ Flutter dependencies installed"
echo ""

# Step 2: Install Cloud Functions dependencies
echo "📦 Step 2: Installing Cloud Functions dependencies..."
cd functions
npm install
cd ..
echo "✅ Cloud Functions dependencies installed"
echo ""

# Step 3: Check if SendGrid API key is set
echo "🔑 Step 3: Checking SendGrid API key..."
if firebase functions:config:get | grep -q "sendgrid"; then
    echo "✅ SendGrid API key is already configured"
else
    echo "⚠️  SendGrid API key not found"
    echo ""
    echo "Please set your SendGrid API key:"
    echo ""
    read -p "Enter your SendGrid API key (starts with SG.): " api_key
    
    if [ -z "$api_key" ]; then
        echo "❌ API key cannot be empty"
        echo ""
        echo "To set it later, run:"
        echo "  firebase functions:config:set sendgrid.key=\"YOUR_API_KEY\""
        exit 1
    fi
    
    firebase functions:config:set sendgrid.key="$api_key"
    echo "✅ SendGrid API key configured"
fi
echo ""

# Step 4: Deploy Cloud Function
echo "🚀 Step 4: Deploying Cloud Function..."
echo "This may take 1-2 minutes..."
firebase deploy --only functions:sendPasswordResetEmail
echo "✅ Cloud Function deployed successfully"
echo ""

# Step 5: Done!
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "Next steps:"
echo "1. Make sure you've verified your domain (plendy.app) in SendGrid"
echo "2. Test the password reset flow in your app"
echo "3. Check your inbox (not spam folder!)"
echo ""
echo "To test:"
echo "  flutter run"
echo ""
echo "To check logs:"
echo "  firebase functions:log --only sendPasswordResetEmail"
echo ""
echo "Need help? See SETUP_SENDGRID_NOW.md"


