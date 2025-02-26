# Kiosk Presenter for Raspberry Pi

<p align="center"> <img src="https://upload.wikimedia.org/wikipedia/en/thumb/c/cb/Raspberry_Pi_Logo.svg/200px-Raspberry_Pi_Logo.svg.png" width="15%"> </p>

This script sets up a minimal digital signage system on Raspberry Pi 3, 4, and 5. It displays a fullscreen slideshow using `feh`, synchronizes media via `rclone`, and manages display power using `cec-utils`.

## Features

- **Fullscreen Slideshow**: Displays images with `feh`, updating automatically when new images are added.
- **Remote Sync**: Downloads images from cloud storage (Google Drive, Dropbox, etc.) using `rclone`.
- **HDMI-CEC Control**: Turns the display on/off automatically with `cec-utils`.
- **Real-Time Monitoring**: Detects new images and updates the slideshow.
- **Scheduled Power Management**: Controls display power via `cron` jobs.

## Installation

Run the setup script using `wget`:
```bash
wget https://raw.githubusercontent.com/MonkeyEnterprise/kiosk-presenter/refs/heads/main/setup.sh -O setup.sh
chmod +x setup.sh
./setup.sh
```

or run the setup script using `git`:
```bash
git clone https://github.com/MonkeyEnterprise/kiosk-presenter.git ~/kiosk-presenter
chmod +x ~/kiosk-presenter/setup.sh
. ~/kiosk-presenter/setup.sh
```

Follow the prompts to configure `rclone`.

## Behavior After Installation

- Boots into a terminal session with X running in fullscreen mode.
- Syncs media files every 5 minutes.
- Controls display power based on a predefined schedule.
- Runs a continuous, auto-updating slideshow.

## Troubleshooting

- **Check media sync**:
  ```bash
  rclone ls remote:path
  ```
- **Test HDMI-CEC commands**:
  ```bash
  echo "standby 0" | cec-client -s -d 1  # Turn off display
  echo "on 0" | cec-client -s -d 1       # Turn on display
  ```
- **View cron jobs**:
  ```bash
  crontab -l
  ```

## Logs

Media sync logs:
```bash
tail -f ~/feh_sync.log
```

---