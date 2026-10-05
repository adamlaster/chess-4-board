#!/usr/bin/env bash
# ==============================================================================
# Chess 4 Board - Build and Deploy Pipeline
# ==============================================================================
# Usage:
#   ./build_and_deploy.sh            # Complete build (AAR + APK) & deploy
#   ./build_and_deploy.sh --skip-aar # Skip AAR compilation (Godot/assets only)
#   ./build_and_deploy.sh --no-deploy # Build APK without deploying to device
# ==============================================================================

set -euo pipefail

# Color formatting
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Base Directories (resolved relative to this script so it works from any checkout)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHESS_DIR="$SCRIPT_DIR"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../godot-webview/GodotWebView" && pwd)"
AAR_OUT_DIR="$PLUGIN_DIR/GodotWebView/build/outputs/aar"
TARGET_ADDONS_DIR="$CHESS_DIR/addons/webview"
OUTPUT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/output"
APK_PATH="$OUTPUT_DIR/Chess4Board.apk"

# Tool Paths and Fallbacks
if [[ -z "${JAVA_HOME:-}" ]]; then
    if [[ -d "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" ]]; then
        export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    elif [[ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
        export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    fi
fi

if [[ -z "${ANDROID_HOME:-}" ]]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
fi

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$HOME/.local/bin:$PATH"

GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
if ! command -v "$GODOT_BIN" &>/dev/null && command -v godot &>/dev/null; then
    GODOT_BIN="$(command -v godot)"
fi

# Options
BUILD_AAR=true
DEPLOY=true

for arg in "$@"; do
    case "$arg" in
        --skip-aar)
            BUILD_AAR=false
            ;;
        --no-deploy|--skip-deploy|-b)
            DEPLOY=false
            ;;
        -h|--help)
            echo -e "${BOLD}Chess 4 Board - Build and Deploy Script${NC}"
            echo "Usage: ./build_and_deploy.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-aar     Skip compiling GodotWebView Android library (AAR)"
            echo "  --no-deploy    Build the APK without installing to the Board device"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo -e "${YELLOW}Warning: Unknown option '$arg'${NC}"
            ;;
    esac
done

echo -e "\n${BOLD}${CYAN}=== Starting Chess 4 Board Pipeline ===${NC}\n"

# ------------------------------------------------------------------------------
# STEP 1: Build Android WebView Plugin (AAR)
# ------------------------------------------------------------------------------
if [[ "$BUILD_AAR" = true ]]; then
    echo -e "${BOLD}${GREEN}[Step 1/4] Building Android WebView Plugin (AAR)...${NC}"
    cd "$PLUGIN_DIR"
    ./gradlew --no-build-cache clean assemble
    echo -e "${GREEN}✓ AAR build complete.${NC}\n"
else
    echo -e "${YELLOW}[Step 1/4] Skipping AAR build (--skip-aar selected).${NC}\n"
fi

# ------------------------------------------------------------------------------
# STEP 2: Copy AARs to chess-4-board
# ------------------------------------------------------------------------------
if [[ "$BUILD_AAR" = true ]]; then
    echo -e "${BOLD}${GREEN}[Step 2/4] Copying AARs to Chess 4 Board project...${NC}"
    mkdir -p "$TARGET_ADDONS_DIR"
    cp -v "$AAR_OUT_DIR/GodotWebView-debug.aar" "$TARGET_ADDONS_DIR/"
    cp -v "$AAR_OUT_DIR/GodotWebView-release.aar" "$TARGET_ADDONS_DIR/"
    echo -e "${GREEN}✓ Plugin AARs copied.${NC}\n"
else
    echo -e "${YELLOW}[Step 2/4] Skipping AAR copy (--skip-aar selected).${NC}\n"
fi

# ------------------------------------------------------------------------------
# STEP 3: Export Android APK via Godot CLI
# ------------------------------------------------------------------------------
echo -e "${BOLD}${GREEN}[Step 3/4] Exporting Chess4Board.apk with Godot...${NC}"
mkdir -p "$OUTPUT_DIR"
cd "$CHESS_DIR"
"$GODOT_BIN" --headless --path "$CHESS_DIR" --export-debug "Android" "$APK_PATH"
echo -e "${GREEN}✓ APK exported: $APK_PATH ($(du -h "$APK_PATH" | cut -f1))${NC}\n"

# ------------------------------------------------------------------------------
# STEP 4: Install and Launch APK on Board Device
# ------------------------------------------------------------------------------
if [[ "$DEPLOY" = true ]]; then
    echo -e "${BOLD}${GREEN}[Step 4/4] Deploying to Board device...${NC}"
    cd "$OUTPUT_DIR"
    board-connect install "$APK_PATH" --launch
    echo -e "\n${BOLD}${GREEN}=== Deployment Complete & Launched! ===${NC}\n"
else
    echo -e "${YELLOW}[Step 4/4] Skipping deployment (--no-deploy selected).${NC}\n"
    echo -e "${BOLD}${GREEN}=== Build Successful! ===${NC}\n"
fi
