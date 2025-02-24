
# Installation Guide for Minimal FEH Setup with Rclone and CEC-Utils

## 1. Install Necessary Packages

Update your system and install the required packages:

```sh
sudo apt update
sudo apt install xorg x11-xserver-utils feh rclone cec-utils inotify-tools

```

## 2. Set Up Directory Structure

Create the required directories for configuration and media:

```sh
mkdir -p ~/.config/openbox
mkdir -p ~/media/feh
```

### Edit your `~/.bash_profile`:

```sh
nano ~/.bash_profile
```

Add the following lines to automatically start X on login without a cursor:

```bash
# Start X automatically if not already running
if [[ -z $DISPLAY && $XDG_VTNR -eq 1 ]]; then
  startx -- -nocursor
fi
```

## 3. Configure Rclone

Run the following command to configure `rclone`:

```sh
rclone config
```

Follow the interactive menu to set up your remote storage connection (Google Drive, Dropbox, etc.). Once configured, use the remote name and path in your `.xinitrc` file.


## 4. Configure `~/.xinitrc` for FEH Slideshow and CEC Power Management

Create or edit the `~/.xinitrc` file:

```sh
nano ~/.xinitrc
```

Add the following configuration to keep the screen active and start the slideshow:

```bash
# Disable screen saver and power management
xset s off
xset -dpms
xset s noblank

# Turn on display via HDMI-CEC
echo "on 0" | cec-client -s -d 1

# Function to start FEH slideshow
start_feh() {
  pkill feh  # Stop any running feh instances
  feh -recursive -Y -x -q -D 30 -B black -F -Z ~/media/feh &
}

# Function to synchronize media folder using rclone
sync_media() {
  echo "$(date): Starting rclone sync" >> ~/feh_sync.log
  rclone sync remote:path ~/media/feh --delete-during
}

# Initial synchronization and slideshow start
sync_media

# Check if images are present initially
if find ~/media/feh -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.bmp' \) | grep -q .; then
  start_feh
else
  # Display black screen if no images are found
  xsetroot -solid black &
fi

# Periodically check for new images on the server
while true; do
  # Run rclone sync every 5 minutes
  sleep 300
  sync_media

  # Check for new images and restart FEH if new images are found
  if find ~/media/feh -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.bmp' \) | grep -q .; then
    start_feh
  fi
done

```

### Make the X-init script executable:

```sh
chmod +x ~/.xinitrc
```

## 5. Reboot to Apply Changes

Restart the system to apply all changes:

```sh
sudo reboot
```

---

Crontab 
``` sh
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
```

## Expected Behavior

After reboot:
- The system will boot directly into a terminal.
- X will automatically start without a cursor.
- Media files will synchronize from your remote storage using `rclone`.
- HDMI-CEC will power on the display.
- `feh` will automatically start the slideshow and keep the display active.

---

## Additional Tips

- To verify if `rclone` is syncing correctly, run:

```sh
rclone ls remote:path
```

- To test HDMI-CEC commands manually:

```sh
echo "standby 0" | cec-client -s -d 1  # Turn off display
echo "on 0" | cec-client -s -d 1       # Turn on display
```
