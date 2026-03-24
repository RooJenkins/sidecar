#!/bin/bash
# Bump version number in Info.plist
# Usage: bump-version.sh [major|minor|patch|build]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$(dirname "$SCRIPT_DIR")/Info.plist"

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "${1:-build}" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    build)
        CURRENT_BUILD=$((CURRENT_BUILD + 1))
        /usr/libexec/PlistBuddy -c "Set CFBundleVersion $CURRENT_BUILD" "$PLIST"
        echo "Build: $CURRENT_BUILD (version stays $CURRENT_VERSION)"
        exit 0
        ;;
    *)
        echo "Usage: bump-version.sh [major|minor|patch|build]"
        exit 1
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
CURRENT_BUILD=$((CURRENT_BUILD + 1))

/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $NEW_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $CURRENT_BUILD" "$PLIST"

echo "Version: $CURRENT_VERSION → $NEW_VERSION (build $CURRENT_BUILD)"
