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
        if ! cloudflared tunnel route dns "$tunnel_id" "$tunnel_name.$domain_name"; then
            echo "cloudflared tunnel routing failed."
            return 1
        fi
        echo "cloudflared tunnel '$tunnel_name' routed successfully to '$tunnel_name.$domain_name'."

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
    fi
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

### MAIN EXECUTION ###
install_dependencies
setup_media_directory
configure_bash_profile
create_xinitrc
setup_crontab
prompt_cloudflared_setup
prompt_rclone_setup
prompt_reboot
