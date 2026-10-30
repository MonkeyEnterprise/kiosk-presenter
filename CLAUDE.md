# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Bash-only digital signage setup for a Raspberry Pi 5. A fullscreen `feh` slideshow shows images synced from cloud storage via `rclone`. HDMI-CEC (`cec-utils`) turns the display on and off on a cron schedule. A Cloudflare Tunnel is optional, for remote access. There is no build step or lint config. The scripts target the Pi (Debian/Raspberry Pi OS, `apt`, `/dev/cec*`, X11).

## Testing

- `./test/run.sh` (needs Docker) builds a Debian 12 image and runs each `test/*_test.sh` in its own container, with the repo mounted read-only at `/repo`. Use `./test/run.sh <name>_test.sh` to run one test. All tests take about a minute.
  - [test/kiosk_client_test.sh](test/kiosk_client_test.sh) runs the real `bin/kiosk_client.sh` with `feh` on Xvfb and a local directory as the rclone remote. It uses `KIOSK_MEDIA_DIR`, `KIOSK_LOG_DIR` and `KIOSK_SYNC_INTERVAL=2` to redirect paths and speed up the loop.
  - [test/migrate_test.sh](test/migrate_test.sh) builds an old-layout kiosk, runs `migrate.sh` twice and checks the result.
  - Each test file uses `check '<condition>' "<description>"`.
- Not covered: autologin and `startx`, the cloudflared and rclone parts of `setup.sh`, and CEC. They need a Debian arm64 VM or a real Pi, and CEC needs real hardware.
- `bash -n <script>` for a quick syntax check.

## Layout and runtime flow

The device runs as user `kiosk`. The repo must be cloned to `~/kiosk-presenter`: `dotfiles/xinitrc` hardcodes that path, and `setup.sh` and `migrate.sh` refuse to run from anywhere else. The scripts in `bin/` find the repo from their own location. Runtime data lives outside the repo, in `~/media` (synced media) and `~/logs` (logs and hash cache). `~/media` is a mirror of the remote, so anything else put there is deleted on the next sync. That is why the placeholder lives in `assets/no-image.png`.

1. Autologin on tty1 → `~/.bash_profile` (a symlink to `dotfiles/bash_profile`) sources `~/.bashrc` and then runs `startx -- -nocursor` in an endless restart loop.
2. `~/.xinitrc` (a symlink to `dotfiles/xinitrc`) turns off screen blanking and DPMS, then `exec`s `bin/kiosk_client.sh --remote_path "$RCLONE_REMOTE_PATH"`.
3. `bin/kiosk_client.sh` loops forever, every 300 s:
   - It runs `rclone sync` from the remote into `~/media`. `--exclude '*/**'` syncs top-level files only, and files deleted on the remote are deleted locally.
   - A failed sync (non-zero rclone exit code) is logged but not fatal, so the last synced media stays on screen when the network is down. Keep it that way: if the script exits, X exits too and the screen goes black.
   - It hashes `ls -lR` of the media dir, compares the hash with `~/logs/.cache`, and restarts `feh` if they differ. It also restarts `feh` if it is not running. If the media dir is empty, `feh` shows `assets/no-image.png` instead, because `feh` exits immediately when it has no images.
4. `bin/cec_client.sh "<cmd>" ...` tries each `/dev/cec*` adapter in turn: it runs a `scan`, then sends the commands, and stops at the first adapter where they succeed. Cron calls it with `"on 0"` and `"standby 0"`.

`RCLONE_REMOTE_PATH` (e.g. `kiosk-dropbox:/Kiosks/Kiosk4`) is appended to `~/.bashrc` by the rclone step in `setup.sh`. The rclone remote names are `kiosk-dropbox`, `kiosk-gdrive` and `kiosk-onedrive`.

## setup.sh and migrate.sh

`setup.sh` is an interactive installer, run as the kiosk user without `sudo`; it calls `sudo` itself. It runs these steps in order: apt deps → symlink the dotfiles (`link_dotfile` keeps an existing file as `.bak`) → crontab → download cloudflared, log in, create the tunnel and DNS route, write `/etc/cloudflared/config.yml` (ingress to `http://localhost:8080`) and `tunnel run` → rclone remote setup.

- `install_crontab` replaces every existing line matching `cec[-_]client.sh` and keeps other jobs, so it is safe to re-run. The display on/off schedule is hardcoded there.
- `main` only runs when `setup.sh` is executed directly. `migrate.sh` sources it to reuse `log`, the checks, `link_dotfile` and `install_crontab`, so keep top-level code in `setup.sh` free of side effects.
- Known issue: `cloudflared tunnel run` runs in the foreground, so `rclone_setup` only runs after the tunnel stops. The tunnel is not installed as a service either.

`migrate.sh` moves a kiosk from the old layout (`~/core` holding the scripts, logs and cache; `~/feh` holding the media; copied dotfiles; cron jobs calling `~/core/cec-client.sh`) to the current one. Everything it replaces goes to `~/kiosk-backup-<timestamp>`, and a second run changes nothing.

## Conventions

- Each script starts with a `# ===` banner header (description, usage, `Author: Lorenzo Pouw 2025`, project URL), and sections are separated by `# ===` dividers. Each script defines its own `log()` helper that prefixes a `YYYY-MM-DD HH:MM:SS - ` timestamp.
- Config values sit in a `# === CONFIG ===` block at the top of each runtime script.
- Scripts must keep their executable bit in git (`git update-index --chmod=+x`), because `xinitrc` and cron call them directly.
