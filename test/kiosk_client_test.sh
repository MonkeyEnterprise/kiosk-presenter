#!/bin/bash

# =============================================================================
# kiosk_client.sh Tests
# -----------------------------------------------------------------------------
# Runs bin/kiosk_client.sh against a local directory acting as the rclone
# remote, with feh on a virtual X server (Xvfb). The sync interval is lowered
# from 300s to 2s. Meant to run inside the container started by test/run.sh,
# as user kiosk, with the repository mounted at /repo.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# === CONFIG ===
CLIENT="/repo/bin/kiosk_client.sh"
REMOTE="/home/kiosk/remote"
IMG="/repo/test/fixtures/image.png" # Any image will do as test media

export KIOSK_MEDIA_DIR="/home/kiosk/media"
export KIOSK_LOG_DIR="/home/kiosk/logs"
export KIOSK_STATE_DIR="/home/kiosk/state"
export KIOSK_SYNC_INTERVAL=2
MEDIA="$KIOSK_MEDIA_DIR"
LOG="$KIOSK_LOG_DIR/kiosk_client.log"

source /repo/test/lib.sh

# Args of the running feh process (empty if feh isn't running)
feh_args() {
    ps -o args= -C feh
}

# Start every test from a clean kiosk
reset_kiosk() {
    pkill -f kiosk_client.sh
    pkill -x feh
    sleep 0.5
    rm -rf "$MEDIA" "$KIOSK_LOG_DIR" "$KIOSK_STATE_DIR" "$REMOTE"
    mkdir -p "$REMOTE"
}

Xvfb :99 -screen 0 1280x720x24 > /dev/null 2>&1 &
export DISPLAY=:99
sleep 1

# =============================================================================
# Tests
# =============================================================================

echo "== --remote_path without a value"
reset_kiosk
"$CLIENT" --remote_path 2> /dev/null &
PID=$!; sleep 3
check '[ -s "$LOG" ]' "script gets past argument parsing"
check 'grep -q "Configured remote path: kiosk-dropbox:/" "$LOG"' "falls back to the default remote"
check 'kill -0 $PID 2> /dev/null' "script keeps running after a failed sync"
check '[[ "$(feh_args)" == *placeholder.svg* ]]' "feh shows the placeholder"
check 'grep -q "width=\"1280\" height=\"720\"" "$KIOSK_STATE_DIR/placeholder.svg"' "placeholder sized for the 1280x720 screen"
check 'grep -qF "$(hostname) · " "$KIOSK_STATE_DIR/placeholder.svg" && ! grep -q "__DEVICE__" "$KIOSK_STATE_DIR/placeholder.svg"' "placeholder shows the hostname and IP address"

echo "== Default log directory not created yet"
reset_kiosk
rm -rf "$HOME/logs"
env -u KIOSK_LOG_DIR "$CLIENT" --remote_path "$REMOTE" 2> /dev/null &
PID=$!; sleep 3
check '[ ! -e /var/log/kiosk-presenter ] && grep -q "logging to $HOME/logs" "$HOME/logs/kiosk_client.log"' "falls back to ~/logs and says so"
check 'kill -0 $PID 2> /dev/null' "script keeps running"
rm -rf "$HOME/logs"

echo "== --remote_path with an empty value (empty RCLONE_REMOTE_PATH in xinitrc)"
reset_kiosk
"$CLIENT" --remote_path "" 2> /dev/null &
PID=$!; sleep 3
check 'grep -q "Configured remote path: kiosk-dropbox:/" "$LOG"' "falls back to the default remote"
check 'kill -0 $PID 2> /dev/null' "script keeps running"

echo "== Normal sync and slideshow"
reset_kiosk
cp "$IMG" "$REMOTE/a.png"
cp "$IMG" "$REMOTE/b.png"
mkdir "$REMOTE/sub"
cp "$IMG" "$REMOTE/sub/c.png"
"$CLIENT" --remote_path "$REMOTE" 2> /dev/null &
PID=$!; sleep 3
check '[ -f "$MEDIA/a.png" ] && [ -f "$MEDIA/b.png" ]' "files are synced"
check '[ ! -e "$MEDIA/sub" ]' "subdirectories are not synced"
check '[[ "$(feh_args)" == *"$MEDIA" ]]' "feh shows the media directory"
FEH1=$(pgrep -x feh)

echo "== New file on the remote"
cp "$IMG" "$REMOTE/d.png"; sleep 5
FEH2=$(pgrep -x feh)
check '[ -f "$MEDIA/d.png" ]' "new file is synced"
check '[ -n "$FEH2" ] && [ "$FEH1" != "$FEH2" ]' "feh is restarted"

echo "== Remote unreachable (no network)"
mv "$REMOTE" "$REMOTE.off"; sleep 5
check 'grep -q "Sync failed (exit code" "$LOG"' "sync failure is logged with its exit code"
check 'kill -0 $PID 2> /dev/null' "script keeps running"
check '[[ "$(feh_args)" == *"$MEDIA" ]]' "feh keeps showing the media directory"
check '[ "$(ls "$MEDIA" | wc -l)" -eq 3 ]' "local media is kept"

echo "== Remote reachable again, file deleted on the remote"
mv "$REMOTE.off" "$REMOTE"
rm "$REMOTE/a.png"; sleep 5
check '[ ! -f "$MEDIA/a.png" ]' "deleted file is removed locally"
check 'pgrep -x feh > /dev/null' "feh is running"

echo "== File name containing 'error'"
cp "$IMG" "$REMOTE/error-poster.png"; sleep 5
check '[ -f "$MEDIA/error-poster.png" ]' "file is synced"
check '! tail -n 20 "$LOG" | grep -q "Sync failed"' "no false sync failure"
check 'kill -0 $PID 2> /dev/null' "script keeps running"

echo "== All files removed from the remote"
rm "$REMOTE"/*.png; sleep 5
check '[ -z "$(ls -A "$MEDIA")" ]' "media directory is empty"
check '[[ "$(feh_args)" == *placeholder.svg* ]]' "feh switches to the placeholder"

echo "== Remote with files, but no images"
echo "not an image" > "$REMOTE/Vault.dbx-vault"; sleep 5
check '[ -f "$MEDIA/Vault.dbx-vault" ]' "file is synced"
check '[[ "$(feh_args)" == *placeholder.svg* ]]' "feh shows the placeholder instead of a black screen"
rm "$REMOTE/Vault.dbx-vault"

echo "== Media arrives on a kiosk showing the placeholder"
cp "$IMG" "$REMOTE/e.png"; sleep 5
check '[[ "$(feh_args)" == *"$MEDIA" ]]' "feh switches back to the slideshow"

finish
