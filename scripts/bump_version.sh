#!/bin/bash

# Change to project root directory
cd "$(dirname "$0")/.."

# Check if argument is provided, default to 'build'
VERSION_TYPE=${1:-build}

echo "Bumping $VERSION_TYPE version..."
dart run scripts/bump_version.dart "$VERSION_TYPE"

if [ $? -eq 0 ]; then
    echo ""
    echo "Version bump completed successfully!"
    echo ""
    echo "Usage examples:"
    echo "  ./scripts/bump_version.sh          (bumps build number)"
    echo "  ./scripts/bump_version.sh build    (bumps build number)"
    echo "  ./scripts/bump_version.sh patch    (bumps patch version)"
    echo "  ./scripts/bump_version.sh minor    (bumps minor version)"
    echo "  ./scripts/bump_version.sh major    (bumps major version)"
else
    echo "Version bump failed!"
    exit 1
fi 