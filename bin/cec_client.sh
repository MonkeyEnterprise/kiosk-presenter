#!/bin/bash

# =============================================================================
# CEC Client Script - Control the TV over HDMI-CEC
# -----------------------------------------------------------------------------
# Sends one CEC command to the TV through the HDMI port it is connected to.
# The Raspberry Pi 5 has two HDMI ports (/dev/cec0 and /dev/cec1). Every port
# is scanned and tried in this order, until one transmits the command:
# 1. ports whose scan shows the TV (logical address 0), even if the scan also
#    logged errors;
# 2. ports whose scan ran without errors;
# 3. ports whose scan failed. A port without a TV logs 'ioctl CEC_TRANSMIT
#    failed' errors during the scan; it is still tried last, in case the TV
#    didn't answer the scan.
#
# Usage:
#   cec_client.sh --on | --standby | --as
#
# Options:
#   --on        Turn the TV on and, once that succeeded, make the Pi the
#               active source, so the TV switches back to the Pi's input even
#               when someone left it on another channel. Some TVs (e.g. TCL)
#               also only really switch on after that.
#   --standby   Put the TV in standby
#   --as        Only make the Pi the active source
#
# Environment:
#   KIOSK_LOG_DIR       Log directory (default /var/log/kiosk-presenter, or
#                       ~/logs while that doesn't exist)
#   KIOSK_CEC_DEVICES   CEC devices to try, as a glob (default /dev/cec*)
#   KIOSK_CEC_AS_DELAY  Seconds between 'on' and 'as' for --on, so the TV has
#                       time to wake up (default 5)
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# === CONFIG ===
LOG_DIR="${KIOSK_LOG_DIR:-/var/log/kiosk-presenter}"  # Log directory (shared with kiosk_client.sh)
DEVICES="${KIOSK_CEC_DEVICES:-/dev/cec*}"       # CEC adapters to try
AS_DELAY="${KIOSK_CEC_AS_DELAY:-5}"             # Wait between 'on' and 'as'

# setup.sh and migrate.sh create the log directory; until then, use ~/logs
if ! mkdir -p "$LOG_DIR" 2> /dev/null || [ ! -w "$LOG_DIR" ]; then
  LOG_DIR="$HOME/logs"
  mkdir -p "$LOG_DIR"
fi
LOGFILE="$LOG_DIR/cec_client.log"               # Log file to store all log messages

# Logging function: prints message with timestamp to logfile
log() {
  echo "$(date "+%Y-%m-%d %H:%M:%S") - $*" >> "$LOGFILE"
}

usage() {
  echo "Usage: $0 --on | --standby | --as"
}

# Send a command to one adapter; fails when the adapter can't transmit it
send_command() {
  local dev="$1"
  local cmd="$2"
  local output

  log "Sending '$cmd' to $dev"
  output=$(echo "$cmd" | cec-client -s -d 1 "$dev" 2>&1)
  log "Command output for $dev:"
  log "$output"

  if echo "$output" | grep -q 'ioctl CEC_TRANSMIT failed'; then
    log "Transmission error on $dev for '$cmd'."
    return 1
  fi
}

# Map the option to the cec-client command
case "$1" in
  --on)      COMMAND="on 0" ;;
  --standby) COMMAND="standby 0" ;;
  --as)      COMMAND="as" ;;
  *)
    usage
    log "Error: invalid option '$1'"
    exit 1
    ;;
esac

log "Starting CEC command execution: $1 ($COMMAND)"

# Scan every adapter and sort them into the three groups described above
tv_adapters=()
other_adapters=()
failed_adapters=()
for dev in $DEVICES; do
  # The glob stays unexpanded when there are no adapters
  [ -e "$dev" ] || continue

  output=$(echo 'scan' | cec-client -s -d 1 "$dev" 2>&1)
  exit_code=$?
  log "Scan output for $dev:"
  log "$output"

  if echo "$output" | grep -q "^device #0:"; then
    log "Adapter $dev sees the TV."
    tv_adapters+=("$dev")
  elif [ $exit_code -ne 0 ] || echo "$output" | grep -iq "error"; then
    log "Adapter $dev scan failed (no TV on this port?), trying it last."
    failed_adapters+=("$dev")
  else
    log "Adapter $dev responds, but sees no TV."
    other_adapters+=("$dev")
  fi
done

adapters=("${tv_adapters[@]}" "${other_adapters[@]}" "${failed_adapters[@]}")
if [ ${#adapters[@]} -eq 0 ]; then
  log "No CEC adapters found."
  exit 1
fi

# Send the command, stop at the first adapter that transmits it
for dev in "${adapters[@]}"; do
  if ! send_command "$dev" "$COMMAND"; then
    log "Trying next adapter."
    continue
  fi
  log "Command successfully executed on $dev"

  # After a successful 'on', switch the TV to the Pi's input on the same port
  if [ "$1" == "--on" ]; then
    sleep "$AS_DELAY"
    if ! send_command "$dev" "as"; then
      log "TV is on, but switching it to the Pi's input failed."
      exit 1
    fi
    log "TV switched to the Pi's input on $dev"
  fi
  exit 0
done

log "No adapter could transmit '$COMMAND'."
exit 1
