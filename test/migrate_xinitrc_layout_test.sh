#!/bin/bash

# =============================================================================
# migrate.sh Tests: xinitrc layout
# -----------------------------------------------------------------------------
# Builds a kiosk with the xinitrc layout (sync loop and REMOTE_PATH in
# ~/.xinitrc, media in ~/media/feh, ~/feh_sync.log, a tv-power copy in
# /usr/local/bin), runs migrate.sh twice and checks the result. Meant to run
# inside the container started by test/run.sh, as user kiosk, with the
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

mkdir -p "$HOME/media/feh"
cp /repo/assets/no-image.png "$HOME/media/feh/no-image.png"
cp /repo/assets/no-image.png "$HOME/media/feh/poster.png"
echo "somehash" > "$HOME/media/feh/.last_hash"
echo "old sync log line" > "$HOME/feh_sync.log"
cat > "$HOME/.xinitrc" <<'EOF'
#!/bin/bash
# Installed as ~/.xinitrc by kiosk-presenter setup.sh
MEDIA_DIR="$HOME/media/feh"
REMOTE_PATH="dropbox_kiosk:/Kiosks/Hal"
EOF
printf '# user stuff\n\n# Start X automatically if not already running\nstartx\n' > "$HOME/.bash_profile"
printf '#!/bin/bash\necho old tv-power\n' | sudo tee /usr/local/bin/tv-power > /dev/null
sudo chmod 755 /usr/local/bin/tv-power
printf '#!/bin/sh\n' | sudo tee /usr/local/bin/cloudflared > /dev/null
sudo chown kiosk:kiosk /usr/local/bin/cloudflared
crontab - <<'EOF'
0 3 * * * /usr/bin/true
0 6 * * 1-5 /usr/local/bin/tv-power on >/dev/null 2>&1
0 9 * * 1-5 /usr/local/bin/tv-power off >/dev/null 2>&1
EOF

# =============================================================================
# Tests
# =============================================================================

echo "== First run"
"$REPO/migrate.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ]' "exits successfully"
BACKUP=$(backup_dirs)
check '[ "$(echo "$BACKUP" | wc -l)" -eq 1 ] && [ -d "$BACKUP" ]' "creates one backup directory"

check 'grep -qx "export RCLONE_REMOTE_PATH='"'"'dropbox_kiosk:/Kiosks/Hal'"'"'" "$HOME/.bashrc"' "REMOTE_PATH from ~/.xinitrc moved to ~/.bashrc"
check '[ -f "$HOME/media/poster.png" ] && [ ! -e "$HOME/media/feh" ]' "media moved from ~/media/feh to ~/media"
check '[ ! -e "$HOME/media/.last_hash" ]' "old hash file dropped"
check '[ ! -e "$HOME/feh_sync.log" ] && grep -q "old sync log line" "$BACKUP/feh_sync.log"' "~/feh_sync.log moved to the backup"

check '[ "$(readlink "$HOME/.xinitrc")" == "$REPO/dotfiles/xinitrc" ]' "~/.xinitrc links to the repository"
check '[ "$(readlink "$HOME/.bash_profile")" == "$REPO/dotfiles/bash_profile" ]' "~/.bash_profile links to the repository"
check 'grep -q "REMOTE_PATH=" "$BACKUP/.xinitrc.bak"' "old .xinitrc in the backup"
check 'grep -q "user stuff" "$BACKUP/.bash_profile.bak"' "old .bash_profile in the backup"

check '[ "$(readlink /usr/local/bin/tv-power)" == "$TV_POWER" ]' "/usr/local/bin/tv-power links to the repository"
check '[ "$(crontab -l | grep -cF "$TV_POWER")" -eq 8 ]' "8 cron jobs call the repository's tv-power"
check '! crontab -l | grep -qF "/usr/local/bin/tv-power"' "no cron jobs call the old tv-power copy"
check 'crontab -l | grep -qF "/usr/bin/true"' "unrelated cron job kept"
check 'grep -qF "/usr/local/bin/tv-power on" "$BACKUP/crontab"' "old crontab in the backup"
check '[ "$(stat -c %U:%G /usr/local/bin/cloudflared)" == "root:root" ]' "cloudflared binary owned by root"

echo "== Second run on the migrated kiosk"
sleep 1   # A new backup directory would get a different timestamp
"$REPO/migrate.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ]' "exits successfully"
check '[ "$(backup_dirs)" == "$BACKUP" ]' "creates no new backup"
check '[ "$(grep -c "^export RCLONE_REMOTE_PATH=" "$HOME/.bashrc")" -eq 1 ]' "RCLONE_REMOTE_PATH not duplicated"
check '[ "$(crontab -l | grep -cF "$TV_POWER")" -eq 8 ]' "cron jobs not duplicated"

echo "== Warns about the example remote path"
sed -i "s|^export RCLONE_REMOTE_PATH=.*|export RCLONE_REMOTE_PATH='dropbox_kiosk:/path'|" "$HOME/.bashrc"
"$REPO/migrate.sh" > /tmp/out 2>&1
check 'grep -q "still the example value" /tmp/out' "warning shown"

echo "== Bash profile loads the remote path for X"
# The tty1 login shell is interactive; the default .bashrc returns early otherwise
check '[ "$(bash -i -c "source $HOME/.bashrc; echo \$RCLONE_REMOTE_PATH" 2> /dev/null)" == "dropbox_kiosk:/path" ]' "RCLONE_REMOTE_PATH is exported from ~/.bashrc"

finish
