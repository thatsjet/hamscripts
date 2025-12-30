#!/usr/bin/env bash
set -euo pipefail

POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-1}"
LOG_FILE="${LOG_FILE:-}"

# Optional: exclude certain devices from the *startup baseline*.
# Useful when you start the script with something already connected, but you still
# want it to be reported as "USB attached" when it appears.
#
# Examples:
#   BASELINE_EXCLUDE_VIDPID="10C4:EA60,08BB:2901"
#   BASELINE_EXCLUDE_REGEX='IC-7300|Icom'
BASELINE_EXCLUDE_VIDPID="${BASELINE_EXCLUDE_VIDPID:-}"
BASELINE_EXCLUDE_REGEX="${BASELINE_EXCLUDE_REGEX:-}"

# Allowlist is optional.
# If you leave it empty (default), *all* newly attached devices will be reported.
# If you set it, only matching devices will be reported and/or can trigger actions.
#
# Add exact VID:PID allowlist entries here (hex, uppercase or lowercase both OK).
# Example common patterns (commented):
#   ALLOW_VIDPID=("10C4:EA60" "0403:6001" "067B:2303" "1A86:7523")
ALLOW_VIDPID=(
)

# Optional regex (extended) matched against: product/vendor/serial/nodeName.
# Example: ALLOW_NAME_REGEX='IC-7300|Icom|Yaesu|Kenwood|Elecraft'
ALLOW_NAME_REGEX="${ALLOW_NAME_REGEX:-}"

# Command to run when an allowlisted device is inserted.
# It runs in the background with these env vars set:
#   USB_LOCATION_ID_DEC, USB_LOCATION_ID_HEX, USB_VIDPID, USB_PRODUCT, USB_VENDOR, USB_SERIAL, USB_NODE
LAUNCH_CMD="${LAUNCH_CMD:-}"

# If 1, prints what it would do but does not execute LAUNCH_CMD.
DRY_RUN="${DRY_RUN:-0}"

usage() {
	cat <<'EOF'
Usage: ./usbdetect.sh [--once]

Polls macOS IORegistry to detect USB insert/remove events and prints which port
(via locationID). Only allowlisted devices trigger LAUNCH_CMD.

Env vars:
	POLL_INTERVAL_SECONDS=1
	BASELINE_EXCLUDE_VIDPID='VID:PID,VID:PID'
	BASELINE_EXCLUDE_REGEX='...'
	ALLOW_NAME_REGEX='...'
	DRY_RUN=1
	LAUNCH_CMD='open -a MyApp'   (or any shell command)
	LOG_FILE=/path/to/log.txt
EOF
}

log() {
	local msg="$1"
	local line
	line="$(date '+%Y-%m-%d %H:%M:%S') ${msg}"
	echo "$line"
	if [[ -n "$LOG_FILE" ]]; then
		printf '%s\n' "$line" >> "$LOG_FILE"
	fi
}

normalize_vidpid() {
	# Accepts hex like 10c4:ea60 and returns uppercase.
	tr '[:lower:]' '[:upper:]'
}

device_matches_allowlist() {
	local vidpid="$1" product="$2" vendor="$3" serial="$4" node="$5"

	vidpid="$(printf '%s' "$vidpid" | normalize_vidpid)"

	# If no allowlist is configured, everything matches.
	if ((${#ALLOW_VIDPID[@]} == 0)) && [[ -z "$ALLOW_NAME_REGEX" ]]; then
		return 0
	fi

	if ((${#ALLOW_VIDPID[@]} > 0)); then
		local allowed
		for allowed in "${ALLOW_VIDPID[@]}"; do
			allowed="$(printf '%s' "$allowed" | normalize_vidpid)"
			if [[ "$vidpid" == "$allowed" ]]; then
				return 0
			fi
		done
	fi

	if [[ -n "$ALLOW_NAME_REGEX" ]]; then
		local haystack
		haystack="${product} ${vendor} ${serial} ${node}"
		if printf '%s' "$haystack" | LC_ALL=C grep -Eqi "$ALLOW_NAME_REGEX"; then
			return 0
		fi
	fi

	return 1
}

snapshot_devices() {
	# Output TSV lines (sorted):
	# key \t locDec \t locHex \t vidpid \t product \t vendor \t serial \t bDeviceClass \t nodeName
	#
	# key is stable-ish for diffing: locHex|VID:PID|serial
	ioreg -p IOUSB -c IOUSBHostDevice -l -w0 |
		awk '
			function reset_fields() {
				inDev=0
				node=""
				loc=""
				idv=""
				idp=""
				prod=""
				vend=""
				ser=""
				cls=""
			}
			function emit() {
				if (!inDev) return
				if (loc=="" || idv=="" || idp=="") return
				vidpid=sprintf("%04X:%04X", idv, idp)
				locHex=sprintf("0x%08X", loc)
				prodOut=(prod=="" ? node : prod)
				vendOut=(vend=="" ? "-" : vend)
				serOut=(ser=="" ? "-" : ser)
				clsOut=(cls=="" ? "-" : cls)
				key=locHex "|" vidpid "|" serOut
				print key "\t" loc "\t" locHex "\t" vidpid "\t" prodOut "\t" vendOut "\t" serOut "\t" clsOut "\t" node
			}
			BEGIN { reset_fields() }
			/^[| ]*\+-o / {
				# New registry node line
				emit()
				reset_fields()

				# Only track IOUSBHostDevice nodes
				if ($0 !~ /<class IOUSBHostDevice/) next
				inDev=1

				line=$0
				sub(/^[| ]*\+-o /, "", line)
				sub(/  <class.*/, "", line)
				split(line, a, "@")
				node=a[1]
				next
			}
			/"locationID" = / {
				if (!inDev) next
				if (match($0, /"locationID" = [0-9]+/)) {
					tmp=substr($0, RSTART, RLENGTH)
					sub(/.*= /, "", tmp)
					loc=tmp
				}
				next
			}
			/"idVendor" = / {
				if (!inDev) next
				if (match($0, /"idVendor" = [0-9]+/)) {
					tmp=substr($0, RSTART, RLENGTH)
					sub(/.*= /, "", tmp)
					idv=tmp
				}
				next
			}
			/"idProduct" = / {
				if (!inDev) next
				if (match($0, /"idProduct" = [0-9]+/)) {
					tmp=substr($0, RSTART, RLENGTH)
					sub(/.*= /, "", tmp)
					idp=tmp
				}
				next
			}
			/"bDeviceClass" = / {
				if (!inDev) next
				if (match($0, /"bDeviceClass" = [0-9]+/)) {
					tmp=substr($0, RSTART, RLENGTH)
					sub(/.*= /, "", tmp)
					cls=tmp
				}
				next
			}
			/"USB Product Name" = / {
				if (!inDev) next
				if (match($0, /"USB Product Name" = "[^"]*"/)) {
					tmp=substr($0, RSTART, RLENGTH)
					sub(/.*= "/, "", tmp)
					sub(/"$/, "", tmp)
					prod=tmp
				}
				next
			}
			/"USB Vendor Name" = / {
				if (!inDev) next
				if (match($0, /"USB Vendor Name" = "[^"]*"/)) {
					tmp=substr($0, RSTART, RLENGTH)
					sub(/.*= "/, "", tmp)
					sub(/"$/, "", tmp)
					vend=tmp
				}
				next
			}
			/"USB Serial Number" = / {
				if (!inDev) next
				if (match($0, /"USB Serial Number" = "[^"]*"/)) {
					tmp=substr($0, RSTART, RLENGTH)
					sub(/.*= "/, "", tmp)
					sub(/"$/, "", tmp)
					ser=tmp
				}
				next
			}
			END { emit() }
		' |
		LC_ALL=C sort -t $'\t' -k1,1
}

baseline_filter() {
	# Filters snapshot TSV on stdin.
	# Drops lines matching BASELINE_EXCLUDE_VIDPID and/or BASELINE_EXCLUDE_REGEX.
	if [[ -z "$BASELINE_EXCLUDE_VIDPID" && -z "$BASELINE_EXCLUDE_REGEX" ]]; then
		cat
		return 0
	fi

	local exclude_list
	exclude_list="$(printf '%s' "$BASELINE_EXCLUDE_VIDPID" | tr '[:lower:]' '[:upper:]' | tr -d ' ' )"

	awk -v EXCLUDE_LIST="$exclude_list" -v EXCLUDE_RE="$BASELINE_EXCLUDE_REGEX" '
		BEGIN {
			IGNORECASE=1
			n = split(EXCLUDE_LIST, a, ",")
			for (i=1; i<=n; i++) {
				if (a[i] != "") ex[a[i]] = 1
			}
		}
		{
			vidpid = $4
			# Normalize vidpid to uppercase for list compare.
			# BSD awk has toupper().
			vidpid = toupper(vidpid)

			if (EXCLUDE_LIST != "" && (vidpid in ex)) next
			if (EXCLUDE_RE != "" && ($0 ~ EXCLUDE_RE)) next
			print
		}
	'
}

handle_insert() {
	local key="$1" locDec="$2" locHex="$3" vidpid="$4" product="$5" vendor="$6" serial="$7" devClass="$8" node="$9"

	if device_matches_allowlist "$vidpid" "$product" "$vendor" "$serial" "$node"; then
		log "USB attached: port=${locHex} vidpid=${vidpid} class=${devClass} product='${product}' vendor='${vendor}' serial='${serial}'"

		if [[ -z "$LAUNCH_CMD" ]]; then
			return 0
		fi

		export USB_LOCATION_ID_DEC="$locDec"
		export USB_LOCATION_ID_HEX="$locHex"
		export USB_VIDPID="$vidpid"
		export USB_PRODUCT="$product"
		export USB_VENDOR="$vendor"
		export USB_SERIAL="$serial"
		export USB_NODE="$node"

		if [[ "$DRY_RUN" == "1" ]]; then
			log "DRY_RUN=1 would run: ${LAUNCH_CMD}"
			return 0
		fi

		log "Running: ${LAUNCH_CMD}"
		nohup bash -lc "$LAUNCH_CMD" >/dev/null 2>&1 &
	fi
}

handle_remove() {
	local key="$1" locDec="$2" locHex="$3" vidpid="$4" product="$5" vendor="$6" serial="$7" devClass="$8" node="$9"
	log "USB removed:  port=${locHex} vidpid=${vidpid} product='${product}' vendor='${vendor}' serial='${serial}'"
}

main() {
	local once=0
	if (($# > 0)); then
		case "$1" in
			--help|-h) usage; exit 0 ;;
			--once) once=1 ;;
			*) usage; exit 2 ;;
		esac
	fi

	local tmpdir=""
	tmpdir="$(mktemp -d)"
	trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"' EXIT

	local prev="$tmpdir/prev.tsv"
	local cur="$tmpdir/cur.tsv"
	: > "$prev"

	if [[ "$once" == "1" ]]; then
		snapshot_devices
		exit 0
	fi

	# Capture baseline so we only report *new* attachments.
	snapshot_devices | baseline_filter > "$prev" || true
	log "USB detect baseline captured ($(wc -l < "$prev" | tr -d ' ') devices)."
	if [[ -n "$BASELINE_EXCLUDE_VIDPID" || -n "$BASELINE_EXCLUDE_REGEX" ]]; then
		log "Baseline excludes: vidpid='${BASELINE_EXCLUDE_VIDPID}' regex='${BASELINE_EXCLUDE_REGEX}'"
	fi
	log "Watching for new USB attachments (interval=${POLL_INTERVAL_SECONDS}s)."
	log "Port is reported as locationID hex (e.g. 0x01120000)."

	while true; do
		snapshot_devices > "$cur" || true

		# Insertions: in cur not in prev
		comm -13 "$prev" "$cur" | while IFS=$'\t' read -r key locDec locHex vidpid product vendor serial devClass node; do
			handle_insert "$key" "$locDec" "$locHex" "$vidpid" "$product" "$vendor" "$serial" "$devClass" "$node"
		done

		mv "$cur" "$prev"
		sleep "$POLL_INTERVAL_SECONDS"
	done
}

main "$@"
# ioreg -p IOUSB -c IOUSBHostDevice -l -w0 | egrep -n '(^[| ]*\+-o )|("(idVendor|idProduct|locationID|portNum|bDeviceClass|USB Product Name|USB Vendor Name|USB Serial Number)" = )' | head -n 120