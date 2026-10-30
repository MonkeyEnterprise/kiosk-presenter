#!/bin/bash

# =============================================================================
# Kiosk Migration Script
# -----------------------------------------------------------------------------
# Moves a kiosk from the old layout (scripts, logs and cache in ~/core, media
# in ~/feh, copied dotfiles) to the current one:
#
#   ~/kiosk-presenter   git clone of this repository
#   ~/media             synced media
#   ~/logs              logs and hash cache
#
# Steps performed by this script:
# 1. Moves ~/feh to ~/media, so the media doesn't have to be downloaded again.
# 2. Moves the logs from ~/core to ~/logs.
# 3. Moves ~/core to the backup directory (it only held the old scripts).
# 4. Replaces ~/.xinitrc and ~/.bash_profile with links to the repository.
# 5. Points the cec_client cron jobs to the repository.
#
# Everything that is replaced is kept in ~/kiosk-backup-<date>. Running the
# script again on a migrated kiosk changes nothing.
#
# Usage:
# - Clone the repository to ~/kiosk-presenter as the kiosk user, run
#   ./migrate.sh from there and reboot.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# Reuse log(), check_not_root, check_repo_location, link_dotfile and
# install_crontab from setup.sh
source "$(dirname "$(realpath "$0")")/setup.sh"

OLD_CORE="$HOME/core"
OLD_MEDIA="$HOME/feh"
MEDIA="$HOME/media"
LOGS="$HOME/logs"
BACKUP="$HOME/kiosk-backup-$(date "+%Y%m%d-%H%M%S")"

# Create the backup directory on first use, so a run with nothing to back up
# leaves no empty directory behind
backup() {
    mkdir -p "$BACKUP"
    mv "$1" "$BACKUP/"
    log "Moved $1 to $BACKUP/"
}

migrate_media() {
    if [ ! -d "$OLD_MEDIA" ]; then
        log "No $OLD_MEDIA found, nothing to move."
    elif [ -e "$MEDIA" ]; then
        log "$MEDIA already exists, keeping it."
        backup "$OLD_MEDIA"
    else
        mv "$OLD_MEDIA" "$MEDIA"
        log "Moved $OLD_MEDIA to $MEDIA"
    fi
}

migrate_core() {
    if [ ! -d "$OLD_CORE" ]; then
        log "No $OLD_CORE found, nothing to move."
        return 0
    fi

    mkdir -p "$LOGS"
    local logfile
    for logfile in "$OLD_CORE"/*.log; do
        [ -f "$logfile" ] || continue
        cat "$logfile" >> "$LOGS/$(basename "$logfile")"
        rm "$logfile"
        log "Moved $logfile to $LOGS/"
    done

    # The hash cache is recreated by kiosk_client.sh
    rm -f "$OLD_CORE/.cache"

    backup "$OLD_CORE"
}

migrate_dotfiles() {
    local name
    for name in xinitrc bash_profile; do
        link_dotfile "$name"
        # link_dotfile keeps a replaced file as .bak; move it to the backup
        if [ -e "$HOME/.$name.bak" ] || [ -L "$HOME/.$name.bak" ]; then
            backup "$HOME/.$name.bak"
        fi
    done
}

migrate_crontab() {
    local current
    current=$(crontab -l 2>/dev/null)
    if echo "$current" | grep -q 'cec[-_]client\.sh' && ! echo "$current" | grep -qF "$REPO_DIR/bin/cec_client.sh"; then
        mkdir -p "$BACKUP"
        echo "$current" > "$BACKUP/crontab"
        log "Backed up crontab to $BACKUP/crontab"
    fi
    install_crontab
}

check_remote_path() {
    if ! grep -q "RCLONE_REMOTE_PATH" "$BASHRC_FILE" 2>/dev/null; then
        log "Warning: RCLONE_REMOTE_PATH is not set in $BASHRC_FILE, so the default remote (kiosk-dropbox:/) will be used."
    fi
}

check_not_root
check_repo_location
migrate_media
migrate_core
migrate_dotfiles
migrate_crontab
check_remote_path

[ -d "$BACKUP" ] && log "Backup of the old files: $BACKUP"
log "Migration complete. Reboot to start the kiosk with the new layout: sudo reboot"
