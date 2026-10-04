#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

### VARIABLES ###
MEDIA_DIR="$HOME/media/feh"
XINITRC="$HOME/.xinitrc"
BASH_PROFILE="$HOME/.bash_profile"
LOG_FILE="$HOME/feh_sync.log"
HASH_FILE="$MEDIA_DIR/.last_hash"
REMOTE_PATH="dropbox_kiosk:/path"

### FUNCTIONS ###

install_dependencies() {
    echo "=== Installing necessary packages ==="
    sudo apt update && sudo apt full-upgrade -y
    sudo apt install -y xorg x11-xserver-utils feh rclone cec-utils jq
}

setup_media_directory() {
    echo "=== Setting up media directory ==="
    mkdir -p "$MEDIA_DIR"
    wget -q -O "$MEDIA_DIR/no-image.png" \
        "https://raw.githubusercontent.com/MonkeyEnterprise/kiosk-presenter/refs/heads/main/assets/no-image.png"
}

configure_bash_profile() {
    echo "=== Configuring ~/.bash_profile ==="

    # Append startx autostart only if it's not already present
    if ! grep -q 'startx' "$BASH_PROFILE"; then
        cat << 'EOF' >> "$BASH_PROFILE"

# Start X automatically if not already running
if [[ -z $DISPLAY && $XDG_VTNR -eq 1 ]]; then
    while true; do
        startx -- -nocursor
        sleep 5
    done
fi
EOF
    fi
}

create_xinitrc() {
    echo "=== Creating ~/.xinitrc ==="

    cat <<EOL > "$XINITRC"
#!/bin/bash
xset s off &
xset -dpms &
xset s noblank &

mkdir -p "$MEDIA_DIR"

# Function to synchronize media using rclone
sync_media() {
    echo "\$(date): Starting rclone sync" >> "$LOG_FILE"
    (rclone sync "$REMOTE_PATH" "$MEDIA_DIR" --exclude "*/**" --delete-during >> "$LOG_FILE" 2>&1 || true)
}

# Function to start the slideshow and restart on failure
start_feh() {
    echo "\$(date): Starting feh" >> "$LOG_FILE"
    while true; do
        feh -recursive -Y -x -q -D 30 -B black -F -Z "$MEDIA_DIR"
        sleep 5
    done
}

# Function to detect media changes and restart feh if needed
update_display_if_changed() {
    NEW_HASH=\$(ls -lR "$MEDIA_DIR" | sha256sum)

    if [ ! -f "$HASH_FILE" ]; then
        echo "$NEW_HASH" > "$HASH_FILE"
    fi

    OLD_HASH=\$(cat "$HASH_FILE")
    echo "\$(date): Old hash: \$OLD_HASH" >> "$LOG_FILE"
    echo "\$(date): New hash: \$NEW_HASH" >> "$LOG_FILE"

    if [ "\$NEW_HASH" != "\$OLD_HASH" ]; then
        echo "\$(date): Media changed, restarting feh" >> "$LOG_FILE"
        echo "\$NEW_HASH" > "$HASH_FILE"
        pkill -x feh
        start_feh &
    else
        echo "\$(date): No changes detected, feh continues running" >> "$LOG_FILE"
    fi

    if ! pgrep -x feh > /dev/null; then
        echo "\$(date): feh was not running, starting feh" >> "$LOG_FILE"
        start_feh &
    fi
}

# Initial sync and display update
sync_media
update_display_if_changed

# Sync and check for changes every 5 minutes
while true; do
    sleep 300
    sync_media
    update_display_if_changed
done
EOL

    chmod +x "$XINITRC"
}

setup_crontab() {
    echo "=== Setting up CEC power schedule in crontab ==="

    # Remove existing CEC commands
    crontab -l 2>/dev/null | grep -v "cec-client" | crontab -

    # Add new schedule
    (crontab -l 2>/dev/null; cat <<EOF
0 6 * * 1-5 echo 'on 0' | cec-client -s -d 1 >/dev/null 2>&1
0 9 * * 1-5 echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1
30 18 * * 3 echo 'on 0' | cec-client -s -d 1 >/dev/null 2>&1
0 20 * * 3 echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1
0 9 * * 7 echo 'on 0' | cec-client -s -d 1 >/dev/null 2>&1
30 13 * * 7 echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1
0 17 * * 7 echo 'on 0' | cec-client -s -d 1 >/dev/null 2>&1
30 19 * * 7 echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1
EOF
    ) | crontab -
}

prompt_rclone_setup() {
    read -p "Do you want to initialize rclone? (y/n) " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        rclone config
    fi
}

prompt_reboot() {
    read -p "Do you want to reboot? (y/n) " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "=== Rebooting system now... ==="
        sudo reboot now
    else
        echo "=== Setup complete. Please restart manually when ready. ==="
    fi
}

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
        sudo mv cloudflared /usr/local/bin/
        sudo chmod +x /usr/local/bin/cloudflared

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

        # Write new config.yml
        cat <<EOF | sudo tee "$config_file" > /dev/null
tunnel: "$tunnel_id"
credentials-file: "$credentials_file"
origincert: /root/.cloudflared/cert.pem
ingress:
  - hostname: "$tunnel_name.$domain_name"
    service: ssh://localhost:22
  - hostname: "*"
    service: http_status:404
EOF
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

    cat <<EOF | sudo tee "$update_script" > /dev/null
#!/bin/sh
# Installed by kiosk-presenter setup.sh: updates cloudflared and rolls back
# to the previous binary when the tunnel service does not come back.
BIN=/usr/local/bin/cloudflared
LOG=$log_file

echo "\$(date): checking for cloudflared update (\$(\$BIN --version 2>&1 | head -n 1))" >> "\$LOG"
cp "\$BIN" "\$BIN.bak"

"\$BIN" update >> "\$LOG" 2>&1
code=\$?

# Exit code 11 means a new version was installed
if [ "\$code" -ne 11 ]; then
    rm -f "\$BIN.bak"
    exit 0
fi

echo "\$(date): updated to \$(\$BIN --version 2>&1 | head -n 1), restarting tunnel" >> "\$LOG"
systemctl restart cloudflared
sleep 30

if systemctl is-active --quiet cloudflared; then
    echo "\$(date): tunnel running after update" >> "\$LOG"
    rm -f "\$BIN.bak"
else
    echo "\$(date): tunnel not running after update, restoring previous version" >> "\$LOG"
    mv "\$BIN.bak" "\$BIN"
    systemctl restart cloudflared
fi
EOF
    sudo chmod 755 "$update_script"

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

### MAIN EXECUTION ###
case "${1:-}" in
    "")
        install_dependencies
        setup_media_directory
        configure_bash_profile
        create_xinitrc
        setup_crontab
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
