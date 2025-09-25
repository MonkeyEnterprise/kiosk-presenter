#!/bin/bash

# =============================================================================
# Kiosk client Sync & Display Script
# -----------------------------------------------------------------------------
# This script is designed to sync media files from a remote source to a local
# directory, and then display those files in a slideshow using the 'feh' tool.
# The script also ensures that the screen stays active (i.e., prevents screen blanking)
# for continuous kiosk operation.
#
# Key Functions:
# 1. Syncs media from a remote source (using rclone) to a local directory.
# 2. Starts a slideshow of the synced media using the 'feh' tool.
# 3. Continuously checks for any changes in the media and restarts the slideshow
#    if new or updated files are detected.
#
# Usage:
# - By default, it syncs media from the configured remote source to the local
#   directory, then starts a slideshow. The script runs indefinitely, checking for
#   updates in the media every $TIMER seconds.
#
# Arguments:
# --remote_path <path>  : Specifies the remote path from which to sync media.
#                         Example: --remote_path "kiosk-dropbox:/Kiosks/Kiosk4"
#
# Requirements:
# - rclone must be installed for syncing media.
# - feh must be installed for displaying the slideshow.
#
# Steps performed by the script:
# 1. Syncs media from a remote source to a local directory.
# 2. Starts the 'feh' slideshow with the synced media.
# 3. Monitors the media directory for changes and restarts the slideshow if necessary.
#
# -----------------------------------------------------------------------------
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# === CONFIG ===
DIR="/home/kiosk/feh"            	# Media directory
LOG="/home/kiosk/core/kiosk_client.log"	# Log file
CACHE="/home/kiosk/core/.cache"         # Cache file for hash
REMOTE="kiosk-dropbox:/"     		# Default remote path
TIMER=300                    		# Sync interval (seconds)

# Parse arguments for custom remote path
while (( "$#" )); do
    case "$1" in
        --remote_path)
            REMOTE="$2"        # Set the remote path argument
            shift 2            # Skip to the next argument
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Log the configured remote path
log() {
    local msg="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S") 
    echo "$timestamp - $msg" >> "$LOG"
}

# Check if rclone is installed
check_rclone() {
    if ! command -v rclone &> /dev/null; then
        log "Error: rclone is not installed."
        exit 1
    fi
}

# Check if feh is installed
check_feh() {
    if ! command -v feh &> /dev/null; then
        log "Error: feh is not installed."
        exit 1
    fi
}

# Sync media from remote to local directory using rclone
sync_media() {
    log "Starting sync from $REMOTE to $DIR"
    output=$(rclone sync "$REMOTE" "$DIR" --exclude '*/**' --delete-during 2>&1)
    log "$output"

    if echo "$output" | grep -i "error"; then
        log "Sync failed. Check log for details."
        exit 1
    fi
}

# Start feh slideshow (runs in background)
start_feh() {
    log "Starting feh slideshow"
    feh -recursive -Y -x -q -D 30 -B black -F -Z "$DIR" &
}

# Check if media has changed by comparing hash and restart feh if needed
check_changes() {
    # Generate hash of media directory
    new_hash=$(ls -lR "$DIR" | sha256sum | awk '{print $1}')

    # If no previous hash exists, create one
    if [ ! -f "$CACHE" ]; then
        echo "$new_hash" > "$CACHE"
    fi

    old_hash=$(cat "$CACHE")

    # Log hash comparison
    log "Old: $old_hash | New: $new_hash"

    # If hashes are different, media changed, restart feh
    if [ "$new_hash" != "$old_hash" ]; then
        log "Media changed. Restarting feh."
        echo "$new_hash" > "$CACHE"   # Update hash
        pkill -x feh                  # Kill existing feh
        sleep 1                        # Pause to ensure feh termination
        start_feh                      # Restart feh
    else
        log "No changes detected."
    fi

    # If feh isn't running, start it
    if ! pgrep -x feh > /dev/null; then
        log "feh isn't running. Starting feh."
        start_feh
    fi
}

# === MAIN LOOP ===

# Check if required programs are installed
check_rclone
check_feh

# Create media directory if it doesn't exist
mkdir -p "$DIR"

# Log the configured remote path
log "Configured remote path: $REMOTE"

# Initial sync and display check
sync_media
check_changes

# Main loop: Run every $TIMER seconds
while true; do
    sleep "$TIMER"            # Sleep for sync interval
    sync_media                # Sync media
    check_changes             # Check for changes and update display
done











