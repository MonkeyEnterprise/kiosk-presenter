# Kiosk Presenter for Raspberry Pi 5

<p align="center"> <img src="https://upload.wikimedia.org/wikipedia/en/thumb/c/cb/Raspberry_Pi_Logo.svg/200px-Raspberry_Pi_Logo.svg.png" width="15%"> </p>

This repository provides a script to set up a minimal digital signage system on Raspberry Pi 5, combined with optional Cloudflared tunneling for secure remote access. The system supports fullscreen image slideshows using `feh`, cloud media synchronization via `rclone`, and HDMI-CEC display control with `cec-utils`.

---

## Features

* **Fullscreen Slideshow**: Automatically displays images in fullscreen using `feh`, with real-time updates.
* **Remote Media Synchronization**: Fetches images from cloud storage providers like Google Drive or Dropbox using `rclone`.
* **HDMI-CEC Display Control**: Automatically turns the display on or off using `cec-utils`.
* **Cloudflared Tunnel Integration**: Optional secure tunnel setup for remote access using Cloudflare Tunnel.
* **Scheduled Power Management**: Display power is managed using cron jobs.

---

## Installation

Log in on the Raspberry Pi as the `kiosk` user (with autologin on tty1) and run:

```bash
git clone https://github.com/MonkeyEnterprise/kiosk-presenter ~/kiosk-presenter
cd ~/kiosk-presenter
./setup.sh
```

Run `setup.sh` without `sudo`; it asks for your password when it needs it. To update a kiosk later, run `git pull` in `~/kiosk-presenter` and reboot.

## Layout

| Repository | Contents |
|---|---|
| `bin/` | `kiosk_client.sh` (sync and slideshow) and `cec_client.sh` (display power) |
| `dotfiles/` | `bash_profile` and `xinitrc`, linked to `~/.bash_profile` and `~/.xinitrc` by `setup.sh` |
| `assets/` | `no-image.png`, shown while there is no media yet |
| `test/` | Tests that run in Docker |

On the kiosk:

| Path | Contents |
|---|---|
| `~/kiosk-presenter` | This repository |
| `~/media` | Media synced from the cloud. Anything not on the remote is deleted. |
| `~/logs` | `kiosk_client.log`, `cec_client.log` and the hash cache |

## Migrating an existing kiosk

Kiosks installed before this layout have their scripts and logs in `~/core` and their media in `~/feh`. To move one to the current layout:

```bash
git clone https://github.com/MonkeyEnterprise/kiosk-presenter ~/kiosk-presenter
~/kiosk-presenter/migrate.sh
sudo reboot
```

`migrate.sh` moves the media and logs, links the dotfiles and updates the cron jobs. Everything it replaces is kept in `~/kiosk-backup-<date>`. Running it again changes nothing.

## Testing

With Docker installed, run `./test/run.sh` to run all tests, or `./test/run.sh migrate_test.sh` to run one. The tests cover `kiosk_client.sh` and `migrate.sh` in a Debian 12 container; CEC and the cloudflared tunnel need a real Raspberry Pi.
