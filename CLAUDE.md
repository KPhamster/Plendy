# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Essential Commands

This is a Flutter application with Firebase backend. Development uses standard Flutter toolchain:

- **Flutter**: `flutter run` - Start development server
- **Build Android**: `flutter build apk` or `flutter build appbundle`
- **Build iOS**: `flutter build ios` 
- **Tests**: `flutter test`
- **Dependencies**: `flutter pub get`
- **Clean**: `flutter clean`

**Platform-specific builds:**
- **Android**: Requires Android SDK and proper signing configuration
- **iOS**: Requires Xcode and Apple Developer account setup
- **Web**: `flutter build web`

## Architecture Overview

This is a **Flutter cross-platform mobile application** called Plendy, designed for sharing and organizing location-based experiences with social features.

### Core Architecture

**Technology Stack:**
- **Frontend**: Flutter (Dart) with cross-platform support (iOS, Android, Web, Desktop)
- **Backend**: Firebase (Firestore, Authentication, Functions, Storage, Hosting)
- **State Management**: Provider pattern with ChangeNotifier
- **Maps Integration**: Google Maps API with custom implementations
- **Web Scraping**: Custom logic for social media URL previews (Instagram, Facebook, Yelp)

### Project Structure

**Core Application (`lib/`):**
- `main.dart` - Application entry point with Firebase initialization
- `models/` - Data models (User, Experience, Review, Comment, Share permissions)
- `screens/` - UI screens and navigation
- `services/` - Business logic and external API integrations
- `widgets/` - Reusable UI components
- `config/` - API keys and configuration templates

**Platform Configurations:**
- `android/` - Android-specific configuration and native code
- `ios/` - iOS-specific configuration and native code  
- `web/` - Web platform files and configurations
- `linux/`, `macos/`, `windows/` - Desktop platform support

**Backend (`functions/`):**
- Node.js Firebase Functions for server-side operations
- User deletion and data management endpoints

### Key Features & Integrations

**Social Sharing:**
- URL preview generation for Instagram, Facebook, Yelp
- Custom web logic for social media content extraction
- Share permission management between users

**Location Services:**
- Google Maps integration with custom markers and clustering
- Location picker with geocoding
- Experience categorization with color-coded categories

**User Management:**
- Firebase Authentication with email/password and social logins
- User profiles with customizable categories
- Experience sharing and collaboration features

**Media Handling:**
- Image upload and storage via Firebase Storage
- Full-screen media viewer with navigation
- Optimized image loading and caching

### Configuration Requirements

**API Keys (Templates in `lib/config/`):**
- Google Maps API key
- Google Knowledge Graph API
- Firebase configuration
- Social media API credentials

**Build Configuration:**
- Android: Signing keys, permissions, build variants
- iOS: Provisioning profiles, capabilities, build schemes
- Firebase: Project configuration and service accounts

### Development Workflow

**Setup Requirements:**
1. Flutter SDK installation and setup
2. Firebase project configuration
3. API key configuration from templates
4. Platform-specific SDK setup (Android Studio, Xcode)

**Key Development Patterns:**
- **Provider Pattern**: Used throughout for state management
- **Service Layer**: Clean separation between UI and business logic
- **Model-View Architecture**: Clear data flow with reactive updates
- **Platform Channels**: Native code integration where needed

**Testing Strategy:**
- Widget tests for UI components
- Unit tests for services and models
- Integration tests for critical user flows

### Firebase Integration

**Services Used:**
- **Firestore**: Primary database for experiences, users, reviews
- **Authentication**: User management and social logins
- **Storage**: Image and media file storage
- **Functions**: Server-side business logic
- **Hosting**: Web deployment platform

**Security Rules:**
- Firestore security rules for data access control
- Storage rules for media file permissions
- Function authentication and authorization

### Build & Deployment

**Development Builds:**
- Debug builds with hot reload for rapid development
- Emulator support for both Android and iOS

**Production Builds:**
- Release builds with code obfuscation
- App signing for store distribution
- CI/CD pipelines via GitHub Actions

**Distribution:**
- Google Play Store (Android)
- Apple App Store (iOS) 
- Firebase Hosting (Web)
- Manual distribution for desktop platforms

### Deep Linking for Discovery Share URLs

**Implementation:**
The discovery share feature allows users to share public experiences from the Discovery feed. When a user taps a shared discovery link:
- If the Plendy app is installed: Opens the app directly to the Discovery screen showing the shared preview
- If the Plendy app is not installed: Opens the web version at `https://plendy.app/discovery-share/{token}`

**URL Format:**
- Generated URL: `https://plendy.app/discovery-share/{token}`
- Token: 12-character alphanumeric token stored in Firestore `discovery_shares` collection

**Platform Configuration:**

*Android:*
- Configured via intent filters in `android/app/src/main/AndroidManifest.xml`
- App Links with autoVerify for secure deep linking
- Path prefix: `/discovery-share`

*iOS:*
- Configured via `CFBundleURLTypes` in `ios/Runner/Info.plist`
- Custom URL scheme: `plendy://`
- Universal Links via `apple-app-site-association` file

**Flow:**
1. User taps "Share" button on a discovery item
2. `DiscoveryShareService.createShare()` creates a Firestore entry and returns URL
3. User shares the URL via social media, messaging, or email
4. On app install/tap:
   - `main.dart` deep link handler intercepts the URL
   - `_handleIncomingUri()` extracts the token from `/discovery-share/{token}`
   - `DiscoveryShareCoordinator` passes token to `DiscoveryScreen`
   - `showSharedPreview()` fetches and displays the shared media
5. On web:
   - URL routes to `DiscoverySharePreviewScreen`
   - Same `DiscoveryScreen` component displays the preview

**Files Modified:**
- `lib/services/discovery_share_service.dart` - URL generation (already configured)
- `lib/screens/discovery_share_preview_screen.dart` - Web preview wrapper
- `lib/providers/discovery_share_coordinator.dart` - Deep link coordination
- `lib/main.dart` - Deep link routing (lines 724-747)
- `android/app/src/main/AndroidManifest.xml` - Android App Links
- `ios/Runner/Info.plist` - iOS URL schemes
- `web/apple-app-site-association` - iOS universal links mapping