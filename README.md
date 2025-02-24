
# **Installation Guide for Minimal FEH Setup with Rclone and CEC-Utils**

## 1. Install Necessary Packages

First, update your system and install all the required packages:

```sh
sudo apt update
sudo apt install -y xorg x11-xserver-utils feh rclone cec-utils inotify-tools
```

---

## 2. Set Up Directory Structure

Create the required directories for configuration and media:

```sh
mkdir -p ~/.config/openbox
mkdir -p ~/media/feh
```

---

### Edit Your `~/.bash_profile`

Configure X to automatically start without a cursor on login:

```sh
nano ~/.bash_profile
```

Add the following lines:

```bash
# Start X automatically if not already running
if [[ -z $DISPLAY && $XDG_VTNR -eq 1 ]]; then
  startx -- -nocursor
fi
```

Save and exit by pressing `CTRL+X`, then `Y`, and `Enter`.

---

## ☁3. Configure Rclone

Run the following command to configure `rclone`:

```sh
rclone config
```

Follow the interactive menu to set up your remote storage (Google Drive, Dropbox, etc.). After setup, note the remote name and path for use in your `.xinitrc`.

---

## 4. Configure `~/.xinitrc` for FEH Slideshow and CEC Power Management

Create or edit the `~/.xinitrc` file:

```sh
nano ~/.xinitrc
```

Add the following configuration:

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
  sleep 300  # Check every 5 minutes
  sync_media
  if find ~/media/feh -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.bmp' \) | grep -q .; then
    start_feh
  fi
done
```

Make the script executable:

```sh
chmod +x ~/.xinitrc
```

---

## 5. Reboot to Apply Changes

Restart the system to apply all changes:

```sh
sudo reboot
```

---

## 6. Configure Crontab for Scheduled HDMI-CEC Commands

Edit the crontab with:

```sh
crontab -e
```

Add the following tasks:

```sh
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

---

## **Expected Behavior**

After reboot:
- The system boots directly into a terminal.
- X will automatically start without a cursor.
- `rclone` will synchronize media files from remote storage.
- HDMI-CEC will power on the display automatically.
- `feh` will run a fullscreen slideshow and stay active.

---

## **Additional Tips**

- To verify if `rclone` is syncing correctly:

```sh
rclone ls remote:path
```

- To manually test HDMI-CEC commands:

```sh
echo "standby 0" | cec-client -s -d 1  # Turn off display
echo "on 0" | cec-client -s -d 1       # Turn on display
```
