#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Dientempo"
BUILD_DIR="$PROJECT_DIR/build/screenshots"
SCREENSHOTS_DIR="$PROJECT_DIR/app-store/1.0/screenshots"

# Device UUIDs
IPHONE_UUID="C3CCA346-B895-4C12-A793-5091C999DC95"  # iPhone 17 Pro Max
IPAD_UUID="1A890E4C-599E-4F19-A1B4-6CCC7B7D97B8"     # iPad Pro 13-inch (M5)

echo "=== Dientempo Screenshot Tool ==="
echo ""

mkdir -p "$BUILD_DIR" "$SCREENSHOTS_DIR"

# Build for iPhone
echo "1. Building for iPhone..."
xcodebuild -project "$PROJECT_DIR/Dientempo.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "id=$IPHONE_UUID" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/iphone" \
    build 2>&1 | tail -5

# Boot iPhone if needed
echo "2. Booting iPhone simulator..."
xcrun simctl boot "$IPHONE_UUID" 2>/dev/null || true
sleep 3

# Install and launch on iPhone
echo "3. Installing app on iPhone..."
APP_PATH=$(find "$BUILD_DIR/iphone" -name "Dientempo.app" -path "*/Release-iphonesimulator/*" | head -1)
if [ -z "$APP_PATH" ]; then
    APP_PATH=$(find "$BUILD_DIR/iphone" -name "Dientempo.app" | head -1)
fi
xcrun simctl install "$IPHONE_UUID" "$APP_PATH"
xcrun simctl launch "$IPHONE_UUID" com.bystruev.dientempo
sleep 4

# Take iPhone screenshots
echo "4. Taking iPhone screenshots..."
xcrun simctl io "$IPHONE_UUID" screenshot "$SCREENSHOTS_DIR/iphone-counting.png"
echo "   Saved: iphone-counting.png"

# Build for iPad
echo ""
echo "5. Building for iPad..."
xcodebuild -project "$PROJECT_DIR/Dientempo.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "id=$IPAD_UUID" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/ipad" \
    build 2>&1 | tail -5

# Boot iPad if needed
echo "6. Booting iPad simulator..."
xcrun simctl boot "$IPAD_UUID" 2>/dev/null || true
sleep 3

# Install and launch on iPad
echo "7. Installing app on iPad..."
APP_PATH=$(find "$BUILD_DIR/ipad" -name "Dientempo.app" -path "*/Release-iphonesimulator/*" | head -1)
if [ -z "$APP_PATH" ]; then
    APP_PATH=$(find "$BUILD_DIR/ipad" -name "Dientempo.app" | head -1)
fi
xcrun simctl install "$IPAD_UUID" "$APP_PATH"
xcrun simctl launch "$IPAD_UUID" com.bystruev.dientempo
sleep 4

# Take iPad screenshot
echo "8. Taking iPad screenshot..."
xcrun simctl io "$IPAD_UUID" screenshot "$SCREENSHOTS_DIR/ipad-counting.png"
echo "   Saved: ipad-counting.png"

echo ""
echo "=== Screenshots saved to $SCREENSHOTS_DIR ==="
ls -la "$SCREENSHOTS_DIR"
