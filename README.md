# Kiosk Presenter for Raspberry Pi

<p align="center"> <img src="https://upload.wikimedia.org/wikipedia/en/thumb/c/cb/Raspberry_Pi_Logo.svg/200px-Raspberry_Pi_Logo.svg.png" width="15%"> </p>

This repository provides a script to set up a minimal digital signage system on Raspberry Pi 4 and 5, combined with optional Cloudflared tunneling for secure remote access. The system supports fullscreen image slideshows using `feh`, cloud media synchronization via `rclone`, and HDMI-CEC display control with `cec-utils`.

---

## Features

* **Fullscreen Slideshow**: Automatically displays images in fullscreen using `feh`, with real-time updates.
* **Remote Media Synchronization**: Fetches images from cloud storage providers like Google Drive or Dropbox using `rclone`.
* **HDMI-CEC Display Control**: Automatically turns the display on or off using `cec-utils`.
* **Cloudflared Tunnel Integration**: Optional secure tunnel setup for remote access using Cloudflare Tunnel.
* **Scheduled Power Management**: Display power is managed using cron jobs.

---

## Installation

### Using `wget`

```bash
wget https://raw.githubusercontent.com/MonkeyEnterprise/kiosk-presenter/main/setup.sh -O setup.sh
chmod +x setup.sh
./setup.sh
```

### Using `git`

```bash
git clone https://github.com/MonkeyEnterprise/kiosk-presenter.git ~/kiosk-presenter
chmod +x ~/kiosk-presenter/setup.sh
./kiosk-presenter/setup.sh
```

---

## Configuring `rclone`

Run the following command to start configuration:

```bash
rclone config
```

Provide these details:

```
name> dropbox_kiosk
storage> dropbox
client_id> (leave empty)
client_secret> (leave empty)
advanced_config> No
auto_config> No
```

On another Linux machine with `rclone`, authorize Dropbox:

```bash
rclone authorize "dropbox"
```

Copy the `access_token` output and confirm:

```
y/e/d> y
```

Update `~/.xinitrc` to synchronize media at startup:

```bash
rclone sync dropbox_kiosk:"/<path_to_images>" ~/media/feh
```

---

## Cloudflared Tunnel Setup (Optional)

The script includes an optional function to set up a Cloudflare Tunnel for secure remote access:

1. Prompts the user to initialize Cloudflared.
2. Detects system architecture and downloads the appropriate Cloudflared binary.
3. Installs Cloudflared and logs in to your Cloudflare account.
4. Creates a tunnel with a user-defined name.
5. Configures DNS routing and generates `/etc/cloudflared/config.yml`.
6. Installs and enables Cloudflared as a systemd service.

To reset or remove Cloudflared completely, the script includes a cleanup function that:

* Stops and disables all Cloudflared services.
* Removes service and timer files.
* Deletes the Cloudflared binary and configuration directories.

---

## Behavior After Installation

* System boots into a terminal session with X starting in fullscreen mode.
* Media files are synchronized every 5 minutes.
* Display power is automatically managed according to schedule.
* Continuous, auto-updating slideshow runs indefinitely.
* Optional remote access is enabled through Cloudflared tunnel.

---

## Troubleshooting

### Check Media Synchronization

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

### View Media Sync Logs

```bash
tail -f ~/feh_sync.log
```

