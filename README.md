# Kiosk Presenter for Raspberry Pi

This repository provides a script to set up a minimal digital signage system on Raspberry Pi 4 and 5, combined with optional Cloudflared tunneling for secure remote access. The system supports fullscreen image slideshows using `feh`, cloud media synchronization via `rclone`, and HDMI-CEC display control with `cec-utils`.

---

## Features

* **Fullscreen Slideshow**: Automatically displays images in fullscreen using `feh`, with real-time updates.
* **Remote Media Synchronization**: Fetches images from cloud storage providers like Google Drive or Dropbox using `rclone`. When the network is down, the last synced images stay on screen.
* **HDMI-CEC Display Control**: Automatically turns the display on or off using `cec-utils`, on every HDMI port.
* **Cloudflared Tunnel Integration**: Optional SSH access through a Cloudflare Tunnel, with nightly updates and safe hostname changes.
* **Scheduled Power Management**: Display power is managed using cron jobs.

---

## Installation

Log in on the Raspberry Pi as the kiosk user (with console autologin on tty1). Run `setup.sh` without `sudo`; it asks for your password when it needs it.

### Using `wget`

```bash
wget https://raw.githubusercontent.com/MonkeyEnterprise/kiosk-presenter/main/setup.sh -O setup.sh
chmod +x setup.sh
./setup.sh
```

Downloaded on its own, `setup.sh` clones the repository to `~/kiosk-presenter` and continues from there.

### Using `git`

```bash
git clone https://github.com/MonkeyEnterprise/kiosk-presenter.git ~/kiosk-presenter
~/kiosk-presenter/setup.sh
```

The repository must be at `~/kiosk-presenter`. To update a kiosk later, run `git pull` in `~/kiosk-presenter` and reboot.

### Layout

| Repository | Contents |
|---|---|
| `bin/kiosk_client.sh` | Sync and slideshow, started by `~/.xinitrc` |
| `bin/tv-power`, `bin/cec_client.sh` | Display power over HDMI-CEC |
| `bin/cloudflared-auto-update` | Nightly cloudflared update, copied to `/usr/local/bin` |
| `bin/update-cloudflared-containers.sh` | Updates cloudflared Docker containers (for Docker hosts) |
| `dotfiles/` | `bash_profile` and `xinitrc`, linked to `~/.bash_profile` and `~/.xinitrc` |
| `config/tv-power.cron` | Display power schedule, installed in the crontab |
| `config/cloudflared-config.yml` | Template for `/etc/cloudflared/config.yml` |
| `assets/no-image.svg` | Shown while there is no media yet, with the kiosk's hostname and IP address; fills any screen format |
| `test/` | Tests that run in Docker |

On the kiosk:

| Path | Contents |
|---|---|
| `~/kiosk-presenter` | This repository |
| `~/media` | Media synced from the cloud. Anything not on the remote is deleted. |
| `~/logs` | `kiosk_client.log`, `cec_client.log` and the hash cache |
| `/usr/local/bin/tv-power` | Link to `bin/tv-power` |

---

## Configuring `rclone`

`setup.sh` asks whether to initialize rclone and starts `rclone config`. Provide these details:

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

Then `setup.sh` asks for the folder to show, as `remote:path` (e.g. `dropbox_kiosk:/Kiosks/Kiosk4`), and saves it in `~/.bashrc`:

```bash
export RCLONE_REMOTE_PATH='dropbox_kiosk:/Kiosks/Kiosk4'
```

To change the folder later, edit that line and reboot.

---

## Display power schedule

The default schedule is in `config/tv-power.cron`. A kiosk with a schedule of its own keeps it in `~/tv-power.cron` (same format), which is then used instead; `migrate.sh` creates it from the kiosk's old cron jobs. After changing either file, install it again with:

```bash
bash -c 'source ~/kiosk-presenter/setup.sh && install_crontab'
```

`tv-power on|off` calls `bin/cec_client.sh --on` or `--standby`. The script scans every HDMI port (the Pi 5 has two) and sends the command to the port the TV is connected to. When `--on` succeeds, it also makes the Pi the active source after 5 seconds. That switches the TV back to the Pi's input when someone left it on another channel, and some TVs (e.g. TCL) only really switch on then.

---

## Cloudflared Tunnel Setup (Optional)

The script includes an optional function to set up a Cloudflare Tunnel for secure remote access:

1. Prompts the user to initialize Cloudflared.
2. Detects system architecture and downloads the appropriate Cloudflared binary.
3. Installs Cloudflared and logs in to your Cloudflare account.
4. Creates a tunnel with a user-defined name.
5. Configures DNS routing and generates `/etc/cloudflared/config.yml` (SSH to `localhost:22`).
6. Installs and enables Cloudflared as a systemd service.

`cloudflared tunnel route dns` only works for the domain selected during `cloudflared tunnel login`. For any other domain the script prints the CNAME record (`<tunnel-id>.cfargotunnel.com`, proxied) to add in the Cloudflare dashboard.

### Adding or removing a hostname

To move a device to a new domain without losing access, add the new hostname next to the old one, test it, then remove the old one:

```bash
./setup.sh add-hostname       # e.g. pi1.new-domain.com
./setup.sh remove-hostname    # e.g. pi1.old-domain.com, once the new one works
```

Both commands back up `/etc/cloudflared/config.yml`, validate the new config (restoring the backup when it is invalid) and restart the tunnel. As a safety net the previous config is restored automatically after 5 minutes. Once you have logged in again through the new hostname, keep the change with:

```bash
sudo systemctl stop cf-rollback.timer
```

After removing a hostname, delete its DNS record in the Cloudflare dashboard.

### Automatic updates

The setup installs a nightly update job (04:00, root's crontab) that runs `/usr/local/bin/cloudflared-auto-update`. It updates Cloudflared, restarts the tunnel and restores the previous binary if the tunnel does not come back. The job replaces the `cloudflared-update.timer` created by `cloudflared service install`. On a device that was set up earlier, enable it with:

```bash
./setup.sh setup-update
```

Update log:

```bash
tail -f /var/log/cloudflared-update.log
```

### Docker hosts

On a machine that runs cloudflared in Docker containers instead, `bin/update-cloudflared-containers.sh` updates every `cloudflare/cloudflared` container started with docker compose, and rolls back when the tunnel does not reconnect:

```bash
sudo bin/update-cloudflared-containers.sh           # update now
sudo bin/update-cloudflared-containers.sh install   # nightly root cron job (04:30)
```

### Removing Cloudflared

```bash
./setup.sh cleanup-cloudflared
```

This removes Cloudflared completely, including the tunnel credentials, so remote access through the tunnel is lost:

* Stops and disables all Cloudflared services.
* Removes service and timer files.
* Deletes the Cloudflared binary and configuration directories.

---

## Migrating an existing kiosk

Kiosks installed with an earlier version have one of these layouts:

* the whole sync loop in `~/.xinitrc`, media in `~/media/feh` and the log in `~/feh_sync.log`;
* scripts and logs in `~/core` and media in `~/feh`.

To move one to the current layout, first get the current version into `~/kiosk-presenter`.

If the kiosk was installed with `wget` (there is no `~/kiosk-presenter`), clone it:

```bash
git clone https://github.com/MonkeyEnterprise/kiosk-presenter.git ~/kiosk-presenter
```

If it was installed with `git` (`~/kiosk-presenter` exists), update it. The old installation instructions ran `chmod +x` on `setup.sh`, and git counts that as a local change, so `git pull` refuses until it is stashed:

```bash
cd ~/kiosk-presenter
git stash
git pull
```

Then migrate and reboot:

```bash
~/kiosk-presenter/migrate.sh
sudo reboot
```

`migrate.sh` moves the remote from an old `~/.xinitrc` (`REMOTE_PATH="..."` or `--remote_path "..."`) to `~/.bashrc`, moves the media and logs, links the dotfiles and `tv-power`, and replaces the display power cron jobs. The kiosk keeps its own schedule: the times of its old jobs go to `~/tv-power.cron`.

After migrating, check that the kiosk syncs the right folder: `grep RCLONE_REMOTE_PATH ~/.bashrc`. Without it, the kiosk syncs the root of the default remote. Everything it replaces is kept in `~/kiosk-backup-<date>`. Running it again changes nothing. Cloudflared is left alone.

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
tv-power off                              # Turn off display
tv-power on                               # Turn on display and switch it to the Pi
~/kiosk-presenter/bin/cec_client.sh --as  # Only switch the TV to the Pi
```

`~/logs/cec_client.log` shows which HDMI port sees the TV and what was sent.

On TCL TVs, enable **T-Link**, **auto power on** and **quick start / instant power on**. Without quick start the TV ignores CEC while in standby.

### View Scheduled Tasks

```bash
crontab -l
```

### View Logs

```bash
tail -f ~/logs/kiosk_client.log   # sync and slideshow
tail -f ~/logs/cec_client.log     # display power
```

---

## Testing

With Docker installed, run `./test/run.sh` to run all tests, or `./test/run.sh migrate_xinitrc_layout_test.sh` to run one. The tests run the scripts in a Debian 12 container. CEC and the Cloudflare tunnel need a real Raspberry Pi.
