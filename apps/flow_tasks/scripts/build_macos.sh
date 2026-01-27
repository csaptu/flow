#!/bin/bash
set -e

# =============================================================================
# Flow Tasks - macOS Build & Distribution Script
# =============================================================================
#
# Usage:
#   ./scripts/build_macos.sh              # Build unsigned DMG (for testing)
#   ./scripts/build_macos.sh --sign       # Build signed + notarized DMG
#
# Requirements:
#   - Flutter SDK
#   - Xcode Command Line Tools
#   - create-dmg (brew install create-dmg)
#   - Apple Developer account (for signing)
#
# =============================================================================

# Configuration - UPDATE THESE after Apple Developer account is active
DEVELOPER_ID=""                          # e.g., "Developer ID Application: Your Name (TEAMID)"
TEAM_ID=""                               # e.g., "XXXXXXXXXX" (10 characters)
APPLE_ID=""                              # Your Apple ID email for notarization
APP_SPECIFIC_PASSWORD=""                 # App-specific password from appleid.apple.com

# Production API URLs (Railway)
SHARED_API_URL="https://shared-api-production.up.railway.app/api/v1"
TASKS_API_URL="https://tasks-api-production-0064.up.railway.app/api/v1"
PROJECTS_API_URL="https://projects-api-production-95b7.up.railway.app/api/v1"

# App Configuration
APP_NAME="Flow Tasks"
BUNDLE_ID="com.flow.tasks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/macos/Build/Products/Release"
DMG_DIR="$PROJECT_DIR/dist"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
SIGN_APP=false
for arg in "$@"; do
    case $arg in
        --sign)
            SIGN_APP=true
            shift
            ;;
    esac
done

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Flow Tasks - macOS Build Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter not found. Please install Flutter.${NC}"
    exit 1
fi

if ! command -v create-dmg &> /dev/null; then
    echo -e "${RED}Error: create-dmg not found. Install with: brew install create-dmg${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites OK${NC}"
echo ""

# Get version from pubspec.yaml
VERSION=$(grep "^version:" "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //' | cut -d'+' -f1)
BUILD_NUMBER=$(grep "^version:" "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //' | cut -d'+' -f2)
DMG_NAME="FlowTasks-${VERSION}.dmg"

echo "App Version: $VERSION (build $BUILD_NUMBER)"
echo "Output: $DMG_DIR/$DMG_NAME"
echo ""

# Step 1: Clean and build Flutter app
echo -e "${YELLOW}Step 1: Building Flutter app (Release)...${NC}"
echo "Using production APIs:"
echo "  Shared:   $SHARED_API_URL"
echo "  Tasks:    $TASKS_API_URL"
echo "  Projects: $PROJECTS_API_URL"
echo ""

cd "$PROJECT_DIR"
flutter clean
flutter pub get
flutter build macos --release \
    --dart-define=SHARED_API_URL="$SHARED_API_URL" \
    --dart-define=TASKS_API_URL="$TASKS_API_URL" \
    --dart-define=PROJECTS_API_URL="$PROJECTS_API_URL"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: Build failed. App not found at $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Build complete!${NC}"
echo ""

# Step 2: Code signing (if requested)
if [ "$SIGN_APP" = true ]; then
    echo -e "${YELLOW}Step 2: Code signing...${NC}"

    if [ -z "$DEVELOPER_ID" ] || [ -z "$TEAM_ID" ]; then
        echo -e "${RED}Error: DEVELOPER_ID and TEAM_ID must be set for signing.${NC}"
        echo "Edit this script and fill in your credentials."
        exit 1
    fi

    # Sign all frameworks and dylibs first
    echo "Signing frameworks..."
    find "$APP_PATH/Contents/Frameworks" -name "*.framework" -exec \
        codesign --force --options runtime --sign "$DEVELOPER_ID" {} \;

    find "$APP_PATH/Contents/Frameworks" -name "*.dylib" -exec \
        codesign --force --options runtime --sign "$DEVELOPER_ID" {} \;

    # Sign the main app
    echo "Signing app bundle..."
    codesign --force --options runtime --entitlements "$PROJECT_DIR/macos/Runner/Release.entitlements" \
        --sign "$DEVELOPER_ID" "$APP_PATH"

    # Verify signature
    echo "Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"

    echo -e "${GREEN}Code signing complete!${NC}"
else
    echo -e "${YELLOW}Step 2: Skipping code signing (use --sign to enable)${NC}"
fi
echo ""

# Step 3: Create DMG
echo -e "${YELLOW}Step 3: Creating DMG...${NC}"

mkdir -p "$DMG_DIR"
rm -f "$DMG_DIR/$DMG_NAME"

# Simple DMG creation (AppleScript window styling can timeout)
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_DIR/$DMG_NAME"

echo -e "${GREEN}DMG created: $DMG_DIR/$DMG_NAME${NC}"
echo ""

# Step 4: Notarization (if signing enabled)
if [ "$SIGN_APP" = true ]; then
    echo -e "${YELLOW}Step 4: Notarizing DMG...${NC}"

    if [ -z "$APPLE_ID" ] || [ -z "$APP_SPECIFIC_PASSWORD" ]; then
        echo -e "${RED}Error: APPLE_ID and APP_SPECIFIC_PASSWORD must be set for notarization.${NC}"
        echo "Create an app-specific password at https://appleid.apple.com"
        exit 1
    fi

    # Submit for notarization
    echo "Submitting for notarization (this may take a few minutes)..."
    xcrun notarytool submit "$DMG_DIR/$DMG_NAME" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --wait

    # Staple the notarization ticket
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_DIR/$DMG_NAME"

    echo -e "${GREEN}Notarization complete!${NC}"
else
    echo -e "${YELLOW}Step 4: Skipping notarization (use --sign to enable)${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "DMG Location: $DMG_DIR/$DMG_NAME"
echo "Size: $(du -h "$DMG_DIR/$DMG_NAME" | cut -f1)"
echo ""

if [ "$SIGN_APP" = false ]; then
    echo -e "${YELLOW}Note: This DMG is unsigned and will show security warnings.${NC}"
    echo "Run with --sign flag after configuring credentials for distribution."
fi
