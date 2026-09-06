#!/usr/bin/env bash
set -e

# Resolve script location (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0")")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="Dientempo"
BUILD_DIR="$PROJECT_DIR/build/screenshots"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"
BUNDLE_ID="com.bystruev.dientempo"

# Screenshot definitions: number|name|description|launch_args
SCREENSHOTS=(
    "1|warmup|Warm-up screen (Calentando... button)|--screenshot=warmup"
    "2|ready|Ready to count (0 / cero, Vamos button)|--screenshot=0"
    "3|counting|Counting in progress (Alto button, number 42)|--screenshot=42 --screenshot-running"
    "4|voice|Voice settings (Voz picker)|--screenshot=voice"
    "5|locked|Daily-limit lock screen with Unlimited Access purchase button|--screenshot=locked"
)

show_help() {
    cat << 'HELP'
Dientempo Screenshot Tool

Usage: take-screenshots.sh [OPTIONS] [SCREENSHOTS]

Take screenshots of the Dientempo app for App Store submission.
Screenshots are saved to the screenshots/ directory (gitignored).

Options:
  -h, --help       Show this help message
  -l, --list       List all available screenshots
  -b, --build      Build only, don't take screenshots

Screenshots:
  1  Warm-up screen (Calentando... button, grayed out)
  2  Ready to count (0 / cero, Vamos button)
  3  Counting in progress (Alto button, number 42)
  4  Voice settings (Voz picker)
  5  Daily-limit lock screen (Unlimited Access purchase button) -- also the
     one to submit as the review screenshot for the com.bystruev.dientempo.premium
     In-App Purchase

Examples:
  take-screenshots.sh 1 2      # Take screenshots 1 and 2
  take-screenshots.sh 3        # Take screenshot 3 only
  take-screenshots.sh all      # Take all screenshots
  take-screenshots.sh          # Take all screenshots
HELP
}

list_screenshots() {
    echo "Available screenshots:"
    echo ""
    for entry in "${SCREENSHOTS[@]}"; do
        IFS='|' read -r num name desc launch_args <<< "$entry"
        echo "  $num  $name  $desc"
    done
}

parse_args() {
    SELECTED=()
    BUILD_ONLY=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_screenshots
                exit 0
                ;;
            -b|--build)
                BUILD_ONLY=true
                shift
                ;;
            all)
                SELECTED=("${SCREENSHOTS[@]}")
                shift
                ;;
            *)
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    for entry in "${SCREENSHOTS[@]}"; do
                        IFS='|' read -r num name desc launch_args <<< "$entry"
                        if [[ "$num" == "$1" ]]; then
                            SELECTED+=("$entry")
                        fi
                    done
                fi
                shift
                ;;
        esac
    done

    if [[ ${#SELECTED[@]} -eq 0 && "$BUILD_ONLY" == false ]]; then
        SELECTED=("${SCREENSHOTS[@]}")
    fi
}

find_simulator() {
    local device_name_pattern="$1"
    xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if '$device_name_pattern' in d['name'] and d['isAvailable']:
            print(d['udid'])
            sys.exit(0)
print('')
" 2>/dev/null || echo ""
}

build_app() {
    local dest_uuid="$1"
    local label="$2"

    echo "Building for $label..."
    xcodebuild -project "$PROJECT_DIR/Dientempo.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "id=$dest_uuid" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/$label" \
        build 2>&1 | tail -3
    echo ""
}

boot_simulator() {
    local uuid="$1"
    local label="$2"

    echo "Booting $label simulator..."
    xcrun simctl boot "$uuid" 2>/dev/null || true
    sleep 2
}

install_app() {
    local uuid="$1"
    local label="$2"

    echo "Installing app on $label..."
    local app_path
    app_path=$(find "$BUILD_DIR/$label" -name "Dientempo.app" -path "*/Release-iphonesimulator/*" | head -1)
    if [[ -z "$app_path" ]]; then
        app_path=$(find "$BUILD_DIR/$label" -name "Dientempo.app" | head -1)
    fi
    xcrun simctl install "$uuid" "$app_path"
}

launch_app() {
    local uuid="$1"
    local launch_args="$2"

    local cmd="xcrun simctl launch $uuid $BUNDLE_ID"
    for arg in $launch_args; do
        cmd="$cmd $arg"
    done
    eval "$cmd"
}

take_screenshot() {
    local uuid="$1"
    local num="$2"
    local filename="$3"
    local device_label="$4"

    local prefix=$(printf "%02d" "$num")
    xcrun simctl io "$uuid" screenshot "$SCREENSHOTS_DIR/${prefix}_${device_label}-${filename}.png"
    echo "   Saved: ${prefix}_${device_label}-${filename}.png"
}

take_device_screenshots() {
    local uuid="$1"
    local label="$2"
    shift 2
    local selected=("$@")

    echo "=== $label Screenshots ==="
    echo ""

    build_app "$uuid" "$label"
    boot_simulator "$uuid" "$label"
    install_app "$uuid" "$label"

    for entry in "${selected[@]}"; do
        IFS='|' read -r num name desc launch_args <<< "$entry"

        echo "Taking screenshot $num: $desc"

        # Terminate any existing instance
        xcrun simctl terminate "$uuid" "$BUNDLE_ID" 2>/dev/null || true
        sleep 1

        # Launch app with appropriate arguments
        launch_app "$uuid" "$launch_args"

        # Wait for app to load
        sleep 3

        take_screenshot "$uuid" "$num" "$name" "$label"
        echo ""
    done
}

# Main
parse_args "$@"

# Find simulators dynamically
IPHONE_UUID=$(find_simulator "iPhone 17 Pro Max")
IPAD_UUID=$(find_simulator "iPad Pro 13-inch")

if [[ -z "$IPHONE_UUID" ]]; then
    echo "Error: iPhone 17 Pro Max simulator not found"
    exit 1
fi

if [[ -z "$IPAD_UUID" ]]; then
    echo "Error: iPad Pro 13-inch (M5) simulator not found"
    exit 1
fi

echo "Using iPhone: $IPHONE_UUID"
echo "Using iPad: $IPAD_UUID"
echo ""

if [[ "$BUILD_ONLY" == true ]]; then
    build_app "$IPHONE_UUID" "iphone"
    build_app "$IPAD_UUID" "ipad"
    echo "Build complete."
    exit 0
fi

mkdir -p "$SCREENSHOTS_DIR"

echo "=== Dientempo Screenshot Tool ==="
echo ""
echo "Screenshots to take: ${#SELECTED[@]}"
for entry in "${SELECTED[@]}"; do
    IFS='|' read -r num name desc launch_args <<< "$entry"
    echo "  $num. $desc"
done
echo ""

take_device_screenshots "$IPHONE_UUID" "iphone" "${SELECTED[@]}"
take_device_screenshots "$IPAD_UUID" "ipad" "${SELECTED[@]}"

echo ""
echo "=== Screenshots saved to $SCREENSHOTS_DIR ==="
ls -la "$SCREENSHOTS_DIR"
