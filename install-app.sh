#!/bin/bash

# Dock Stick Forever Installer
# Installs the built .app to ~/Applications

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

BUNDLE_NAME="Dock Stick Forever.app"
SOURCE_PATH=".build/release/${BUNDLE_NAME}"
DEST_DIR="${HOME}/Applications"
DEST_PATH="${DEST_DIR}/${BUNDLE_NAME}"

if [ ! -d "${SOURCE_PATH}" ]; then
    echo -e "${RED}Error: ${BUNDLE_NAME} not found at ${SOURCE_PATH}${NC}"
    echo -e "${YELLOW}Run ./build-app.sh first${NC}"
    exit 1
fi

mkdir -p "${DEST_DIR}"

if [ -d "${DEST_PATH}" ]; then
    echo -e "${YELLOW}⚠ Dock Stick Forever is already installed${NC}"
    read -p "Replace it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Installation cancelled${NC}"
        exit 0
    fi
    # Quit the running copy first, or the replaced binary keeps the old tap.
    osascript -e 'quit app "Dock Stick Forever"' 2>/dev/null || true
    sleep 1
    rm -rf "${DEST_PATH}"
fi

echo -e "${BLUE}▶︎ Installing to ${DEST_DIR}...${NC}"
cp -R "${SOURCE_PATH}" "${DEST_PATH}"

echo -e "${GREEN}✓ Installed${NC}"
echo ""
echo -e "${YELLOW}First launch will ask for Accessibility access.${NC}"
echo -e "  open \"${DEST_PATH}\""
echo ""
