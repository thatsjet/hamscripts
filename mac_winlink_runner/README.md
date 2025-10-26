# Winlink Runner

A bash script to manage Winlink services with automatic startup, error handling, and graceful shutdown.

## What It Does

This script manages three components needed to run Winlink:

1. **rigctld** - Ham radio rig control. Mine is configured for IC-7300 so modify for your rig.
2. **pat http** - Fire up the [Pat Winlink client](https://getpat.io/) web interface on localhost.
3. **Open in the Browser** - Open the Pat web interface in Google Chrome.

The script starts all services in the background, monitors for errors, and provides a simple stop command to cleanly shut down all services.

## Features

- ✅ Start all Winlink services with one command
- ✅ Automatic error detection and cleanup
- ✅ 2-second delays between commands for proper initialization
- ✅ PID tracking for reliable service management
- ✅ Graceful shutdown of all services
- ✅ Status messages during startup and shutdown
- ✅ Prevents duplicate instances from running

## Installation

1. Copy `winlink_runner.sh` to your home directory (or any location you prefer)
2. Make the script executable:
   ```bash
   chmod +x ~/winlink_runner.sh
3. Add an alias to your `.bashrc` file to make it easy to access like:
    ```bash
    alias winlink="~/winlink_runner.sh"