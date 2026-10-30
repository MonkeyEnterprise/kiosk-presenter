#!/bin/bash

# =============================================================================
# setup.sh Tests
# -----------------------------------------------------------------------------
# Checks the parts of setup.sh that run without network or a Cloudflare
# account: the checks, the command line and the crontab install. Meant to run
# inside the container started by test/run.sh, as user kiosk, with the
# repository mounted at /repo.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

source /repo/test/lib.sh

# === CONFIG ===
REPO="$HOME/kiosk-presenter"

cp -a /repo "$REPO"

echo "== Command line"
"$REPO/setup.sh" help > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ] && grep -q "add-hostname" /tmp/out' "help lists the commands"
"$REPO/setup.sh" bogus > /tmp/out 2>&1; rc=$?
check '[ $rc -ne 0 ] && grep -q "Usage:" /tmp/out' "unknown command shows usage and fails"

echo "== Checks"
sudo "$REPO/setup.sh" help > /tmp/out 2>&1; rc=$?
check '[ $rc -ne 0 ] && grep -q "Do not run this script with sudo" /tmp/out' "refuses to run as root"
/repo/setup.sh help > /tmp/out 2>&1; rc=$?
check '[ $rc -ne 0 ] && grep -q "must be at $REPO" /tmp/out' "refuses to run from the wrong location"

echo "== Crontab"
echo "0 3 * * * /usr/bin/true" | crontab -
bash -c "source $REPO/setup.sh && install_crontab && install_crontab" > /dev/null
check '[ "$(crontab -l | grep -c "$REPO/bin/tv-power")" -eq 10 ]' "schedule installed once after two runs"
check 'crontab -l | grep -qxF "0 18 * * 6 $REPO/bin/tv-power on >/dev/null 2>&1"' "default schedule includes Saturday"
check '! crontab -l | grep -q "^[[:space:]]*$"' "no blank lines in the crontab"
check '! crontab -l | grep -q -e "__BIN__" -e "^#"' "placeholders and comments filled in or left out"
check 'crontab -l | grep -qF "/usr/bin/true"' "unrelated cron job kept"

echo "== Crontab with a schedule of the kiosk's own"
printf '# own schedule\n0 7 * * 1 __BIN__/tv-power on >/dev/null 2>&1\n' > "$HOME/tv-power.cron"
bash -c "source $REPO/setup.sh && install_crontab" > /dev/null
check '[ "$(crontab -l | grep -c "tv-power")" -eq 1 ] && crontab -l | grep -qxF "0 7 * * 1 $REPO/bin/tv-power on >/dev/null 2>&1"' "~/tv-power.cron is used instead of the default"
rm "$HOME/tv-power.cron"

echo "== setup-update replaces the old cloudflared update job"
# Root's crontab as found on kiosk1
printf '%s\n' '0 4 * * * /usr/local/bin/cloudflared update >> /var/log/cloudflared-update.log 2>&1; [ $? -eq 11 ] && systemctl restart cloudflared' \
    '0 5 * * * /usr/bin/true' | sudo crontab -
"$REPO/setup.sh" setup-update > /dev/null 2>&1
"$REPO/setup.sh" setup-update > /dev/null 2>&1
check '! sudo crontab -l | grep -qF "/usr/local/bin/cloudflared update"' "old update job removed"
check '[ "$(sudo crontab -l | grep -c "cloudflared-auto-update")" -eq 1 ]' "one cloudflared-auto-update job, also after two runs"
check 'sudo crontab -l | grep -qF "/usr/bin/true"' "unrelated root cron job kept"
check '[ "$(stat -c %U /usr/local/bin/cloudflared-auto-update)" == "root" ]' "update script installed, owned by root"

echo "== Log rotation"
bash -c "source $REPO/setup.sh && install_log_dir && install_logrotate" > /dev/null
CONF=/etc/logrotate.d/kiosk-presenter
LOGS=/var/log/kiosk-presenter
check '[ "$(stat -c "%U %a" $LOGS)" == "$(id -un) 755" ]' "log directory created, owned by the kiosk user"
check '[ "$(stat -c "%U %a" $CONF)" == "root 644" ]' "config installed, owned by root"
check 'grep -qF "$LOGS/*.log {" $CONF && grep -qF "su $(id -un) $(id -gn)" $CONF && ! grep -q "__" $CONF' "placeholders filled in"
head -c 6000000 /dev/zero | tr "\0" "x" | fold -w 100 > "$LOGS/kiosk_client.log"
sudo logrotate -s /tmp/logrotate.state $CONF; rc=$?
check '[ $rc -eq 0 ]' "logrotate accepts the config"
check '[ -f "$LOGS/kiosk_client.log.1" ] && [ ! -s "$LOGS/kiosk_client.log" ]' "a log over 5 MB is rotated and the original emptied"
check '[ "$(stat -c %U "$LOGS/kiosk_client.log.1")" == "$(id -un)" ]' "the rotated log stays owned by the kiosk user"

echo "== Sourcing has no side effects"
bash -c "source $REPO/setup.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ] && [ ! -s /tmp/out ]' "sourcing setup.sh prints and runs nothing"

finish
