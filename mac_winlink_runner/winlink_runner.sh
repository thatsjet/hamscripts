#!/bin/bash

# Script to start/stop Winlink services
# Usage: ./start_winlink.sh [start|stop]

PID_FILE="$HOME/.winlink_pids"

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
    # Check if already running
    if [ -f "$PID_FILE" ]; then
        source "$PID_FILE"
        if ([ -n "$RIGCTLD_PID" ] && kill -0 "$RIGCTLD_PID" 2>/dev/null) || \
           ([ -n "$PAT_PID" ] && kill -0 "$PAT_PID" 2>/dev/null); then
            echo "Services appear to be already running. Stop them first with: $0 stop"
            exit 1
        fi
    fi
    
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
    
    # 1. Start rigctld
    echo "[1/3] Starting rigctld..."
    rigctld -m 3073 -r /dev/tty.usbserial-3110 -t 4532 &
    PID1=$!
    PIDS+=($PID1)
    echo "✓ rigctld started (PID: $PID1)"
    sleep 2
    
    # 2. Start pat http
    echo "[2/3] Starting pat http..."
    pat http &
    PID2=$!
    PIDS+=($PID2)
    echo "✓ pat http started (PID: $PID2)"
    sleep 2
    
    # 3. Open Chrome
    echo "[3/3] Opening Google Chrome..."
    open -a "Google Chrome" http://localhost:8080
    echo "✓ Chrome opened"
    
    # Save PIDs to file
    cat > "$PID_FILE" << EOF
RIGCTLD_PID=$PID1
PAT_PID=$PID2
EOF
    
    echo ""
    echo "All services started successfully!"
    echo "rigctld PID: $PID1"
    echo "pat http PID: $PID2"
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
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac
