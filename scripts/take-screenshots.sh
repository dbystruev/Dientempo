#!/usr/bin/env bash
set -e

# Resolve script location (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0")")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="Dientempo"
BUILD_DIR="$PROJECT_DIR/build/screenshots"
SCREENSHOTS_DIR="$PROJECT_DIR/screenshots"

# Device UUIDs
IPHONE_UUID="C3CCA346-B895-4C12-A793-5091C999DC95"  # iPhone 17 Pro Max

# Screenshot definitions: number|name|description|launch_number
# launch_number: the number to show (0 = warmup/ready state, >0 = counting at that number)
SCREENSHOTS=(
    "1|warmup|Warm-up screen (Calentando... button)|warmup"
    "2|ready|Ready to count (0 / cero, Vamos button)|0"
    "3|counting|Counting in progress (shows number 42)|42"
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
  3  Counting in progress (shows number 42 / cuarenta y dos)

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
        IFS='|' read -r num name desc launch_number <<< "$entry"
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
                        IFS='|' read -r num name desc launch_number <<< "$entry"
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
    local launch_number="$2"

    if [[ "$launch_number" == "warmup" ]]; then
        # Launch without arguments to show warmup state
        xcrun simctl launch "$uuid" com.bystruev.dientempo
    else
        # Launch with screenshot argument
        xcrun simctl launch "$uuid" com.bystruev.dientempo "--screenshot=$launch_number"
    fi
}

take_screenshot() {
    local uuid="$1"
    local filename="$2"
    local device_label="$3"

    xcrun simctl io "$uuid" screenshot "$SCREENSHOTS_DIR/${device_label}-${filename}.png"
    echo "   Saved: ${device_label}-${filename}.png"
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
        IFS='|' read -r num name desc launch_number <<< "$entry"

        echo "Taking screenshot $num: $desc"

        # Terminate any existing instance
        xcrun simctl terminate "$uuid" com.bystruev.dientempo 2>/dev/null || true
        sleep 1

        # Launch app with appropriate arguments
        launch_app "$uuid" "$launch_number"

        # Wait for app to load
        sleep 3

        take_screenshot "$uuid" "$name" "$label"
        echo ""
    done
}

# Main
parse_args "$@"

if [[ "$BUILD_ONLY" == true ]]; then
    build_app "$IPHONE_UUID" "iphone"
    echo "Build complete."
    exit 0
fi

mkdir -p "$SCREENSHOTS_DIR"

echo "=== Dientempo Screenshot Tool ==="
echo ""
echo "Screenshots to take: ${#SELECTED[@]}"
for entry in "${SELECTED[@]}"; do
    IFS='|' read -r num name desc launch_number <<< "$entry"
    echo "  $num. $desc"
done
echo ""

take_device_screenshots "$IPHONE_UUID" "iphone" "${SELECTED[@]}"

echo ""
echo "=== Screenshots saved to $SCREENSHOTS_DIR ==="
ls -la "$SCREENSHOTS_DIR"
