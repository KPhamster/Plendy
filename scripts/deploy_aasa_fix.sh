#!/bin/bash
# Deploy AASA Fix for Universal Links
# This script ensures both AASA file paths are properly deployed

set -e  # Exit on error

echo "🚀 Universal Links AASA Deployment Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Navigate to project root
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

echo "📍 Project root: $PROJECT_ROOT"
echo ""

# Step 1: Verify source files exist
echo "Step 1: Verifying source files..."
if [ ! -f "web/apple-app-site-association" ]; then
    echo -e "${RED}❌ Error: web/apple-app-site-association not found${NC}"
    exit 1
fi

if [ ! -f "web/.well-known/apple-app-site-association" ]; then
    echo -e "${YELLOW}⚠️  Creating .well-known directory...${NC}"
    mkdir -p web/.well-known
    cp web/apple-app-site-association web/.well-known/apple-app-site-association
fi

# Verify files are identical
if diff web/apple-app-site-association web/.well-known/apple-app-site-association > /dev/null; then
    echo -e "${GREEN}✅ Both AASA files are identical${NC}"
else
    echo -e "${RED}❌ Error: AASA files differ! Syncing...${NC}"
    cp web/apple-app-site-association web/.well-known/apple-app-site-association
fi
echo ""

# Step 2: Clean previous build
echo "Step 2: Cleaning previous build..."
flutter clean
echo -e "${GREEN}✅ Clean complete${NC}"
echo ""

# Step 3: Build web app
echo "Step 3: Building web app (release mode)..."
flutter build web --release

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Build complete${NC}"
echo ""

# Step 4: Verify build output
echo "Step 4: Verifying build output..."
if [ ! -f "build/web/apple-app-site-association" ]; then
    echo -e "${RED}❌ Error: AASA file not in build output${NC}"
    exit 1
fi

if [ ! -f "build/web/.well-known/apple-app-site-association" ]; then
    echo -e "${RED}❌ Error: .well-known AASA file not in build output${NC}"
    echo "   Copying manually..."
    mkdir -p build/web/.well-known
    cp build/web/apple-app-site-association build/web/.well-known/apple-app-site-association
fi

echo -e "${GREEN}✅ Build output verified${NC}"
echo ""

# Display file contents for verification
echo "Step 5: Displaying AASA file content..."
echo "----------------------------------------"
cat build/web/apple-app-site-association | python3 -m json.tool || cat build/web/apple-app-site-association
echo "----------------------------------------"
echo ""

# Check for required paths
if grep -q "/shared/\*" build/web/apple-app-site-association && \
   grep -q "/shared-category/\*" build/web/apple-app-site-association; then
    echo -e "${GREEN}✅ Required paths present: /shared/* and /shared-category/*${NC}"
else
    echo -e "${RED}❌ Warning: Required paths may be missing${NC}"
    echo "   Please verify the AASA file content above"
fi
echo ""

# Step 6: Deploy to Firebase
echo "Step 6: Deploying to Firebase Hosting..."
echo ""
echo -e "${YELLOW}This will deploy your web app with the updated AASA files.${NC}"
read -p "Continue with deployment? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    firebase deploy --only hosting
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✅ Deployment successful!${NC}"
    else
        echo -e "${RED}❌ Deployment failed${NC}"
        exit 1
    fi
else
    echo "Deployment cancelled"
    exit 0
fi
echo ""

# Step 7: Wait for propagation
echo "Step 7: Waiting for Firebase propagation (2 minutes)..."
echo "☕ Grab a coffee while we wait..."
sleep 120
echo -e "${GREEN}✅ Wait complete${NC}"
echo ""

# Step 8: Test deployed files
echo "Step 8: Testing deployed AASA files..."
echo ""

echo "Testing root path..."
ROOT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://plendy.app/apple-app-site-association)
if [ "$ROOT_STATUS" = "200" ]; then
    echo -e "${GREEN}✅ Root path: HTTP $ROOT_STATUS${NC}"
else
    echo -e "${RED}❌ Root path: HTTP $ROOT_STATUS${NC}"
fi

echo "Testing .well-known path..."
WELLKNOWN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://plendy.app/.well-known/apple-app-site-association)
if [ "$WELLKNOWN_STATUS" = "200" ]; then
    echo -e "${GREEN}✅ .well-known path: HTTP $WELLKNOWN_STATUS${NC}"
else
    echo -e "${RED}❌ .well-known path: HTTP $WELLKNOWN_STATUS${NC}"
fi
echo ""

# Compare content
echo "Comparing content..."
curl -s https://plendy.app/apple-app-site-association > /tmp/aasa-root.json
curl -s https://plendy.app/.well-known/apple-app-site-association > /tmp/aasa-wellknown.json

if diff /tmp/aasa-root.json /tmp/aasa-wellknown.json > /dev/null; then
    echo -e "${GREEN}✅ Both URLs return IDENTICAL content${NC}"
    echo ""
    echo "Content:"
    cat /tmp/aasa-root.json | python3 -m json.tool || cat /tmp/aasa-root.json
else
    echo -e "${RED}❌ URLs return DIFFERENT content!${NC}"
    echo ""
    echo "Root path content:"
    cat /tmp/aasa-root.json | python3 -m json.tool || cat /tmp/aasa-root.json
    echo ""
    echo ".well-known path content:"
    cat /tmp/aasa-wellknown.json | python3 -m json.tool || cat /tmp/aasa-wellknown.json
fi
echo ""

# Cleanup
rm -f /tmp/aasa-root.json /tmp/aasa-wellknown.json

# Final instructions
echo "=========================================="
echo "🎉 Deployment Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo ""
echo "1. ⏰ Wait 6-24 hours for Apple's CDN to refresh"
echo "   Apple's CDN: https://app-site-association.cdn-apple.com/a/v1/plendy.app"
echo ""
echo "2. 🔍 Validate with Apple's tool:"
echo "   https://search.developer.apple.com/appsearch-validation-tool/"
echo "   Enter: plendy.app"
echo ""
echo "3. 📱 Test on iOS device:"
echo "   - Delete and reinstall your app"
echo "   - Send yourself: https://plendy.app/shared-category/3fUjNojtxXsk"
echo "   - Tap the link - should open in app!"
echo ""
echo "4. 🐛 If issues persist:"
echo "   - Check Xcode Signing & Capabilities → Associated Domains"
echo "   - Verify provisioning profile includes Associated Domains"
echo "   - Contact Apple Developer Support to clear CDN cache"
echo ""
echo -e "${GREEN}✅ All done!${NC}"

