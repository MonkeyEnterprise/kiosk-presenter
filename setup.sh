#!/bin/bash

echo "=== Updating system and installing necessary packages ==="
sudo apt update
sudo apt install -y xorg x11-xserver-utils feh rclone cec-utils inotify-tools

echo "=== Setting up directory structure ==="
mkdir -p ~/.config/openbox
mkdir -p ~/media/feh

echo "=== Configuring ~/.bash_profile ==="
if ! grep -q 'startx' ~/.bash_profile; then
  echo '# Start X automatically if not already running' >> ~/.bash_profile
  echo 'if [[ -z $DISPLAY && $XDG_VTNR -eq 1 ]]; then' >> ~/.bash_profile
  echo '  startx -- -nocursor' >> ~/.bash_profile
  echo 'fi' >> ~/.bash_profile
fi

echo "=== Reminder: Please run 'rclone config' manually to set up your remote storage ==="

echo "=== Creating and configuring ~/.xinitrc ==="
cat <<EOL > ~/.xinitrc
# Disable screen saver and power management
xset s off
xset -dpms
xset s noblank

# Turn on display via HDMI-CEC
echo "on 0" | cec-client -s -d 1

# Synchronize media folder using rclone
rclone sync remote:path ~/media/feh --delete-during

# Function to start FEH slideshow
start_feh() {
  pkill feh  # Stop any running feh instances
  feh -recursive -Y -x -q -D 30 -B black -F -Z ~/media/feh &
}

# Check if images are present initially
if find ~/media/feh -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.bmp' \) | grep -q .; then
  start_feh
else
  # Display black screen if no images are found
  xsetroot -solid black &
fi

# Monitor the folder for new images
inotifywait -m -e create -e moved_to --format '%f' ~/media/feh | while read FILENAME; do
  if echo "$FILENAME" | grep -Ei '\.(jpg|jpeg|png|bmp)$' > /dev/null; then
    start_feh
  fi
done
EOL

echo "=== Making ~/.xinitrc executable ==="
chmod +x ~/.xinitrc

echo "=== Setting up crontab with direct CEC commands ==="
(crontab -l 2>/dev/null; echo "0 6 * * 1-5 echo 'on 0' | cec-client -s -d 1 >/dev/null 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 9 * * 1-5 echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "30 18 * * 3 echo 'on 0' | cec-client -s -d 1 >/dev/null 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 20 * * 3 echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 9 * * 7 echo 'on 0' | cec-client -s -d 1 >/dev/null 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "30 13 * * 7 echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 17 * * 7 echo 'on 0' | cec-client -s -d 1 >/dev/null 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "30 19 * * 7 echo 'standby 0' | cec-client -s -d 1 >/dev/null 2>&1") | crontab -

echo "=== Setup complete. Please run 'rclone config' manually if you haven't done so yet. ==="
echo "=== The system will reboot now to apply all changes. ==="
sudo reboot
