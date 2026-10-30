#!/bin/bash

# =============================================================================
# migrate.sh Tests: logs in ~/logs
# -----------------------------------------------------------------------------
# Builds a kiosk with the current layout from before the logs moved to
# /var/log (as on kiosk1): logs, a rotated log, the hash cache and the
# placeholder in ~/logs. Runs migrate.sh twice and checks that the logs end up
# in /var/log/kiosk-presenter. Meant to run inside the container started by
# test/run.sh, as user kiosk, with the repository mounted at /repo.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

source /repo/test/lib.sh

# === CONFIG ===
REPO="$HOME/kiosk-presenter"
LOGS="/var/log/kiosk-presenter"

# =============================================================================
# Kiosk with logs in ~/logs
# =============================================================================

cp -a /repo "$REPO"
ln -s "$REPO/dotfiles/xinitrc" "$HOME/.xinitrc"
ln -s "$REPO/dotfiles/bash_profile" "$HOME/.bash_profile"
echo "export RCLONE_REMOTE_PATH='kiosk-dropbox:/Kiosks/Kiosk1'" >> "$HOME/.bashrc"
mkdir -p "$HOME/logs" "$HOME/media"
echo "current kiosk log line" > "$HOME/logs/kiosk_client.log"
echo "rotated kiosk log line" > "$HOME/logs/kiosk_client.log.1"
echo "current cec log line" > "$HOME/logs/cec_client.log"
echo "somehash" > "$HOME/logs/.cache"
echo "<svg/>" > "$HOME/logs/placeholder.svg"

# =============================================================================
# Tests
# =============================================================================

echo "== First run"
"$REPO/migrate.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ]' "exits successfully"
check '[ "$(stat -c "%U %a" $LOGS)" == "$(id -un) 755" ]' "log directory created, owned by the kiosk user"
check 'grep -q "current kiosk log line" $LOGS/kiosk_client.log' "kiosk_client.log moved"
check 'grep -q "rotated kiosk log line" $LOGS/kiosk_client.log.1' "rotated log moved too"
check 'grep -q "current cec log line" $LOGS/cec_client.log' "cec_client.log moved"
check '[ ! -e "$HOME/logs" ]' "~/logs removed (cache and placeholder are recreated in ~/.cache)"
check '! ls -d "$HOME"/kiosk-backup-* > /dev/null 2>&1' "nothing needed a backup"
check 'grep -qF "$LOGS/*.log" /etc/logrotate.d/kiosk-presenter' "log rotation points to the new directory"

echo "== Second run"
"$REPO/migrate.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ]' "exits successfully"
check '[ "$(grep -c "current kiosk log line" $LOGS/kiosk_client.log)" -eq 1 ]' "logs not duplicated"

echo "== Scripts log to the new directory"
"$REPO/bin/cec_client.sh" --standby > /dev/null 2>&1
check 'grep -q "Starting CEC command execution: --standby" $LOGS/cec_client.log' "cec_client.sh logs to $LOGS"
check '[ ! -e "$HOME/logs" ]' "no fallback to ~/logs"

finish
