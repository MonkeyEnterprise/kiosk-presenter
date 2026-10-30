#!/bin/bash

# =============================================================================
# Kiosk Migration Script
# -----------------------------------------------------------------------------
# Moves a kiosk from one of the older layouts to the current one:
#
#   ~/kiosk-presenter         git clone of this repository
#   ~/media                   synced media
#   /var/log/kiosk-presenter  logs
#   ~/.cache/kiosk-presenter  hash cache and placeholder
#
# Older layouts it recognizes:
# - xinitrc layout: the whole sync loop in ~/.xinitrc (with REMOTE_PATH in
#   it), media in ~/media/feh, log in ~/feh_sync.log, a copy of tv-power in
#   /usr/local/bin.
# - core layout: scripts, logs and cache in ~/core, media in ~/feh, cron
#   jobs calling ~/core/cec_client.sh (or cec-client.sh). The remote is
#   either RCLONE_REMOTE_PATH in ~/.bashrc or written out in ~/.xinitrc as
#   --remote_path "remote:path".
# - logs in ~/logs: the current layout before the logs moved to /var/log.
#
# Steps performed by this script:
# 1. Moves the remote from an old ~/.xinitrc (REMOTE_PATH="..." or
#    --remote_path "...") to RCLONE_REMOTE_PATH in ~/.bashrc.
# 2. Moves the media to ~/media, so it doesn't have to be downloaded again.
# 3. Moves the logs from ~/core or ~/logs to /var/log/kiosk-presenter, and
#    ~/core to the backup directory.
# 4. Replaces ~/.xinitrc and ~/.bash_profile with links to the repository.
# 5. Links /usr/local/bin/tv-power to the repository and replaces the TV power
#    cron jobs. The kiosk keeps its own schedule: the times of its old jobs
#    are written to ~/tv-power.cron, which setup.sh then uses instead of the
#    default config/tv-power.cron.
# 6. Installs log rotation (/etc/logrotate.d/kiosk-presenter).
# 7. Makes /usr/local/bin/cloudflared owned by root again (older setups left
#    it owned by the kiosk user, while root runs it).
#
# Everything that is replaced is kept in ~/kiosk-backup-<date>. Running the
# script again on a migrated kiosk changes nothing. The tunnel configuration
# is left alone.
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
OLD_LOGS="$HOME/logs"
BACKUP="$HOME/kiosk-backup-$(date "+%Y%m%d-%H%M%S")"

# Create the backup directory on first use, so a run with nothing to back up
# leaves no empty directory behind
backup() {
    mkdir -p "$BACKUP"
    mv "$1" "$BACKUP/"
    log "Moved $1 to $BACKUP/"
}

# Older layouts kept the remote in ~/.xinitrc, as REMOTE_PATH="..." (xinitrc
# layout) or as --remote_path "..." on the exec line (some core layout
# kiosks); the current dotfiles read RCLONE_REMOTE_PATH from ~/.bashrc instead
migrate_remote_path() {
    if [ -L "$HOME/.xinitrc" ] || [ ! -f "$HOME/.xinitrc" ]; then
        return 0
    fi

    local remote_path
    remote_path=$(sed -n 's/^REMOTE_PATH="\(.*\)"$/\1/p' "$HOME/.xinitrc" | head -n 1)
    if [ -z "$remote_path" ]; then
        # Quoted ("remote:My Folder") or not; a variable such as
        # "$RCLONE_REMOTE_PATH" is skipped, that one is already in ~/.bashrc
        remote_path=$(grep -v '^\s*#' "$HOME/.xinitrc" | sed -n \
            -e 's/.*--remote_path[ =]"\([^"$][^"]*\)".*/\1/p' \
            -e 's/.*--remote_path[ =]\([^"$ ][^ ]*\).*/\1/p' | head -n 1)
    fi
    if [ -z "$remote_path" ]; then
        return 0
    fi

    if grep -q '^export RCLONE_REMOTE_PATH=' "$BASHRC_FILE" 2>/dev/null; then
        log "RCLONE_REMOTE_PATH is already set in $BASHRC_FILE, ignoring $remote_path from ~/.xinitrc."
    else
        save_remote_path "$remote_path"
    fi
}

migrate_media() {
    if [ -d "$OLD_XINITRC_MEDIA" ]; then
        # The hash file is recreated by kiosk_client.sh
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

    install_log_dir

    # Logs from ~/core (core layout) or ~/logs (before /var/log). Current logs
    # are appended, rotated ones (.log.1, .log.2.gz) moved unless already there.
    local dir file
    for dir in "$OLD_CORE" "$OLD_LOGS"; do
        [ -d "$dir" ] || continue
        for file in "$dir"/*.log "$dir"/*.log.*; do
            [ -f "$file" ] || continue
            if [[ "$file" == *.log ]]; then
                cat "$file" >> "$KIOSK_LOG_DIR_DEFAULT/$(basename "$file")" && rm "$file"
            else
                mv -n "$file" "$KIOSK_LOG_DIR_DEFAULT/"
            fi
            log "Moved $file to $KIOSK_LOG_DIR_DEFAULT/"
        done

        # The hash cache and the placeholder are recreated by kiosk_client.sh
        rm -f "$dir/.cache" "$dir/placeholder.svg"
    done

    if [ -d "$OLD_CORE" ]; then
        backup "$OLD_CORE"
    fi
    if [ -d "$OLD_LOGS" ]; then
        rmdir "$OLD_LOGS" 2> /dev/null || backup "$OLD_LOGS"
    fi
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

# Write the times of the old TV power jobs to ~/tv-power.cron, so the kiosk
# keeps its own schedule. "on 0" and "on" become 'tv-power on', "standby 0"
# and "off" become 'tv-power off'.
save_old_schedule() {
    local current="$1"
    if [ -f "$KIOSK_SCHEDULE" ]; then
        log "$KIOSK_SCHEDULE already exists, keeping it."
        return 0
    fi

    local jobs
    jobs=$(echo "$current" | grep -v '^\s*#' | grep -e 'cec[-_]client\.sh' -e 'tv-power' | awk '
        {
            schedule = $1 " " $2 " " $3 " " $4 " " $5
            if ($0 ~ /standby|tv-power off/) action = "off"
            else if ($0 ~ /"on|tv-power on/) action = "on"
            else next
            print schedule " __BIN__/tv-power " action " >/dev/null 2>&1"
        }')
    if [ -z "$jobs" ]; then
        return 0
    fi

    {
        echo "# Display power schedule of this kiosk, taken over from its old crontab by"
        echo "# migrate.sh. setup.sh uses this file instead of config/tv-power.cron."
        echo "# __BIN__ is replaced with the repository's bin/ directory."
        echo "$jobs"
    } > "$KIOSK_SCHEDULE"
    log "Kept this kiosk's schedule ($(echo "$jobs" | wc -l | tr -d " ") jobs) in $KIOSK_SCHEDULE"
}

migrate_crontab() {
    local current
    current=$(crontab -l 2>/dev/null)
    if echo "$current" | grep -q -e 'cec[-_]client\.sh' -e 'tv-power' \
        && ! echo "$current" | grep -qF "$REPO_DIR/bin/tv-power"; then
        mkdir -p "$BACKUP"
        echo "$current" > "$BACKUP/crontab"
        log "Backed up crontab to $BACKUP/crontab"
        save_old_schedule "$current"

        # Drop the comments of the old crontab: they describe the old TV jobs.
        # The full old crontab is in the backup.
        echo "$current" | grep -v -e '^\s*#' -e '^+#' -e '^\s*$' | crontab -
    fi
    install_crontab
}

# Root runs cloudflared (service and nightly update), so the kiosk user must
# not own the binary
fix_cloudflared_owner() {
    local bin="/usr/local/bin/cloudflared"
    if [ -f "$bin" ] && [ "$(stat -c %u "$bin")" != "0" ]; then
        sudo chown root:root "$bin"
        log "$bin is now owned by root."
    fi
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
install_logrotate
fix_cloudflared_owner
check_remote_path

[ -d "$BACKUP" ] && log "Backup of the old files: $BACKUP"
log "Migration complete. Reboot to start the kiosk with the new layout: sudo reboot"
