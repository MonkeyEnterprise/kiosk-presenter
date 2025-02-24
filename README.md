
# Installation Guide for Minimal FEH Setup with Rclone and CEC-Utils

## 1. Install Necessary Packages

Update your system and install the required packages:

```sh
sudo apt update
sudo apt install xorg x11-xserver-utils feh rclone cec-utils
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

# Synchronize media folder using rclone (replace 'remote:path' with your actual rclone config)
rclone sync remote:path ~/media/feh --delete-during

# Start FEH slideshow
feh -recursive -Y -x -q -D 30 -B black -F -Z ~/media/feh
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
