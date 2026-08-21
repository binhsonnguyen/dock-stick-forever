#!/bin/bash

# Dock Stick Forever .app Builder
# Builds the macOS application bundle from Swift Package Manager

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔨 Building Dock Stick Forever.app${NC}"
echo ""

# release   - optimised, this machine's architecture (default)
# universal - optimised, arm64 + x86_64; use this for anything you publish
# debug     - unoptimised
BUILD_CONFIG="${1:-release}"
APP_NAME="DockStickForever"
BUNDLE_NAME="Dock Stick Forever.app"

echo -e "${BLUE}▶︎ Building ${APP_NAME} executable (${BUILD_CONFIG})...${NC}"
case "$BUILD_CONFIG" in
    universal)
        swift build -c release --arch arm64 --arch x86_64 --product "${APP_NAME}"
        # A multi-arch build lands under .build/apple, not .build/release.
        BINARY=".build/apple/Products/Release/${APP_NAME}"
        BUILD_DIR=".build/release"
        ;;
    release)
        swift build -c release --product "${APP_NAME}"
        BINARY=".build/release/${APP_NAME}"
        BUILD_DIR=".build/release"
        ;;
    debug)
        swift build --product "${APP_NAME}"
        BINARY=".build/debug/${APP_NAME}"
        BUILD_DIR=".build/debug"
        ;;
    *)
        echo -e "${YELLOW}Unknown configuration '${BUILD_CONFIG}'. Use: release | universal | debug${NC}"
        exit 1
        ;;
esac
APP_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
echo -e "${GREEN}✓ Build complete${NC}"
echo ""

echo -e "${BLUE}▶︎ Creating app bundle structure...${NC}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BINARY}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Info.plist" "${APP_DIR}/Contents/Info.plist"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "${APP_DIR}/Contents/Info.plist" 2>/dev/null || true
fi

# Ad-hoc signature. Accessibility approval is keyed to the code signature, so
# an unsigned bundle would have to be re-approved on every launch.
echo -e "${BLUE}▶︎ Signing (ad-hoc)...${NC}"
codesign --force --sign - --timestamp=none "${APP_DIR}"

echo -e "${GREEN}✓ App bundle created${NC}"
echo ""

APP_SIZE=$(du -sh "${APP_DIR}" | cut -f1)
ARCHS=$(lipo -archs "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || echo "unknown")
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Successfully built ${BUNDLE_NAME}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Location: ${APP_DIR}"
echo -e "  Size: ${APP_SIZE}"
echo -e "  Architectures: ${ARCHS}"
echo ""
echo -e "${YELLOW}To install:${NC}"
echo -e "  ./install-app.sh"
echo ""
