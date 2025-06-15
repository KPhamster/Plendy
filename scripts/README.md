# Scripts Directory - Quick Reference

## Version Bumping Scripts

### Quick Commands
```bash
# Bump build number (most common)
scripts\bump_version.bat

# Bump patch version
scripts\bump_version.bat patch

# Build and bump in one command
scripts\build_and_bump.bat --release
```

### Available Scripts

| Script | Purpose | Platform |
|--------|---------|----------|
| `bump_version.dart` | Core version bumping logic | Cross-platform |
| `bump_version.bat` | Windows version bump wrapper | Windows |
| `bump_version.sh` | Unix version bump wrapper | Unix/Linux/macOS |
| `build_and_bump.bat` | Build + version bump combo | Windows |
| `build_web.bat` | Web build script | Windows |
| `build_web.sh` | Web build script | Unix/Linux/macOS |

### Version Types
- `build` - Increment build number (1.0.0+1 → 1.0.0+2)
- `patch` - Increment patch version (1.0.0+1 → 1.0.1+2)
- `minor` - Increment minor version (1.0.0+1 → 1.1.0+2)
- `major` - Increment major version (1.0.0+1 → 2.0.0+2)

### Alternative Tools
```bash
# Using Cider (install once: dart pub global activate cider)
cider bump build
cider bump patch
cider version
```

For detailed documentation, see `../VERSION_BUMPING.md` 