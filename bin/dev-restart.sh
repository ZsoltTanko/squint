#!/usr/bin/env bash
# Kill, rebuild, re-register with Launch Services, relaunch.
# The standard development iteration loop for Squint.
# See docs/DEVELOPMENT.md for context.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="Squint.xcodeproj"
SCHEME="Squint"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/Build/Products/Debug/Squint.app"

# Regenerate the Xcode project if project.yml is newer than the .xcodeproj
if [[ ! -d "$PROJECT" ]] || [[ "project.yml" -nt "$PROJECT" ]]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "error: xcodegen not installed (brew install xcodegen)" >&2
        exit 1
    fi
    echo "==> Regenerating $PROJECT from project.yml"
    xcodegen generate
fi

echo "==> Killing any running Squint"
killall Squint 2>/dev/null || true

echo "==> Building"
set +e
BUILD_OUTPUT="$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1)"
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -ne 0 ]]; then
    echo "$BUILD_OUTPUT" | grep -E " error: |warning: " | head -40
    echo "==> Build FAILED (exit $BUILD_STATUS)" >&2
    exit $BUILD_STATUS
fi

echo "==> Build succeeded"

echo "==> Re-registering with Launch Services (refreshes Services menu)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -f "$REPO_ROOT/$APP_PATH"
/System/Library/CoreServices/pbs -update

echo "==> Launching $APP_PATH"
open "$REPO_ROOT/$APP_PATH"

sleep 1
if pgrep -x Squint >/dev/null; then
    echo "==> Running (pid $(pgrep -x Squint))"
else
    echo "==> Warning: app launched but no process found. Check Console.app for crash logs." >&2
fi
