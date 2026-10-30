#!/bin/bash

# =============================================================================
# migrate.sh Tests
# -----------------------------------------------------------------------------
# Builds a kiosk with the old layout (~/core, ~/feh, copied dotfiles, cron jobs
# pointing to ~/core), runs migrate.sh twice and checks the result. Meant to
# run inside the container started by test/run.sh, as user kiosk, with the
# repository mounted at /repo.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# === CONFIG ===
REPO="$HOME/kiosk-presenter"
CEC="$REPO/bin/cec_client.sh"

PASS=0
FAIL=0

check() {
    if eval "$1"; then
        echo "  PASS: $2"
        PASS=$((PASS+1))
    else
        echo "  FAIL: $2"
        FAIL=$((FAIL+1))
    fi
}

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
cp /repo/assets/no-image.png "$HOME/feh/poster.png"
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

check '[ "$(crontab -l | grep -cF "$CEC")" -eq 8 ]' "8 cron jobs point to the repository"
check '! crontab -l | grep -q "/core/"' "no cron jobs point to ~/core"
check 'crontab -l | grep -qF "/usr/bin/true"' "unrelated cron job kept"
check 'grep -q "core/cec-client.sh" "$BACKUP/crontab"' "old crontab in the backup"

echo "== Second run on the migrated kiosk"
sleep 1   # A new backup directory would get a different timestamp
"$REPO/migrate.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ]' "exits successfully"
check '[ "$(backup_dirs)" == "$BACKUP" ]' "creates no new backup"
check '[ "$(crontab -l | grep -cF "$CEC")" -eq 8 ]' "cron jobs not duplicated"
check '[ -f "$HOME/media/poster.png" ]' "media untouched"

echo "== Scripts work from the new layout"
"$CEC" "on 0" > /dev/null 2>&1
check 'grep -q "Starting CEC command execution: on 0" "$HOME/logs/cec_client.log"' "cec_client.sh logs to ~/logs"
check '[ -x "$REPO/bin/kiosk_client.sh" ] && [ -x "$CEC" ]' "scripts are executable"

echo
echo "== Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
