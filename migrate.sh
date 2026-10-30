#!/bin/bash

# =============================================================================
# Kiosk Migration Script
# -----------------------------------------------------------------------------
# Moves a kiosk from one of the older layouts to the current one:
#
#   ~/kiosk-presenter   git clone of this repository
#   ~/media             synced media
#   ~/logs              logs and hash cache
#
# Older layouts it recognizes:
# - xinitrc layout: the whole sync loop in ~/.xinitrc (with REMOTE_PATH in
#   it), media in ~/media/feh, log in ~/feh_sync.log, a copy of tv-power in
#   /usr/local/bin.
# - core layout: scripts, logs and cache in ~/core, media in ~/feh,
#   RCLONE_REMOTE_PATH in ~/.bashrc, cron jobs calling ~/core/cec-client.sh.
#
# Steps performed by this script:
# 1. Moves REMOTE_PATH from an old ~/.xinitrc to RCLONE_REMOTE_PATH in
#    ~/.bashrc.
# 2. Moves the media to ~/media, so it doesn't have to be downloaded again.
# 3. Moves the logs to ~/logs and ~/core to the backup directory.
# 4. Replaces ~/.xinitrc and ~/.bash_profile with links to the repository.
# 5. Links /usr/local/bin/tv-power to the repository and replaces the TV power
#    cron jobs.
#
# Everything that is replaced is kept in ~/kiosk-backup-<date>. Running the
# script again on a migrated kiosk changes nothing. Cloudflared is left alone.
#
# Usage:
# - Clone the repository to ~/kiosk-presenter as the kiosk user, run
#   ./migrate.sh from there and reboot.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# Reuse log(), the checks, link_dotfile, install_tv_power, install_crontab and
# save_remote_path from setup.sh
source "$(dirname "$(realpath "$0")")/setup.sh"

OLD_CORE="$HOME/core"
OLD_MEDIA="$HOME/feh"
OLD_XINITRC_MEDIA="$HOME/media/feh"
OLD_XINITRC_LOG="$HOME/feh_sync.log"
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

# The xinitrc layout kept the remote in ~/.xinitrc; the current dotfiles read
# RCLONE_REMOTE_PATH from ~/.bashrc instead
migrate_remote_path() {
    if [ -L "$HOME/.xinitrc" ] || [ ! -f "$HOME/.xinitrc" ]; then
        return 0
    fi

    local remote_path
    remote_path=$(sed -n 's/^REMOTE_PATH="\(.*\)"$/\1/p' "$HOME/.xinitrc" | head -n 1)
    if [ -z "$remote_path" ]; then
        return 0
    fi

    if grep -q '^export RCLONE_REMOTE_PATH=' "$BASHRC_FILE" 2>/dev/null; then
        log "RCLONE_REMOTE_PATH is already set in $BASHRC_FILE, ignoring REMOTE_PATH=$remote_path from ~/.xinitrc."
    else
        save_remote_path "$remote_path"
    fi
}

migrate_media() {
    if [ -d "$OLD_XINITRC_MEDIA" ]; then
        # The hash file is recreated by kiosk_client.sh in ~/logs
        rm -f "$OLD_XINITRC_MEDIA/.last_hash"
        local file
        for file in "$OLD_XINITRC_MEDIA"/* "$OLD_XINITRC_MEDIA"/.[!.]*; do
            [ -e "$file" ] || continue
            mv -n "$file" "$MEDIA/"
        done
        rmdir "$OLD_XINITRC_MEDIA" 2>/dev/null || backup "$OLD_XINITRC_MEDIA"
        log "Moved the media from $OLD_XINITRC_MEDIA to $MEDIA"
    fi

    if [ -d "$OLD_MEDIA" ]; then
        if [ -e "$MEDIA" ]; then
            log "$MEDIA already exists, keeping it."
            backup "$OLD_MEDIA"
        else
            mv "$OLD_MEDIA" "$MEDIA"
            log "Moved $OLD_MEDIA to $MEDIA"
        fi
    fi
}

migrate_logs() {
    if [ -f "$OLD_XINITRC_LOG" ]; then
        backup "$OLD_XINITRC_LOG"
    fi

    if [ ! -d "$OLD_CORE" ]; then
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
    if echo "$current" | grep -q -e 'cec[-_]client\.sh' -e 'tv-power' \
        && ! echo "$current" | grep -qF "$REPO_DIR/bin/tv-power"; then
        mkdir -p "$BACKUP"
        echo "$current" > "$BACKUP/crontab"
        log "Backed up crontab to $BACKUP/crontab"
    fi
    install_crontab
}

check_remote_path() {
    local remote_path
    remote_path=$(sed -n "s/^export RCLONE_REMOTE_PATH='\{0,1\}\([^']*\)'\{0,1\}$/\1/p" "$BASHRC_FILE" 2>/dev/null | tail -n 1)
    if [ -z "$remote_path" ]; then
        log "Warning: RCLONE_REMOTE_PATH is not set in $BASHRC_FILE, so the default remote (kiosk-dropbox:/) will be used."
    elif [ "$remote_path" == "dropbox_kiosk:/path" ]; then
        log "Warning: RCLONE_REMOTE_PATH is still the example value '$remote_path'. Set the real folder in $BASHRC_FILE."
    fi
}

check_not_root
check_repo_location
migrate_remote_path
migrate_media
migrate_logs
migrate_dotfiles
install_tv_power
migrate_crontab
check_remote_path

[ -d "$BACKUP" ] && log "Backup of the old files: $BACKUP"
log "Migration complete. Reboot to start the kiosk with the new layout: sudo reboot"
