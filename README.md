# Kiosk Presenter for Raspberry Pi

<p align="center"> <img src="https://upload.wikimedia.org/wikipedia/en/thumb/c/cb/Raspberry_Pi_Logo.svg/200px-Raspberry_Pi_Logo.svg.png" width="15%"> </p>

This script sets up a minimal digital signage system on Raspberry Pi 3, 4, and 5. It enables fullscreen image slideshows using `feh`, synchronizes media via `rclone`, and manages display power with `cec-utils`.

## Features

- **Fullscreen Slideshow**: Displays images with `feh`, automatically updating when new images are added.
- **Remote Sync**: Synchronizes images from cloud storage (Google Drive, Dropbox, etc.) using `rclone`.
- **HDMI-CEC Control**: Automatically turns the display on/off using `cec-utils`.
- **Real-Time Monitoring**: Detects new images and updates the slideshow accordingly.
- **Scheduled Power Management**: Manages display power via `cron` jobs.
-  **Media files sync every 10 minutes (max 20 images x 30 seconds).**

## Installation

To install, run the setup script using `wget`:

```bash
wget https://raw.githubusercontent.com/MonkeyEnterprise/kiosk-presenter/refs/heads/main/setup.sh -O setup.sh
chmod +x setup.sh
./setup.sh
```

Alternatively, use `git`:

```bash
git clone https://github.com/MonkeyEnterprise/kiosk-presenter.git ~/kiosk-presenter
chmod +x ~/kiosk-presenter/setup.sh
. ~/kiosk-presenter/setup.sh
```

### Configuring `rclone`

Follow the prompts to configure `rclone`:

```bash
rclone config
```

Enter the following details:

```
name> dropbox_kiosk
storage> dropbox
client_id> (leave empty)
client_secret> (leave empty)
advanced_config> No
auto_config> No
```

On another Linux machine with `rclone` installed, run:

```bash
rclone authorize "dropbox"
```

Log in and copy the `access_token` from the terminal on the headless machine:

```json
{
  "access_token": "",
  "token_type": "",
  "refresh_token": "",
  "expiry": ""
}
```

Then, confirm with:

```
y/e/d> y
```

Modify the line in `~/.xinitrc` file:
```bash
rclone sync dropbox_kiosk:"/<path_to_images>" ~/media/feh
```

## Behavior After Installation

- The system boots into a terminal session with X running in fullscreen mode.
- Media files sync every **10 minutes (max 20 images x 30 seconds)**.
- The display power is controlled based on a predefined schedule.
- A continuous, auto-updating slideshow runs indefinitely.

## Troubleshooting

### Check Media Sync

```bash
rclone ls dropbox_kiosk:
```

### Test HDMI-CEC Commands

```bash
echo "standby 0" | cec-client -s -d 1  # Turn off display
echo "on 0" | cec-client -s -d 1       # Turn on display
```

### View Scheduled Tasks

```bash
crontab -l
```

## Logs

To view media sync logs:

```bash
tail -f ~/feh_sync.log
