#!/bin/bash

# =============================================================================
# Kiosk Media Sync & Display Setup
# -----------------------------------------------------------------------------
# Installs the kiosk: packages, dotfiles, the TV power schedule, an optional
# Cloudflare Tunnel and the rclone remote. Also manages the tunnel afterwards
# (see ./setup.sh help).
#
# Usage:
# - Run as the kiosk user, not with sudo; it calls sudo itself where needed.
# - From a clone in ~/kiosk-presenter:  ./setup.sh [command]
# - Downloaded on its own (wget), it clones the repository to
#   ~/kiosk-presenter first and continues from there.
# - migrate.sh sources this file to reuse its install functions; the main
#   steps only run when the script is executed directly.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# Ensure the correct path for .bashrc
BASHRC_FILE="$HOME/.bashrc"

# Repository location. dotfiles/xinitrc expects it at ~/kiosk-presenter.
REPO_URL="https://github.com/MonkeyEnterprise/kiosk-presenter.git"
REPO_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
EXPECTED_REPO_DIR="$HOME/kiosk-presenter"

# =============================================================================
# Helper Functions
# =============================================================================

# Logging function to timestamp messages
log() {
    local msg="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$timestamp - $msg"
}

# Make sure the script runs as the kiosk user, so the dotfiles, crontab and
# rclone config end up in that user's home instead of root's
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "Do not run this script with sudo. Run it as the kiosk user; it asks for sudo when needed."
        exit 1
    fi
}

# Make sure the repository is where dotfiles/xinitrc expects it
check_repo_location() {
    if [ "$REPO_DIR" != "$EXPECTED_REPO_DIR" ]; then
        echo "The repository must be at $EXPECTED_REPO_DIR (it is at $REPO_DIR)."
        echo "Clone it with: git clone $REPO_URL $EXPECTED_REPO_DIR"
        exit 1
    fi
}

# When setup.sh was downloaded on its own, clone the repository (or update an
# existing clone) and continue with the setup.sh in there
bootstrap_repo() {
    if [ -f "$REPO_DIR/bin/kiosk_client.sh" ]; then
        return 0
    fi

    if ! command -v git > /dev/null; then
        log "Installing git..."
        sudo apt update && sudo apt install -y git
    fi

    if [ -d "$EXPECTED_REPO_DIR/.git" ]; then
        log "Updating $EXPECTED_REPO_DIR..."
        git -C "$EXPECTED_REPO_DIR" pull --ff-only
    else
        log "Cloning $REPO_URL to $EXPECTED_REPO_DIR..."
        git clone "$REPO_URL" "$EXPECTED_REPO_DIR"
    fi

    exec "$EXPECTED_REPO_DIR/setup.sh" "$@"
}

# =============================================================================
# Install Dependencies
# =============================================================================

# Non-interactive, so apt doesn't stop to ask e.g. for a keyboard layout.
# cron is listed because minimal Debian images don't include it.
install_dependencies() {
    log "Installing necessary packages..."
    sudo apt update
    sudo env DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
    sudo env DEBIAN_FRONTEND=noninteractive apt install -y xorg x11-xserver-utils feh rclone cec-utils jq git cron
}

# =============================================================================
# Dotfiles and TV power
# =============================================================================

# Link a dotfile from the repository into the home directory, so a git pull
# also updates it. An existing file that isn't this link is kept as <file>.bak.
link_dotfile() {
    local name="$1"
    local source_file="$REPO_DIR/dotfiles/$name"
    local dest_file="$HOME/.$name"

    if [ ! -f "$source_file" ]; then
        log "Source file $source_file does not exist."
        return 1
    fi

    if [ "$(readlink "$dest_file")" == "$source_file" ]; then
        log "$dest_file is already linked."
        return 0
    fi

    if [ -e "$dest_file" ] || [ -L "$dest_file" ]; then
        mv "$dest_file" "$dest_file.bak"
        log "Existing $dest_file moved to $dest_file.bak"
    fi

    ln -s "$source_file" "$dest_file"
    log "$dest_file now links to $source_file"
}

install_dotfiles() {
    link_dotfile xinitrc
    link_dotfile bash_profile
}

# Make 'tv-power on|off' available on the command line
install_tv_power() {
    sudo ln -sfn "$REPO_DIR/bin/tv-power" /usr/local/bin/tv-power
    log "/usr/local/bin/tv-power now links to $REPO_DIR/bin/tv-power"
}

# Display power schedule of this kiosk: ~/tv-power.cron when it exists (a
# schedule of its own, e.g. taken over by migrate.sh), else the default
# config/tv-power.cron
KIOSK_SCHEDULE="$HOME/tv-power.cron"

tv_power_schedule() {
    if [ -f "$KIOSK_SCHEDULE" ]; then
        echo "$KIOSK_SCHEDULE"
    else
        echo "$REPO_DIR/config/tv-power.cron"
    fi
}

# Install the display power schedule. Existing TV power entries (tv-power,
# and cec_client.sh from older installs) are replaced, other cron jobs are
# kept.
install_crontab() {
    local schedule
    schedule=$(tv_power_schedule)
    crontab -l 2>/dev/null | grep -v -e 'cec[-_]client\.sh' -e 'tv-power' | {
        cat
        sed -e '/^#/d' -e "s|__BIN__|$REPO_DIR/bin|g" "$schedule"
    } | crontab -
    log "TV power schedule from $schedule installed in crontab."
}

# =============================================================================
# Rclone Setup
# =============================================================================

# Store the remote path in ~/.bashrc, replacing an earlier one.
# dotfiles/bash_profile loads it before X starts.
save_remote_path() {
    local remote_path="$1"
    touch "$BASHRC_FILE"
    sed -i '/^export RCLONE_REMOTE_PATH=/d' "$BASHRC_FILE"
    echo "export RCLONE_REMOTE_PATH='$remote_path'" >> "$BASHRC_FILE"
    log "RCLONE_REMOTE_PATH is now set to: $remote_path"
}

prompt_rclone_setup() {
    read -p "Do you want to initialize rclone? (y/n) " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        return 0
    fi

    rclone config

    echo "Configured remotes:"
    rclone listremotes
    read -p "Enter the folder to show, as remote:path (e.g., dropbox_kiosk:/Kiosks/Kiosk4): " remote_path
    if [ -z "$remote_path" ]; then
        echo "No path entered. Set it later with: export RCLONE_REMOTE_PATH='remote:path' in $BASHRC_FILE"
        return 0
    fi
    save_remote_path "$remote_path"
}

prompt_reboot() {
    read -p "Do you want to reboot? (y/n) " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        log "Rebooting system now..."
        sudo reboot now
    else
        log "Setup complete. Please restart manually when ready."
    fi
}

# =============================================================================
# Cloudflared Setup
# =============================================================================

prompt_cloudflared_setup() {
    read -p "Do you want to initialize cloudflared? (y/n) " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        # Detect architecture
        arch=$(uname -m)
        case "$arch" in
            aarch64|arm64) asset="cloudflared-linux-arm64" ;;
            x86_64|amd64) asset="cloudflared-linux-amd64" ;;
            *) echo "Unsupported architecture: $arch"; return 1 ;;
        esac
        
        # Fetch the latest release URL
        url=$(wget -qO- https://api.github.com/repos/cloudflare/cloudflared/releases/latest | \
              grep browser_download_url | grep "$asset\"" | cut -d '"' -f 4)
        if [ -z "$url" ]; then
            echo "Could not find the download link for cloudflared ($asset)."
            return 1
        fi

        # Download and install cloudflared
        if ! wget -O cloudflared "$url"; then
            echo "Failed to download cloudflared."
            return 1
        fi
        # Owned by root: root runs it (service and nightly update), so the kiosk
        # user must not be able to replace it
        sudo install -m 755 -o root -g root cloudflared /usr/local/bin/cloudflared
        rm -f cloudflared

        # Verify install
        if ! cloudflared --version > /dev/null 2>&1; then
            echo "cloudflared installation failed."
            return 1
        fi
        echo "cloudflared installed successfully."

        # Login
        if ! cloudflared tunnel login; then
            echo "cloudflared login failed."
            return 1
        fi
        echo "cloudflared login successful."

        # Tunnel creation
        read -p "Enter a name for your tunnel: " tunnel_name
        cloudflared tunnel create "$tunnel_name"

        # Retrieve tunnel ID via JSON
        tunnel_id=$(cloudflared tunnel list --output json | jq -r ".[] | select(.name==\"$tunnel_name\") | .id")
        if [ -z "$tunnel_id" ] || [ "$tunnel_id" == "null" ]; then
            echo "Failed to retrieve tunnel ID for $tunnel_name"
            return 1
        fi

        echo "cloudflared tunnel '$tunnel_name' created successfully with ID: $tunnel_id."

        # Domain input
        read -p "Enter the domain name you want to use for the tunnel (e.g., example.com): " domain_name

        # DNS route
        if ! route_dns "$tunnel_id" "$tunnel_name.$domain_name"; then
            return 1
        fi

        # ---- CONFIG in /etc/cloudflared ----
        config_dir="/etc/cloudflared"
        sudo mkdir -p "$config_dir"
        config_file="$config_dir/config.yml"
        credentials_file="$config_dir/${tunnel_id}.json"

        # Copy credentials file from root’s cloudflared dir
        if [ -f "$HOME/.cloudflared/${tunnel_id}.json" ]; then
            sudo cp "$HOME/.cloudflared/${tunnel_id}.json" "$credentials_file"
        else
            echo "Credentials file not found in $HOME/.cloudflared/"
            return 1
        fi

        # Remove conflicting configs if exist
        if [ -f /etc/cloudflared/config.yml ]; then
            echo "Removing old /etc/cloudflared/config.yml..."
            sudo rm /etc/cloudflared/config.yml
        fi

        # Write new config.yml from the template
        local template
        template="$REPO_DIR/config/cloudflared-config.yml"
        sed -e "s|__TUNNEL_ID__|$tunnel_id|" \
            -e "s|__CREDENTIALS_FILE__|$credentials_file|" \
            -e "s|__HOSTNAME__|$tunnel_name.$domain_name|" \
            "$template" | sudo tee "$config_file" > /dev/null
        echo "Generated $config_file for tunnel '$tunnel_name' with domain '$tunnel_name.$domain_name'."

        # Service install
        if ! sudo cloudflared --config "$config_file" service install; then
            echo "Failed to install cloudflared service."
            return 1
        fi
        sudo systemctl enable cloudflared --now
        echo "cloudflared service installed and enabled successfully."

        setup_cloudflared_update
    fi
}

# Update cloudflared nightly from root's crontab. If the tunnel does not come
# back after an update, the previous binary is restored, so the device stays
# reachable.
setup_cloudflared_update() {
    local update_script="/usr/local/bin/cloudflared-auto-update"
    local log_file="/var/log/cloudflared-update.log"

    echo "=== Setting up nightly cloudflared update in root's crontab ==="

    sudo install -m 755 "$REPO_DIR/bin/cloudflared-auto-update" "$update_script"

    # One updater is enough: the cloudflared-update.timer from 'service install' is replaced by the cron job
    sudo systemctl disable --now cloudflared-update.timer 2>/dev/null || true

    # Replace any existing entry, then update every night at 04:00
    (sudo crontab -l 2>/dev/null | grep -v "$update_script" || true
     echo "0 4 * * * $update_script") | sudo crontab -

    echo "cloudflared is updated nightly at 04:00 (log: $log_file)."
}

cleanup_cloudflared() {
    echo "Cleaning up all cloudflared data, services, and configs..."

    # Stop and disable all cloudflared services and timers
    sudo systemctl stop cloudflared cloudflared-update cloudflared-update.timer 2>/dev/null || true
    sudo systemctl disable cloudflared cloudflared-update cloudflared-update.timer 2>/dev/null || true

    # Remove systemd service and timer files
    sudo rm -f /etc/systemd/system/cloudflared.service
    sudo rm -f /etc/systemd/system/cloudflared-update.service
    sudo rm -f /etc/systemd/system/cloudflared-update.timer

    # Reload systemd to apply changes
    sudo systemctl daemon-reload
    sudo systemctl reset-failed

    # Remove the nightly update job
    (sudo crontab -l 2>/dev/null | grep -v "cloudflared-auto-update" || true) | sudo crontab -
    sudo rm -f /usr/local/bin/cloudflared-auto-update

    # Remove cloudflared binary
    if [ -f /usr/local/bin/cloudflared ]; then
        echo "Removing cloudflared binary..."
        sudo rm -f /usr/local/bin/cloudflared
    fi

    # Remove all cloudflared configuration directories
    echo "Removing cloudflared configuration directories..."
    sudo rm -rf /etc/cloudflared
    sudo rm -rf /root/.cloudflared
    sudo rm -rf "$HOME/.cloudflared"

    echo "Cleanup complete. System is ready for a fresh cloudflared installation."
}

# Create the DNS record for a tunnel hostname.
# 'cloudflared tunnel route dns' only works for the domain chosen during
# 'cloudflared tunnel login' (the zone in cert.pem). For any other domain it
# creates a wrong record such as 'pi1.new.com.old.app', so the CNAME has to
# be added in the Cloudflare dashboard instead.
route_dns() {
    local tunnel_id="$1"
    local hostname="$2"

    read -p "Is the domain of '$hostname' the one you selected during 'cloudflared tunnel login'? (y/n) " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        if ! cloudflared tunnel route dns "$tunnel_id" "$hostname"; then
            echo "cloudflared tunnel routing failed."
            return 1
        fi
        echo "Tunnel routed successfully to '$hostname'."
    else
        echo
        echo "Add this DNS record in the Cloudflare dashboard (zone of '$hostname'):"
        echo "  Type:   CNAME"
        echo "  Name:   $hostname"
        echo "  Target: $tunnel_id.cfargotunnel.com"
        echo "  Proxy:  Proxied (orange cloud)"
        echo
        read -p "Press Enter when the record has been added... "
    fi
}

# Restart cloudflared with a safety net: if the new config locks you out,
# the previous config is restored automatically after 5 minutes.
restart_cloudflared_with_rollback() {
    local config_file="$1"
    local backup_file="$2"

    sudo systemctl stop cf-rollback.timer 2>/dev/null || true
    sudo systemctl reset-failed cf-rollback.service 2>/dev/null || true
    sudo systemd-run --quiet --unit=cf-rollback --on-active=5min \
        /bin/sh -c "cp '$backup_file' '$config_file' && systemctl restart cloudflared"

    echo
    echo "Restarting cloudflared. An SSH session through the tunnel will drop now."
    echo "The previous config is restored automatically in 5 minutes."
    echo "After logging in again through the new hostname, keep the change with:"
    echo "  sudo systemctl stop cf-rollback.timer"
    echo
    sudo systemctl restart cloudflared
}

# Validate the edited config; restore the backup when it is invalid.
validate_cloudflared_config() {
    local config_file="$1"
    local backup_file="$2"

    if ! sudo cloudflared tunnel --config "$config_file" ingress validate; then
        echo "The new config is invalid, restoring the previous one."
        sudo cp "$backup_file" "$config_file"
        return 1
    fi
}

read_hostname() {
    local prompt="$1"
    read -p "$prompt" hostname
    if [[ ! "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
        echo "Invalid hostname: '$hostname'"
        return 1
    fi
}

# Add an extra hostname to the existing tunnel (e.g. when moving to a new
# domain). The existing hostnames keep working, so you can test the new one
# before removing the old one.
add_cloudflared_hostname() {
    local config_file="/etc/cloudflared/config.yml"
    local backup_file="$config_file.bak"

    if [ ! -f "$config_file" ]; then
        echo "$config_file not found. Set up cloudflared first."
        return 1
    fi

    local tunnel_id
    tunnel_id=$(sudo sed -n 's/^tunnel: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$config_file")
    if [ -z "$tunnel_id" ]; then
        echo "Could not read the tunnel ID from $config_file."
        return 1
    fi

    echo "Current hostnames:"
    sudo grep 'hostname:' "$config_file" | grep -v '"\*"' | sed 's/^ *- hostname: */  /'

    if ! sudo grep -qF 'hostname: "*"' "$config_file"; then
        echo "Catch-all rule (hostname: \"*\") not found in $config_file."
        return 1
    fi

    read_hostname "Enter the new hostname (e.g., pi1.example.com): " || return 1
    if sudo grep -qF "hostname: \"$hostname\"" "$config_file"; then
        echo "'$hostname' is already in $config_file."
        return 1
    fi

    if ! route_dns "$tunnel_id" "$hostname"; then
        return 1
    fi

    # Insert the new rule before the catch-all rule
    sudo cp "$config_file" "$backup_file"
    sudo awk -v host="$hostname" '
        /^ *- hostname: "\*"/ && !done {
            print "  - hostname: \"" host "\""
            print "    service: ssh://localhost:22"
            done = 1
        }
        { print }
    ' "$backup_file" | sudo tee "$config_file" > /dev/null

    validate_cloudflared_config "$config_file" "$backup_file" || return 1
    echo "Added '$hostname' to $config_file."
    restart_cloudflared_with_rollback "$config_file" "$backup_file"
}

# Remove a hostname from the tunnel (e.g. the old domain after a move).
# Remove its DNS record in the Cloudflare dashboard afterwards.
remove_cloudflared_hostname() {
    local config_file="/etc/cloudflared/config.yml"
    local backup_file="$config_file.bak"

    if [ ! -f "$config_file" ]; then
        echo "$config_file not found."
        return 1
    fi

    echo "Current hostnames:"
    sudo grep 'hostname:' "$config_file" | grep -v '"\*"' | sed 's/^ *- hostname: */  /'

    read_hostname "Enter the hostname to remove: " || return 1
    if ! sudo grep -qF "hostname: \"$hostname\"" "$config_file"; then
        echo "'$hostname' is not in $config_file."
        return 1
    fi
    if [ "$(sudo grep 'hostname:' "$config_file" | grep -vc '"\*"')" -le 1 ]; then
        echo "'$hostname' is the last hostname; removing it would lock you out."
        return 1
    fi

    # Drop the hostname line and the service line that follows it
    sudo cp "$config_file" "$backup_file"
    sudo awk -v host="$hostname" '
        skip { skip = 0; next }
        {
            line = $0
            sub(/^ +/, "", line)
            sub(/ +$/, "", line)
            if (line == "- hostname: \"" host "\"") { skip = 1; next }
        }
        { print }
    ' "$backup_file" | sudo tee "$config_file" > /dev/null

    validate_cloudflared_config "$config_file" "$backup_file" || return 1
    echo "Removed '$hostname' from $config_file."
    echo "Remember to delete its DNS record in the Cloudflare dashboard."
    restart_cloudflared_with_rollback "$config_file" "$backup_file"
}

# =============================================================================
# Main Script Execution
# =============================================================================

usage() {
    echo "Usage: $0 [command]"
    echo
    echo "Without a command the full kiosk installation runs."
    echo
    echo "Commands:"
    echo "  add-hostname         Add a hostname to the existing cloudflared tunnel"
    echo "  remove-hostname      Remove a hostname from the cloudflared tunnel"
    echo "  setup-update         Update cloudflared nightly (root crontab, 04:00)"
    echo "  cleanup-cloudflared  Remove cloudflared completely (tunnel access is lost!)"
}

main() {
    check_not_root
    bootstrap_repo "$@"
    check_repo_location

    case "${1:-}" in
        "")
            set -e
            install_dependencies
            install_dotfiles
            install_tv_power
            install_crontab
            prompt_cloudflared_setup
            prompt_rclone_setup
            prompt_reboot
            ;;
        add-hostname)
            add_cloudflared_hostname
            ;;
        remove-hostname)
            remove_cloudflared_hostname
            ;;
        setup-update)
            setup_cloudflared_update
            ;;
        cleanup-cloudflared)
            read -p "This removes cloudflared and all tunnel credentials from this device. Continue? (y/n) " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                cleanup_cloudflared
            fi
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Only run when executed directly, not when sourced by migrate.sh
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
