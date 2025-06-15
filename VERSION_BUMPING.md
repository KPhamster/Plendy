# Version Bumping Guide for Plendy

This document outlines several methods to automatically bump version codes in your Flutter project.

## Current Version Format

Your `pubspec.yaml` currently uses the format: `version: 1.0.0+1`
- `1.0.0` is the version name (major.minor.patch)
- `+1` is the build number/version code

## Method 1: Custom Dart Script (Recommended for Local Development)

### Usage
```bash
# Windows
scripts\bump_version.bat [build|patch|minor|major]

# Unix/Linux/macOS
./scripts/bump_version.sh [build|patch|minor|major]

# Direct Dart execution
dart run scripts/bump_version.dart [build|patch|minor|major]
```

### Examples
```bash
scripts\bump_version.bat          # 1.0.0+1 → 1.0.0+2
scripts\bump_version.bat build    # 1.0.0+1 → 1.0.0+2
scripts\bump_version.bat patch    # 1.0.0+1 → 1.0.1+2
scripts\bump_version.bat minor    # 1.0.0+1 → 1.1.0+2
scripts\bump_version.bat major    # 1.0.0+1 → 2.0.0+2
```

### Features
- ✅ Cross-platform (Windows/Unix)
- ✅ Supports all version types
- ✅ No external dependencies
- ✅ Fast execution
- ✅ Clear error messages

## Method 2: Cider Package (Professional Tool)

### Installation
```bash
dart pub global activate cider
```

### Usage
```bash
cider bump build     # Bump build number
cider bump patch     # Bump patch version
cider bump minor     # Bump minor version
cider bump major     # Bump major version
cider bump breaking  # Bump breaking version (major for 1.x.x, minor for 0.x.x)

# Set specific version
cider version 2.1.0+5

# Get current version
cider version
```

### Features
- ✅ Industry standard tool
- ✅ Semver compliant
- ✅ Supports changelog generation
- ✅ Git integration
- ✅ Null safety compatible

## Method 3: GitHub Actions Automation

### Automatic Version Bumping
The GitHub Actions workflow (`.github/workflows/version-bump.yml`) provides:

1. **Automatic build bumping** on push to main/master
2. **Manual version bumping** via GitHub UI
3. **Git tagging** for releases

### Manual Trigger
1. Go to GitHub Actions tab
2. Select "Version Bump" workflow
3. Click "Run workflow"
4. Choose version type (build/patch/minor/major)

### Features
- ✅ Automated on git push
- ✅ Manual control via GitHub UI
- ✅ Creates git tags for releases
- ✅ Commits changes automatically

## Method 4: Build and Bump Script (All-in-One)

### Usage
```bash
# Windows
scripts\build_and_bump.bat [options]

# Options:
--aab           # Build Android App Bundle instead of APK
--apk           # Build APK (default)
--release       # Build release version (default: debug)
--version TYPE  # Version type: build|patch|minor|major
```

### Examples
```bash
scripts\build_and_bump.bat                           # Debug APK, bump build
scripts\build_and_bump.bat --release                 # Release APK, bump build
scripts\build_and_bump.bat --aab --release           # Release AAB, bump build
scripts\build_and_bump.bat --version patch --release # Release APK, bump patch
```

### Features
- ✅ Version bump + build in one command
- ✅ Supports APK and AAB builds
- ✅ Debug and release builds
- ✅ Shows build output location

## Method 5: Flutter CLI (Built-in)

### Usage
```bash
# Build with specific version
flutter build apk --build-name=1.2.0 --build-number=42

# Build AAB with version
flutter build appbundle --build-name=1.2.0 --build-number=42
```

### Features
- ✅ No additional tools needed
- ✅ Direct Flutter integration
- ❌ Manual version management
- ❌ No automatic incrementing

## Recommended Workflows

### For Local Development
1. Use the custom Dart script: `scripts\bump_version.bat build`
2. Or use Cider: `cider bump build`

### For Releases
1. Use the build script: `scripts\build_and_bump.bat --version patch --release`
2. Or use GitHub Actions for automated releases

### For CI/CD
1. Use GitHub Actions workflow for automatic version bumping
2. Integrate with your deployment pipeline

## Version Strategy Recommendations

### Build Number (`+X`)
- Increment for every build
- Use for internal testing
- No user-facing changes

### Patch Version (`X.X.+1`)
- Bug fixes
- Small improvements
- No new features

### Minor Version (`X.+1.0`)
- New features
- Backward compatible changes
- API additions

### Major Version (`+1.0.0`)
- Breaking changes
- Major feature releases
- API changes

## Integration with Android

Your Android build automatically uses the Flutter version:
- `versionCode` = build number from pubspec.yaml
- `versionName` = version name from pubspec.yaml

No additional configuration needed in `android/app/build.gradle`.

## Best Practices

1. **Always bump build number** when creating any build
2. **Use semantic versioning** for user-facing releases
3. **Automate version bumping** in CI/CD pipelines
4. **Tag releases** in git for tracking
5. **Keep changelog** updated with version changes

## Troubleshooting

### Script Permission Issues (Unix/Linux/macOS)
```bash
chmod +x scripts/bump_version.sh
```

### Cider Not Found
```bash
# Add to PATH or use full path
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

### GitHub Actions Not Running
- Check repository permissions
- Ensure workflows are enabled
- Verify branch protection rules

## Files Created/Modified

- `scripts/bump_version.dart` - Core version bumping logic
- `scripts/bump_version.bat` - Windows wrapper script
- `scripts/bump_version.sh` - Unix wrapper script
- `scripts/build_and_bump.bat` - All-in-one build script
- `.github/workflows/version-bump.yml` - GitHub Actions workflow
- `VERSION_BUMPING.md` - This documentation

All scripts are ready to use immediately! 