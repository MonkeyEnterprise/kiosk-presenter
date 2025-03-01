#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

### VARIABLES ###
MEDIA_DIR="$HOME/media/feh"
CONFIG_DIR="$HOME/.config/openbox"
XINITRC="$HOME/.xinitrc"
BASH_PROFILE="$HOME/.bash_profile"
LOG_FILE="$HOME/feh_sync.log"
REMOTE_PATH="dropbox_kiosk:path"

### FUNCTIONS ###
install_packages() {
    echo "=== Updating system and installing necessary packages ==="
    sudo apt update
    sudo apt install -y xorg x11-xserver-utils feh rclone cec-utils inotify-tools
}

setup_directories() {
    echo "=== Setting up directory structure ==="
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$MEDIA_DIR"
    wget https://raw.githubusercontent.com/MonkeyEnterprise/kiosk-presenter/refs/heads/main/assets/no-image.png
}

configure_bash_profile() {
    echo "=== Configuring ~/.bash_profile ==="
    if ! grep -q 'startx' "$BASH_PROFILE"; then
        echo -e '\n# Start X automatically if not already running' >> "$BASH_PROFILE"
        echo 'if [[ -z $DISPLAY && $XDG_VTNR -eq 1 ]]; then' >> "$BASH_PROFILE"
        echo '  startx -- -nocursor' >> "$BASH_PROFILE"
        echo 'fi' >> "$BASH_PROFILE"
    fi
}

configure_xinitrc() {
    echo "=== Creating and configuring ~/.xinitrc ==="
    cat <<EOL > "$XINITRC"
# Disable screen saver and power management
xset s off
xset -dpms
xset s noblank

# Turn on display via HDMI-CEC
echo "on 0" | cec-client -s -d 1

# Function to start FEH slideshow
start_feh() {
  feh -recursive -Y -x -q -D 30 -B black -F -Z "$MEDIA_DIR" &
}

# Function to synchronize media folder using rclone
sync_media() {
  echo "$(date): Starting rclone sync" >> "$LOG_FILE"
  rclone sync "$REMOTE_PATH" "$MEDIA_DIR" --delete-during
}

# Function to check if images exist and start feh accordingly
update_display() {
  if find "$MEDIA_DIR" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.bmp' \) | grep -q .; then
    # Kill existing feh instances before starting a new one
    pkill -x feh
    start_feh
  else
    # Kill feh if no images are found and set black background
    pkill -x feh
    xsetroot -solid black &
  fi
}

# Initial synchronization and slideshow start
sync_media
update_display

# Periodically check for new images on the server
while true; do
  sleep 600  # Check every 10 minutes
  sync_media
  update_display
done
EOL

    chmod +x "$XINITRC"
}

setup_cron_jobs() {
    echo "=== Setting up crontab with direct CEC commands ==="
    crontab -l 2>/dev/null | grep -v "cec-client" | crontab -  # Remove old CEC jobs
    (crontab -l 2>/dev/null; cat <<EOL
# Prayer sessions from Monday to Friday
0 6 * * 1-5 echo "on 0" | cec-client -s -d 1 >/dev/null 2>&1
0 9 * * 1-5 echo "standby 0" | cec-client -s -d 1 >/dev/null 2>&1

# Wednesday evening
30 18 * * 3 echo "on 0" | cec-client -s -d 1 >/dev/null 2>&1
0 20 * * 3 echo "standby 0" | cec-client -s -d 1 >/dev/null 2>&1

# Sunday morning
0 9 * * 7 echo "on 0" | cec-client -s -d 1 >/dev/null 2>&1
30 13 * * 7 echo "standby 0" | cec-client -s -d 1 >/dev/null 2>&1

# Sunday evening
0 17 * * 7 echo "on 0" | cec-client -s -d 1 >/dev/null 2>&1
30 19 * * 7 echo "standby 0" | cec-client -s -d 1 >/dev/null 2>&1
EOL
    ) | crontab -
}

initialize_rclone() {
    read -p "Do you want to initialize rclone? (y/n) " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        rclone config
    fi
}

### MAIN EXECUTION ###
install_packages
setup_directories
configure_bash_profile
configure_xinitrc
setup_cron_jobs
initialize_rclone

echo "=== Setup complete. System will now reboot. ==="
read -p "Do you want to reboot? (y/n) " choice
if [[ "$choice" =~ ^[Yy]$ ]]; then
  sudo reboot
fi
