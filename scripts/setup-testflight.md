# TestFlight Setup Guide for Plendy

## Prerequisites
1. Apple Developer Account (free or paid)
2. Access to a Mac OR use GitHub Actions (recommended)

## Step 1: Apple Developer Account Setup

### A. Create Apple ID & Developer Account
1. Go to [developer.apple.com](https://developer.apple.com)
2. Sign in with your Apple ID
3. Enroll in Apple Developer Program (free tier works for TestFlight)

### B. Get Your Team ID
1. Go to [developer.apple.com/account](https://developer.apple.com/account)
2. Click "Membership" in the sidebar
3. Copy your **Team ID** (10-character string like `ABC123DEFG`)

### C. Create App Store Connect API Key
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Go to "Users and Access" → "Keys"
3. Click "+" to create new API key
4. Name: "Plendy CI/CD"
5. Access: "Developer"
6. Click "Generate"
7. **Download the .p8 file** (you can only download once!)
8. Note the **Key ID** and **Issuer ID**

## Step 2: Update Bundle Identifier

You need to change from `com.example.plendy` to something unique:

### Option A: Use your domain
- `com.yourdomain.plendy`

### Option B: Use your name
- `com.yourname.plendy`

### Option C: Use reverse GitHub username
- `com.github.yourusername.plendy`

**Example:** If your name is John Smith, use `com.johnsmith.plendy`

## Step 3: Register Your App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click "My Apps" → "+" → "New App"
3. Fill in:
   - **Platform:** iOS
   - **Name:** Plendy
   - **Primary Language:** English
   - **Bundle ID:** Your chosen bundle ID (e.g., `com.yourname.plendy`)
   - **SKU:** plendy-ios (or any unique identifier)

## Step 4: GitHub Secrets Setup

In your GitHub repository, go to Settings → Secrets and Variables → Actions, and add these secrets:

### Required Secrets:
1. **`IOS_CERTIFICATE_BASE64`** - Your iOS distribution certificate (base64 encoded)
2. **`IOS_CERTIFICATE_PASSWORD`** - Password for the certificate
3. **`IOS_PROVISIONING_PROFILE_BASE64`** - Your provisioning profile (base64 encoded)
4. **`APP_STORE_CONNECT_API_KEY_ID`** - Key ID from Step 1C
5. **`APP_STORE_CONNECT_API_ISSUER_ID`** - Issuer ID from Step 1C
6. **`APP_STORE_CONNECT_API_KEY_BASE64`** - The .p8 file content (base64 encoded)
7. **`KEYCHAIN_PASSWORD`** - Any secure password for the build keychain

## Step 5: Update Project Configuration

### A. Update Bundle Identifier in iOS Project
Run this command to update your bundle identifier:

```bash
# Replace 'com.yourname.plendy' with your chosen bundle ID
flutter pub run change_app_package_name:main com.yourname.plendy
```

### B. Update ExportOptions.plist
Edit `ios/ExportOptions.plist` and replace `REPLACE_WITH_YOUR_TEAM_ID` with your actual Team ID.

## Step 6: Getting Certificates (Choose One Method)

### Method A: Using Xcode (Requires Mac)
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select Runner project → Signing & Capabilities
3. Select your Team
4. Xcode will automatically create certificates and provisioning profiles
5. Export certificate from Keychain Access
6. Download provisioning profile from Developer Portal

### Method B: Using Fastlane (Recommended)
1. Install Fastlane: `gem install fastlane`
2. Run: `fastlane match init`
3. Follow the setup to create certificates automatically

### Method C: Manual Creation
1. Go to [developer.apple.com/certificates](https://developer.apple.com/certificates)
2. Create iOS Distribution certificate
3. Create App Store provisioning profile
4. Download both files

## Step 7: Convert Files to Base64

For the GitHub secrets, you need to convert your files to base64:

### On Mac/Linux:
```bash
# Certificate
base64 -i YourCertificate.p12 | pbcopy

# Provisioning Profile
base64 -i YourProfile.mobileprovision | pbcopy

# API Key
base64 -i AuthKey_KEYID.p8 | pbcopy
```

### On Windows:
```powershell
# Certificate
[Convert]::ToBase64String([IO.File]::ReadAllBytes("YourCertificate.p12")) | Set-Clipboard

# Provisioning Profile
[Convert]::ToBase64String([IO.File]::ReadAllBytes("YourProfile.mobileprovision")) | Set-Clipboard

# API Key
[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_KEYID.p8")) | Set-Clipboard
```

## Step 8: Deploy to TestFlight

Once everything is set up:

1. **Push to GitHub** - The workflow will trigger automatically
2. **Or manually trigger** - Go to GitHub Actions → "iOS TestFlight Deployment" → "Run workflow"
3. **Wait for build** - Takes about 10-15 minutes
4. **Check App Store Connect** - Your build will appear in TestFlight section
5. **Add yourself as tester** - Go to TestFlight → Internal Testing → Add yourself
6. **Install TestFlight app** on your iPhone
7. **Accept invitation** and install your app!

## Troubleshooting

### Common Issues:
1. **Bundle ID already exists** - Choose a different bundle identifier
2. **Certificate issues** - Make sure certificate is for distribution, not development
3. **Provisioning profile mismatch** - Ensure profile matches your bundle ID and certificate
4. **Team ID wrong** - Double-check your Team ID in Apple Developer account

### Getting Help:
- Check GitHub Actions logs for detailed error messages
- Verify all secrets are correctly set
- Ensure your Apple Developer account has necessary permissions

## Alternative: Cloud Mac Services

If you prefer not to use GitHub Actions:

1. **MacStadium** - Rent a Mac in the cloud ($79/month)
2. **AWS EC2 Mac** - Amazon's cloud Macs (pay per hour)
3. **MacinCloud** - Virtual Mac rental ($20/month)

With a cloud Mac, you can use Xcode directly and follow traditional iOS development workflows. 