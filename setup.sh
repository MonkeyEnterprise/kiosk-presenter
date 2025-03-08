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
    sudo apt install -y xorg x11-xserver-utils feh rclone cec-utils
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

### MAIN EXECUTION ###
install_dependencies
setup_media_directory
configure_bash_profile
create_xinitrc
setup_crontab
prompt_rclone_setup
prompt_reboot
