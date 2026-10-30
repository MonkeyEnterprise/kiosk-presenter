# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Bash-only digital signage setup for a Raspberry Pi 5. A fullscreen `feh` slideshow shows images synced from cloud storage via `rclone`. HDMI-CEC (`cec-utils`) turns the display on and off on a cron schedule. A Cloudflare Tunnel is optional, for SSH access. There is no build step or lint config. The scripts target the Pi (Debian/Raspberry Pi OS, `apt`, `/dev/cec*`, X11).

## Testing

- `./test/run.sh` (needs Docker) builds a Debian 12 image and runs each `test/*_test.sh` in its own container, with the repo mounted read-only at `/repo`. Use `./test/run.sh <name>_test.sh` to run one test. All tests take about a minute.
  - [test/kiosk_client_test.sh](test/kiosk_client_test.sh) runs the real `bin/kiosk_client.sh` with `feh` on Xvfb and a local directory as the rclone remote. It uses `KIOSK_MEDIA_DIR`, `KIOSK_LOG_DIR` and `KIOSK_SYNC_INTERVAL=2` to redirect paths and speed up the loop.
  - `migrate_core_layout_test.sh` and `migrate_xinitrc_layout_test.sh` each build a kiosk with one of the old layouts, run `migrate.sh` twice and check the result.
  - `setup_test.sh` covers the parts of `setup.sh` that need no network: checks, subcommands, `install_crontab`, and that sourcing it has no side effects.
  - The test files source [test/lib.sh](test/lib.sh) for `check '<condition>' "<description>"` and `finish`. The image has passwordless `sudo` for `kiosk`, like the Pi.
- Not covered: autologin and `startx`, the wget bootstrap, the cloudflared and rclone parts of `setup.sh`, and CEC. They need a Debian arm64 VM or a real Pi, and CEC needs real hardware.
- `bash -n <script>` for a quick syntax check.

## Layout and runtime flow

The device runs as user `kiosk`. The repo must be cloned to `~/kiosk-presenter`: `dotfiles/xinitrc` hardcodes that path, and `setup.sh` and `migrate.sh` refuse to run from anywhere else. The scripts in `bin/` find the repo from their own location. Runtime data lives outside the repo, in `~/media` (synced media) and `~/logs` (logs and hash cache). `~/media` is a mirror of the remote, so anything else put there is deleted on the next sync. That is why the placeholder lives in `assets/no-image.png`.

1. Autologin on tty1 → `~/.bash_profile` (a symlink to `dotfiles/bash_profile`) sources `~/.bashrc` and then runs `startx -- -nocursor` in an endless restart loop.
2. `~/.xinitrc` (a symlink to `dotfiles/xinitrc`) turns off screen blanking and DPMS, then `exec`s `bin/kiosk_client.sh --remote_path "$RCLONE_REMOTE_PATH"`.
3. `bin/kiosk_client.sh` loops forever, every 300 s:
   - It runs `rclone sync` from the remote into `~/media`. `--exclude '*/**'` syncs top-level files only, and files deleted on the remote are deleted locally.
   - A failed sync (non-zero rclone exit code) is logged but not fatal, so the last synced media stays on screen when the network is down. Keep it that way: if the script exits, X exits too and the screen goes black.
   - It hashes `ls -lR` of the media dir, compares the hash with `~/logs/.cache`, and restarts `feh` if they differ. It also restarts `feh` if it is not running. If the media dir is empty, `feh` shows `assets/no-image.png` instead, because `feh` exits immediately when it has no images.
4. Cron runs `bin/tv-power on|off` on the schedule in `config/tv-power.cron` (`__BIN__` is replaced with the repo's `bin/`). `on` sends `on 0`, then `as` after 5 s, because TCL TVs only wake up when the Pi claims active source. `tv-power` calls `bin/cec_client.sh "<cmd>"`, which tries each `/dev/cec*` adapter in turn (the Pi 5 has two): it runs a `scan`, then sends the commands, and stops at the first adapter where they succeed. `/usr/local/bin/tv-power` is a symlink to `bin/tv-power`.

`RCLONE_REMOTE_PATH` (e.g. `dropbox_kiosk:/Kiosks/Kiosk4`) is the per-device setting. `save_remote_path` in `setup.sh` writes it as the last line of `~/.bashrc`. That works because the tty1 login shell is interactive; the stock Debian `.bashrc` returns early in non-interactive shells.

## setup.sh and migrate.sh

`setup.sh` is an interactive installer, run as the kiosk user without `sudo`; it calls `sudo` itself. Downloaded on its own (wget), `bootstrap_repo` clones the repo to `~/kiosk-presenter` and `exec`s the `setup.sh` in there. Without arguments, it runs (under `set -e`): apt deps → symlink the dotfiles (`link_dotfile` keeps an existing file as `.bak`) → link `tv-power` → crontab → optional cloudflared → optional `rclone config` and `save_remote_path` → reboot prompt. Subcommands: `add-hostname`, `remove-hostname`, `setup-update`, `cleanup-cloudflared`, `help`.

- Cloudflared: the binary is installed as a systemd service with `config/cloudflared-config.yml` as the config template (SSH to `localhost:22`, catch-all 404). `add-hostname`/`remove-hostname` edit `/etc/cloudflared/config.yml` with a backup, `ingress validate`, and a `cf-rollback` systemd timer that restores the old config after 5 minutes unless stopped. `route_dns` only uses `cloudflared tunnel route dns` for the zone from `cloudflared tunnel login`; for other domains it prints the CNAME to add by hand.
- `bin/cloudflared-auto-update` is copied (not linked) to `/usr/local/bin`, because root runs it from cron and it must not be writable by the kiosk user. Keep it that way for anything root runs.
- `install_crontab` replaces every line matching `cec[-_]client.sh` or `tv-power` and keeps other jobs, so it is safe to re-run.
- `main` only runs when `setup.sh` is executed directly. `migrate.sh` sources it to reuse its functions, so keep top-level code in `setup.sh` free of side effects (`setup_test.sh` checks this).

`migrate.sh` moves a kiosk from either old layout to the current one, and leaves cloudflared alone:
- xinitrc layout (from the old `main`): the whole sync loop in `~/.xinitrc` with `REMOTE_PATH="..."` in it, media in `~/media/feh`, `~/feh_sync.log`, a copy of `tv-power` in `/usr/local/bin`.
- core layout (from the old `dev-op`): `~/core` holding the scripts, logs and cache, media in `~/feh`, cron jobs calling `~/core/cec-client.sh`.

Everything it replaces goes to `~/kiosk-backup-<timestamp>`, and a second run changes nothing.

`bin/update-cloudflared-containers.sh` is a standalone tool for Docker hosts running cloudflared containers, not part of the kiosk install.

## Conventions

- Each script starts with a `# ===` banner header (description, usage, `Author: Lorenzo Pouw 2025`, project URL), and sections are separated by `# ===` dividers. Each script defines its own `log()` helper that prefixes a `YYYY-MM-DD HH:MM:SS - ` timestamp.
- Config values sit in a `# === CONFIG ===` block at the top of each runtime script.
- Scripts must keep their executable bit in git (`git update-index --chmod=+x`), because `xinitrc` and cron call them directly.
