#!/bin/bash

# =============================================================================
# migrate.sh Tests: core layout
# -----------------------------------------------------------------------------
# Builds a kiosk with the core layout (~/core, ~/feh, copied dotfiles, cron
# jobs pointing to ~/core), runs migrate.sh twice and checks the result. Meant
# to run inside the container started by test/run.sh, as user kiosk, with the
# repository mounted at /repo.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

source /repo/test/lib.sh

# === CONFIG ===
REPO="$HOME/kiosk-presenter"
TV_POWER="$REPO/bin/tv-power"

backup_dirs() {
    ls -d "$HOME"/kiosk-backup-* 2> /dev/null
}

# =============================================================================
# Old kiosk layout
# =============================================================================

cp -a /repo "$REPO"

mkdir -p "$HOME/core" "$HOME/feh"
echo "old script" > "$HOME/core/kiosk_client.sh"
echo "old script" > "$HOME/core/cec_client.sh"
echo "old kiosk log line" > "$HOME/core/kiosk_client.log"
echo "old cec log line" > "$HOME/core/cec_client.log"
echo "oldhash" > "$HOME/core/.cache"
cp /repo/test/fixtures/image.png "$HOME/feh/poster.png"
echo "old xinitrc" > "$HOME/.xinitrc"
echo "old bash_profile" > "$HOME/.bash_profile"
echo "export RCLONE_REMOTE_PATH='kiosk-dropbox:/Kiosks/Kiosk4'" >> "$HOME/.bashrc"
crontab - <<'EOF'
0 3 * * * /usr/bin/true
0 6 * * 1-5 /home/kiosk/core/cec-client.sh "on 0"
0 9 * * 1-5 /home/kiosk/core/cec-client.sh "standby 0"
EOF

# =============================================================================
# Tests
# =============================================================================

echo "== Refuses to run from the wrong location"
/repo/migrate.sh > /tmp/out 2>&1; rc=$?
check '[ $rc -ne 0 ] && grep -q "must be at $REPO" /tmp/out' "exits with a clear message"
check '[ -d "$HOME/core" ]' "changes nothing"

echo "== First run"
"$REPO/migrate.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ]' "exits successfully"
BACKUP=$(backup_dirs)
check '[ "$(echo "$BACKUP" | wc -l)" -eq 1 ] && [ -d "$BACKUP" ]' "creates one backup directory"

check '[ -f "$HOME/media/poster.png" ] && [ ! -e "$HOME/feh" ]' "media moved from ~/feh to ~/media"
check 'grep -q "old kiosk log line" "$HOME/logs/kiosk_client.log"' "kiosk_client.log moved to ~/logs"
check 'grep -q "old cec log line" "$HOME/logs/cec_client.log"' "cec_client.log moved to ~/logs"
check '[ ! -e "$HOME/core" ] && [ -f "$BACKUP/core/kiosk_client.sh" ]' "~/core moved to the backup"
check '[ ! -e "$BACKUP/core/.cache" ]' "hash cache dropped"

check '[ "$(readlink "$HOME/.xinitrc")" == "$REPO/dotfiles/xinitrc" ]' "~/.xinitrc links to the repository"
check '[ "$(readlink "$HOME/.bash_profile")" == "$REPO/dotfiles/bash_profile" ]' "~/.bash_profile links to the repository"
check 'grep -q "old xinitrc" "$BACKUP/.xinitrc.bak"' "old .xinitrc in the backup"
check 'grep -q "old bash_profile" "$BACKUP/.bash_profile.bak"' "old .bash_profile in the backup"
check '[ ! -e "$HOME/.xinitrc.bak" ] && [ ! -e "$HOME/.bash_profile.bak" ]' "no .bak files left in ~"

check '[ "$(crontab -l | grep -cF "$TV_POWER")" -eq 8 ]' "8 cron jobs call the repository's tv-power"
check '! crontab -l | grep -q -e "/core/" -e "cec[-_]client"' "no cron jobs call the old scripts"
check 'crontab -l | grep -qF "/usr/bin/true"' "unrelated cron job kept"
check 'grep -q "core/cec-client.sh" "$BACKUP/crontab"' "old crontab in the backup"
check '[ "$(readlink /usr/local/bin/tv-power)" == "$TV_POWER" ]' "/usr/local/bin/tv-power links to the repository"
check '[ "$(grep -c "^export RCLONE_REMOTE_PATH=" "$HOME/.bashrc")" -eq 1 ] && grep -q "Kiosks/Kiosk4" "$HOME/.bashrc"' "RCLONE_REMOTE_PATH kept"

echo "== Second run on the migrated kiosk"
sleep 1   # A new backup directory would get a different timestamp
"$REPO/migrate.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ]' "exits successfully"
check '[ "$(backup_dirs)" == "$BACKUP" ]' "creates no new backup"
check '[ "$(crontab -l | grep -cF "$TV_POWER")" -eq 8 ]' "cron jobs not duplicated"
check '[ -f "$HOME/media/poster.png" ]' "media untouched"

echo "== Scripts work from the new layout"
tv-power off > /dev/null 2>&1
check 'grep -q "Starting CEC command execution: --standby" "$HOME/logs/cec_client.log"' "tv-power off reaches cec_client.sh, which logs to ~/logs"
check '[ -x "$REPO/bin/kiosk_client.sh" ] && [ -x "$TV_POWER" ]' "scripts are executable"

finish
