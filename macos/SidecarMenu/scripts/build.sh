#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="SidecarMenu"
BUNDLE_ID="com.sidecar.menu"
ENTITLEMENTS="$PROJECT_DIR/SidecarMenu.entitlements"
INFO_PLIST="$PROJECT_DIR/Info.plist"
PRIVACY_MANIFEST="$PROJECT_DIR/PrivacyInfo.xcprivacy"

# Parse args
SIGN=""
NOTARIZE=""
INSTALL=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --sign)    SIGN="$2"; shift 2 ;;
        --notarize) NOTARIZE=1; shift ;;
        --install) INSTALL=1; shift ;;
        --help)
            echo "Usage: build.sh [--sign IDENTITY] [--notarize] [--install]"
            echo ""
            echo "  --sign IDENTITY   Code sign with Developer ID (e.g. 'Developer ID Application: Name (TEAMID)')"
            echo "  --notarize        Submit to Apple for notarization (requires --sign)"
            echo "  --install         Copy to /Applications after build"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

cd "$PROJECT_DIR"

# Read version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO_PLIST")
echo "Building $APP_NAME v$VERSION ($BUILD)..."

# Build release
swift build -c release 2>&1

# Construct .app bundle
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

# Copy privacy manifest
if [ -f "$PRIVACY_MANIFEST" ]; then
    cp "$PRIVACY_MANIFEST" "$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
fi

# Copy app icon if it exists
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "Built $APP_BUNDLE"

# Code sign
if [ -n "$SIGN" ]; then
    echo "Signing with: $SIGN"
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN" \
        --timestamp \
        "$APP_BUNDLE"
    echo "Verifying signature..."
    codesign --verify --verbose "$APP_BUNDLE"
fi

# Notarize
if [ -n "$NOTARIZE" ]; then
    if [ -z "$SIGN" ]; then
        echo "Error: --notarize requires --sign"
        exit 1
    fi

    ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
    echo "Creating zip for notarization..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    echo "Submitting to Apple for notarization..."
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "notary" --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"

    rm "$ZIP_PATH"
    echo "Notarization complete."
fi

# Create distributable DMG
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
echo "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH" 2>/dev/null
echo "DMG created: $DMG_PATH"

# Install
if [ -n "$INSTALL" ]; then
    DEST="/Applications/$APP_NAME.app"
    echo "Installing to $DEST..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
    rm -rf "$DEST"
    cp -R "$APP_BUNDLE" "$DEST"
    echo "Installed. Launch with: open /Applications/$APP_NAME.app"
fi

echo "Done."
