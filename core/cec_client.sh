#!/bin/bash

# =============================================================================
# CEC Client Script - Interact with HDMI Devices using the CEC Protocol
# -----------------------------------------------------------------------------
# This script interacts with CEC (Consumer Electronics Control) adapters over 
# HDMI to send commands for managing devices such as TVs, audio systems, and more. 
# The script supports executing CEC commands such as turning devices on/off, 
# setting standby modes, etc., across multiple detected CEC adapters.
#
# Usage:
#   ./cec_client.sh <commands>
# 
# Options:
#   <commands>   : The CEC commands to be sent to the detected CEC adapters.
#
# Example:
#   ./cec_client.sh "on 0" "standby 0"
#
# Commands:
#   - "on <logical_address>"      : Power on a device at a specific logical address.
#   - "standby <logical_address>" : Put a device into standby mode at a specific logical address.
# -----------------------------------------------------------------------------
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# === CONFIG ===
LOGFILE="/home/kiosk/core/cec_client.log"  # Log file to store all log messages
COMMANDS=()               # Array to store all CEC commands passed as arguments

# Logging function: prints message with timestamp to logfile
log() {
  echo "$(date "+%Y-%m-%d %H:%M:%S") - $*" >> "$LOGFILE"
}

# Parse the script arguments to capture commands
while (( "$#" )); do
  COMMANDS+=("$1")
  shift
done

# Ensure at least one CEC command is provided
if [ ${#COMMANDS[@]} -eq 0 ]; then
  log "Error: No CEC command provided. Usage: $0 'on 0'"
  exit 1
fi

# Log the start of CEC command execution
log "Starting CEC command execution: ${COMMANDS[*]}"

# Detect all available CEC adapters (e.g., /dev/cec0, /dev/cec1, etc.)
adapters=(/dev/cec*)

# Exit if no CEC adapters are found
if [ ${#adapters[@]} -eq 0 ]; then
  log "No CEC adapters found."
  exit 1
fi

# Log the list of found adapters
log "Found ${#adapters[@]} CEC adapter(s): ${adapters[*]}"

# Iterate over each detected adapter device
for dev in "${adapters[@]}"; do
  # Confirm the device file exists (may be a glob without matches)
  if [ ! -e "$dev" ]; then
    log "Device $dev does not exist."
    continue
  fi

  log "Testing CEC adapter: $dev"

  # Send 'scan' command to test if the adapter responds
  output=$(echo 'scan' | cec-client -s -d 1 "$dev" 2>&1)
  exit_code=$?

  # Log the scan output to the logfile
  log "Scan output for $dev:"
  log "$output"

  # Check if the scan command failed (non-zero exit) or output contains "error"
  if [ $exit_code -ne 0 ] || echo "$output" | grep -iq "error"; then
    log "Adapter $dev did not respond to scan."
    continue
  fi

  # Flag to track if all commands sent to this adapter succeed
  all_success=true

  # Loop over each CEC command provided as argument
  for cmd in "${COMMANDS[@]}"; do
    log "Sending command: $cmd to $dev"

    # Send command to adapter and capture output
    output=$(echo "$cmd" | cec-client -s -d 1 "$dev" 2>&1)

    # Log command output to the logfile
    log "Command output for $dev:"
    log "$output"

    # Detect transmission errors in the output (e.g., failure to transmit)
    if echo "$output" | grep -q 'ioctl CEC_TRANSMIT failed'; then
      log "Transmission error on $dev for command: $cmd"
      all_success=false
      break  # Stop sending further commands to this adapter
    fi
  done

  # If all commands succeeded on this adapter, log success and exit
  if $all_success; then
    log "Commands successfully executed on $dev"
    exit 0
  else
    # Otherwise, try the next adapter
    log "Commands failed on $dev, trying next adapter."
  fi
done

# If no working CEC adapters were found, log failure and exit with error code
log "No working CEC adapter found after trying all."
exit 1

