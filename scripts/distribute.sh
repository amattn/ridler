#!/bin/bash
set -euo pipefail

# Ridler Distribution Script
# Usage: ./scripts/distribute.sh [--skip-notarize] [--skip-dmg]
#
# Prerequisites:
#   - Xcode with valid Developer ID Application certificate
#   - App-specific password stored in Keychain for notarization:
#       xcrun notarytool store-credentials "Ridler-Notarize" \
#         --apple-id "your@email.com" \
#         --team-id "YOUR_TEAM_ID" \
#         --password "app-specific-password"
#
# Environment variables (optional overrides):
#   RIDLER_TEAM_ID        - Apple Developer Team ID
#   RIDLER_SIGN_IDENTITY  - Code signing identity (default: "Developer ID Application")
#   RIDLER_NOTARY_PROFILE - notarytool credentials profile (default: "Ridler-Notarize")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODE_PROJECT="$PROJECT_DIR/Ridler/Ridler.xcodeproj"
SCHEME="Ridler"
CONFIGURATION="Release"
ARCHIVE_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$ARCHIVE_DIR/Ridler.xcarchive"
APP_NAME="Ridler"
DMG_NAME="Ridler"

SIGN_IDENTITY="${RIDLER_SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${RIDLER_NOTARY_PROFILE:-Ridler-Notarize}"

SKIP_NOTARIZE=false
SKIP_DMG=false

for arg in "$@"; do
    case $arg in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --skip-dmg) SKIP_DMG=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-notarize] [--skip-dmg]"
            echo ""
            echo "Options:"
            echo "  --skip-notarize  Skip notarization step"
            echo "  --skip-dmg       Skip DMG creation"
            echo ""
            echo "Environment variables:"
            echo "  RIDLER_TEAM_ID        Apple Developer Team ID"
            echo "  RIDLER_SIGN_IDENTITY  Code signing identity (default: 'Developer ID Application')"
            echo "  RIDLER_NOTARY_PROFILE notarytool credentials profile (default: 'Ridler-Notarize')"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

echo "=== Ridler Distribution Build ==="
echo "Project: $XCODE_PROJECT"
echo "Configuration: $CONFIGURATION"
echo ""

# Clean build directory
echo "--- Cleaning build directory ---"
rm -rf "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_DIR"

# Step 1: Archive
echo "--- Step 1: Archiving $SCHEME ---"
xcodebuild archive \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -arch arm64 \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    | tail -5

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive failed — $ARCHIVE_PATH not found"
    exit 1
fi
echo "Archive created: $ARCHIVE_PATH"

# Step 2: Export app from archive
echo "--- Step 2: Exporting app ---"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
EXPORT_DIR="$ARCHIVE_DIR/export"
mkdir -p "$EXPORT_DIR"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    echo "Archive contents:"
    find "$ARCHIVE_PATH" -name "*.app" 2>/dev/null || echo "  No .app found"
    exit 1
fi

cp -R "$APP_PATH" "$EXPORT_DIR/$APP_NAME.app"
echo "Exported: $EXPORT_DIR/$APP_NAME.app"

# Step 3: Code sign for distribution
echo "--- Step 3: Code signing ---"
codesign --deep --force --options runtime \
    --sign "$SIGN_IDENTITY" \
    "$EXPORT_DIR/$APP_NAME.app" 2>&1 || {
    echo ""
    echo "WARNING: Code signing with '$SIGN_IDENTITY' failed."
    echo "If you don't have a Developer ID certificate, use --skip-notarize"
    echo "The app will still work locally without notarization."
    echo ""
    # Fall back to ad-hoc signing for local use
    codesign --deep --force --sign - "$EXPORT_DIR/$APP_NAME.app"
    SKIP_NOTARIZE=true
}

codesign --verify --deep --strict "$EXPORT_DIR/$APP_NAME.app"
echo "Code signing verified"

# Step 4: Notarize
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "--- Step 4: Notarizing ---"

    # Create zip for notarization
    NOTARIZE_ZIP="$ARCHIVE_DIR/$APP_NAME-notarize.zip"
    ditto -c -k --keepParent "$EXPORT_DIR/$APP_NAME.app" "$NOTARIZE_ZIP"

    echo "Submitting to Apple Notary Service..."
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        2>&1 | tee "$ARCHIVE_DIR/notarize-log.txt"

    NOTARY_STATUS=$(grep -o "status: [A-Za-z]*" "$ARCHIVE_DIR/notarize-log.txt" | tail -1 | cut -d' ' -f2)

    if [ "$NOTARY_STATUS" != "Accepted" ]; then
        echo "ERROR: Notarization failed with status: $NOTARY_STATUS"
        echo "Check $ARCHIVE_DIR/notarize-log.txt for details"
        exit 1
    fi

    # Staple the notarization ticket
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$EXPORT_DIR/$APP_NAME.app"
    echo "Notarization complete and stapled"

    rm -f "$NOTARIZE_ZIP"
else
    echo "--- Step 4: Skipping notarization ---"
fi

# Step 5: Create DMG
if [ "$SKIP_DMG" = false ]; then
    echo "--- Step 5: Creating DMG ---"

    DMG_STAGING="$ARCHIVE_DIR/dmg-staging"
    DMG_PATH="$ARCHIVE_DIR/$DMG_NAME.dmg"

    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"

    # Copy app to staging
    cp -R "$EXPORT_DIR/$APP_NAME.app" "$DMG_STAGING/"

    # Create symlink to /Applications for drag-to-install
    ln -s /Applications "$DMG_STAGING/Applications"

    # Create DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH"

    # Sign the DMG
    codesign --sign "$SIGN_IDENTITY" "$DMG_PATH" 2>/dev/null || \
        codesign --sign - "$DMG_PATH" 2>/dev/null || true

    # Notarize DMG if notarization is enabled
    if [ "$SKIP_NOTARIZE" = false ]; then
        echo "Notarizing DMG..."
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
        xcrun stapler staple "$DMG_PATH"
    fi

    rm -rf "$DMG_STAGING"

    echo ""
    echo "=== Distribution Complete ==="
    echo "DMG: $DMG_PATH"
    echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
else
    echo "--- Step 5: Skipping DMG creation ---"
    echo ""
    echo "=== Distribution Complete ==="
    echo "App: $EXPORT_DIR/$APP_NAME.app"
fi

echo ""
echo "Done!"
