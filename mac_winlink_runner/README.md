# Winlink Runner

A bash script to manage Winlink services with automatic startup, error handling, and graceful shutdown.

# Winlink Runner

A bash script to start/stop a Winlink stack on macOS with basic error handling and a single `stop` command.

## What It Does

This script manages the components needed to run Winlink:

1. **rigctld** - Ham radio rig control (Hamlib). This repo’s defaults are configured for an IC-7300; update for your rig/serial device.
2. **VaraHF modem** - Starts VARA HF modem via `wine --cx-app vara.exe`.
3. **pat http** - Starts the [Pat Winlink client](https://getpat.io/) web interface on localhost.
4. **Open in the Browser** - Opens the Pat web UI in Google Chrome.

The script starts services in the background, writes their PIDs to `~/.winlink_pids`, and uses that file to stop them later.

## Features

- ✅ One-command start/stop
- ✅ PID tracking for reliable shutdown
- ✅ 2-second delays between commands for initialization
- ✅ Prevents duplicate instances from running

## Usage

Start:

```bash
./winlink_runner.sh start
```

When you run `start`, the script first reminds you to ensure the radio is powered on and ready to connect. Answer `y`/`yes` to continue; any other response aborts without starting anything.

Stop:

```bash
./winlink_runner.sh stop
```

`stop` terminates `rigctld`, VaraHF, and `pat http` using the PIDs saved in `~/.winlink_pids`.

Validate config (does not start anything):

```bash
./winlink_runner.sh check
```

`check` also verifies required commands are available (`rigctld`, `pat`, `wine`), that your configured serial device exists, and (if set) that your `BROWSER_APP` is installed.

## Configuration (Required)

This runner is intentionally configurable per user/machine.

- Your local config file is: `mac_winlink_runner/winlink_runner.conf`
- It is **gitignored** (won't be committed).
- A checked-in template is provided at: `mac_winlink_runner/winlink_runner.conf.template`

Create your config:

```bash
cd mac_winlink_runner
cp winlink_runner.conf.template winlink_runner.conf
```

Then edit `winlink_runner.conf` and set at least:

- `CALLSIGN`
- `HAMLIB_MODEL` (the Hamlib rig model number)
- `RIG_SERIAL_PORT` (your radio's serial device)
- `VARA_CX_APP` (CrossOver app name) **or** `VARA_EXE_PATH` (full path to `VARA.exe`)

### Finding your Hamlib rig model

- Wiki list: https://github.com/Hamlib/Hamlib/wiki/Supported-Radios
- Or locally (recommended):
   ```bash
   rigctl -l | less
   ```

### Finding your serial port on macOS

```bash
ls /dev/tty.*
```

## First run behavior

If you run `./winlink_runner.sh start` and no config exists, the script prints setup instructions and exits.

## Installation

1. Make the script executable:
   ```bash
   chmod +x winlink_runner.sh
   ```
2. (Optional) Add an alias to your shell config (for example `~/.zshrc` or `~/.bashrc`):
   ```bash
   alias winlink="/full/path/to/winlink_runner.sh"
   ```