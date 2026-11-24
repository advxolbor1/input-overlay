#!/bin/bash
# Builds Input Overlay into dist/"Input Overlay.app"
#
# Usage:
#   ./build_app.sh                build only
#   ./build_app.sh --run          build, then launch
#   ./build_app.sh --install      build, copy to /Applications, then launch
#
# Optional: CODESIGN_ID="My Certificate Name" ./build_app.sh --install
#   (a stable signing identity stops macOS from forgetting the Input Monitoring
#    permission every time you rebuild; see README)
set -euo pipefail
cd "$(dirname "$0")"

EXEC_NAME="InputOverlay"
APP_NAME="Input Overlay.app"
APP="dist/${APP_NAME}"
SIGN_ID="${CODESIGN_ID:--}"

RUN=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --run) RUN=1 ;;
        --install) INSTALL=1; RUN=1 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXEC_NAME" "$APP/Contents/MacOS/$EXEC_NAME"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -f AppIcon.icns ]]; then
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign "$SIGN_ID" "$APP"
echo "Built $APP"

TARGET="$APP"
if [[ $INSTALL -eq 1 ]]; then
    pkill -x "$EXEC_NAME" 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/${APP_NAME}"
    cp -R "$APP" "/Applications/${APP_NAME}"
    TARGET="/Applications/${APP_NAME}"
    echo "Installed to $TARGET"
fi

if [[ $RUN -eq 1 ]]; then
    pkill -x "$EXEC_NAME" 2>/dev/null || true
    sleep 0.5
    open "$TARGET"
fi
