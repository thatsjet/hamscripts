#!/bin/bash

# Script to start/stop Winlink services
# Usage: ./start_winlink.sh [start|stop]

PID_FILE="$HOME/.winlink_pids"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${WINLINK_RUNNER_CONFIG:-$SCRIPT_DIR/winlink_runner.conf}"

die() {
    echo "Error: $*" >&2
    exit 1
}

require_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: '$cmd' (ensure it is installed and on your PATH)"
}

require_macos_app() {
    local app_name="$1"
    if ! open -Ra "$app_name" >/dev/null 2>&1; then
        die "macOS app not found: '$app_name' (set BROWSER_APP to an installed app, or leave it empty to use your default browser)"
    fi
}

print_first_run_instructions() {
    echo ""
    echo "Winlink Runner is not configured yet."
    echo ""
    echo "1) Create your config from the template:"
    echo "   cd \"$SCRIPT_DIR\""
    echo "   cp winlink_runner.conf.template winlink_runner.conf"
    echo ""
    echo "2) Edit winlink_runner.conf and set at least:"
    echo "   - CALLSIGN"
    echo "   - HAMLIB_MODEL (Hamlib rig model number)"
    echo "   - RIG_SERIAL_PORT (e.g. /dev/tty.usbserial-*)"
    echo "   - VARA_CX_APP (CrossOver app name) OR VARA_EXE_PATH (full path to VARA.exe)"
    echo ""
    echo "Hamlib model tips:"
    echo "   - Wiki list: https://github.com/Hamlib/Hamlib/wiki/Supported-Radios"
    echo "   - Or locally: rigctl -l | less"
    echo ""
    echo "macOS serial port tip:"
    echo "   ls /dev/tty.*"
    echo ""
    echo "Then rerun: $0 start"
    echo ""
}

require_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_first_run_instructions
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    if [ -z "${CALLSIGN:-}" ]; then
        echo "Config error: CALLSIGN is not set in $CONFIG_FILE"
        exit 1
    fi

    if [ -z "${HAMLIB_MODEL:-}" ]; then
        echo "Config error: HAMLIB_MODEL is not set in $CONFIG_FILE"
        exit 1
    fi
    if ! [[ "${HAMLIB_MODEL}" =~ ^[0-9]+$ ]]; then
        echo "Config error: HAMLIB_MODEL must be a number (got: ${HAMLIB_MODEL})"
        exit 1
    fi

    if [ -z "${RIG_SERIAL_PORT:-}" ]; then
        echo "Config error: RIG_SERIAL_PORT is not set in $CONFIG_FILE"
        exit 1
    fi

    if [ -z "${RIGCTLD_PORT:-}" ]; then
        RIGCTLD_PORT=4532
    fi
    if ! [[ "${RIGCTLD_PORT}" =~ ^[0-9]+$ ]]; then
        echo "Config error: RIGCTLD_PORT must be a number (got: ${RIGCTLD_PORT})"
        exit 1
    fi

    if [ -z "${VARA_CX_APP:-}" ] && [ -z "${VARA_EXE_PATH:-}" ]; then
        echo "Config error: Set VARA_CX_APP (CrossOver) or VARA_EXE_PATH (Wine path) in $CONFIG_FILE"
        exit 1
    fi

    if [ -z "${PAT_HTTP_URL:-}" ]; then
        PAT_HTTP_URL="http://localhost:8080"
    fi
}

require_dependencies() {
    require_command rigctld
    require_command pat
    require_command wine

    if [ ! -e "$RIG_SERIAL_PORT" ]; then
        die "RIG_SERIAL_PORT does not exist: $RIG_SERIAL_PORT (tip: ls /dev/tty.*)"
    fi

    if [ -n "${VARA_EXE_PATH:-}" ]; then
        if [ ! -f "$VARA_EXE_PATH" ]; then
            die "VARA_EXE_PATH is set but file not found: $VARA_EXE_PATH"
        fi
    fi

    if [ -n "${BROWSER_APP:-}" ]; then
        require_macos_app "$BROWSER_APP"
    fi
}

check_config() {
    require_config
    require_dependencies

    echo "Config OK"
    echo "  Config file: $CONFIG_FILE"
    echo "  CALLSIGN: ${CALLSIGN}"
    echo "  HAMLIB_MODEL: ${HAMLIB_MODEL}"
    echo "  RIG_SERIAL_PORT: ${RIG_SERIAL_PORT}"
    echo "  RIGCTLD_PORT: ${RIGCTLD_PORT}"
    if [ -n "${VARA_CX_APP:-}" ]; then
        echo "  VARA launch: wine --cx-app ${VARA_CX_APP}"
    else
        echo "  VARA launch: wine ${VARA_EXE_PATH}"
    fi
    echo "  PAT_HTTP_URL: ${PAT_HTTP_URL}"
    if [ -n "${BROWSER_APP:-}" ]; then
        echo "  BROWSER_APP: ${BROWSER_APP}"
    fi
}

# Function to stop services
stop_services() {
    if [ ! -f "$PID_FILE" ]; then
        echo "No PID file found. Services may not be running."
        exit 0
    fi
    
    echo "Stopping Winlink services..."
    
    # Read PIDs from file
    source "$PID_FILE"
    
    STOPPED=0
    
    # Stop rigctld
    if [ -n "$RIGCTLD_PID" ] && kill -0 "$RIGCTLD_PID" 2>/dev/null; then
        echo "Stopping rigctld (PID: $RIGCTLD_PID)..."
        kill "$RIGCTLD_PID" 2>/dev/null && echo "✓ rigctld stopped" || echo "✗ Failed to stop rigctld"
        STOPPED=1
    else
        echo "rigctld not running"
    fi

    # Stop VaraHF modem
    if [ -n "$VARA_PID" ] && kill -0 "$VARA_PID" 2>/dev/null; then
        echo "Stopping VaraHF (PID: $VARA_PID)..."
        kill "$VARA_PID" 2>/dev/null && echo "✓ VaraHF stopped" || echo "✗ Failed to stop VaraHF"
        STOPPED=1
    else
        echo "VaraHF not running"
    fi
    
    # Stop pat http
    if [ -n "$PAT_PID" ] && kill -0 "$PAT_PID" 2>/dev/null; then
        echo "Stopping pat http (PID: $PAT_PID)..."
        kill "$PAT_PID" 2>/dev/null && echo "✓ pat http stopped" || echo "✗ Failed to stop pat http"
        STOPPED=1
    else
        echo "pat http not running"
    fi
    
    # Remove PID file
    rm -f "$PID_FILE"
    
    if [ $STOPPED -eq 1 ]; then
        echo "Services stopped successfully!"
    fi
    
    exit 0
}

# Function to start services
start_services() {
    require_config
    require_dependencies

    # Check if already running
    if [ -f "$PID_FILE" ]; then
        source "$PID_FILE"
        if ([ -n "$RIGCTLD_PID" ] && kill -0 "$RIGCTLD_PID" 2>/dev/null) || \
           ([ -n "$VARA_PID" ] && kill -0 "$VARA_PID" 2>/dev/null) || \
           ([ -n "$PAT_PID" ] && kill -0 "$PAT_PID" 2>/dev/null); then
            echo "Services appear to be already running. Stop them first with: $0 stop"
            exit 1
        fi
    fi

    echo "Before starting: ensure your radio is turned on and ready to connect."
    read -r -p "Is the radio on and ready? [y/N]: " RADIO_READY
    case "$RADIO_READY" in
        [yY]|[yY][eE][sS])
            ;;
        *)
            echo "Aborting. Turn on the radio and run: $0 start"
            exit 0
            ;;
    esac
    
    set -e  # Exit on error
    
    # Array to track background PIDs
    declare -a PIDS=()
    
    # Cleanup function to kill all started processes
    cleanup() {
        echo "Error detected. Cleaning up processes..."
        for pid in "${PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "Killing process $pid"
                kill "$pid" 2>/dev/null || true
            fi
        done
        rm -f "$PID_FILE"
        exit 1
    }
    
    # Set trap to cleanup on error
    trap cleanup ERR
    
    echo "Starting Winlink services..."
    echo "Using callsign: ${CALLSIGN}"
    
    # 1. Start rigctld
    echo "[1/4] Starting rigctld..."
    rigctld -m "$HAMLIB_MODEL" -r "$RIG_SERIAL_PORT" -t "$RIGCTLD_PORT" &
    PID1=$!
    PIDS+=($PID1)
    echo "✓ rigctld started (PID: $PID1)"
    sleep 2
    
    # 2. Start VaraHF modem
    echo "[2/4] Starting VaraHF modem (vara.exe)..."
    if [ -n "${VARA_CX_APP:-}" ]; then
        wine --cx-app "$VARA_CX_APP" &
    else
        wine "$VARA_EXE_PATH" &
    fi
    PID2=$!
    PIDS+=($PID2)
    echo "✓ VaraHF started (PID: $PID2)"
    sleep 2

    # 3. Start pat http
    echo "[3/4] Starting pat http..."
    pat http &
    PID3=$!
    PIDS+=($PID3)
    echo "✓ pat http started (PID: $PID3)"
    sleep 2
    
    # 4. Open Chrome
    echo "[4/4] Opening Google Chrome..."
    if [ -n "${BROWSER_APP:-}" ]; then
        open -a "$BROWSER_APP" "$PAT_HTTP_URL" 2>/dev/null || open "$PAT_HTTP_URL"
    else
        open "$PAT_HTTP_URL"
    fi
    echo "✓ Browser opened"
    
    # Save PIDs to file
    cat > "$PID_FILE" << EOF
RIGCTLD_PID=$PID1
VARA_PID=$PID2
PAT_PID=$PID3
EOF
    
    echo ""
    echo "All services started successfully!"
    echo "rigctld PID: $PID1"
    echo "VaraHF PID: $PID2"
    echo "pat http PID: $PID3"
    echo ""
    echo "To stop services, run: $0 stop"
    
    # Exit successfully, leaving processes running
    exit 0
}

# Main script logic
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    check|validate)
        check_config
        ;;
    *)
        echo "Usage: $0 {start|stop|check}"
        exit 1
        ;;
esac
