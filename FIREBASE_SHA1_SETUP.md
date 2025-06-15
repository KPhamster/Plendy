# 🔑 Firebase SHA-1 Certificate Setup for Google Sign-In

## Your SHA-1 Fingerprints

### Release (Production) SHA-1:
```
ED:95:A0:EE:54:4E:97:D3:B2:86:44:49:DD:DC:23:DA:0D:A8:9F:05
```

### Debug (Development) SHA-1:
```
02:FF:48:FD:64:B1:FE:97:76:DC:EE:CB:83:99:B5:E8:39:C1:F7:30
```

## Setup Steps

1. **Go to Firebase Console**: https://console.firebase.google.com/
2. **Select project**: `plendy-7df50`
3. **Project Settings** (⚙️ gear icon)
4. **Find Android app**: `com.plendy.app`
5. **Add both SHA-1 fingerprints above**
6. **Download updated `google-services.json`**
7. **Replace** `android/app/google-services.json`

## After Adding SHA-1 Certificates

1. Clean and rebuild your app:
   ```bash
   flutter clean
   flutter run
   ```

2. Test Google Sign-In functionality

## Notes

- **Release SHA-1**: Required for production app (Google Play Store)
- **Debug SHA-1**: Required for development/testing
- Both certificates are from your current keystore configuration
- Google Sign-In will not work without these certificates in Firebase 