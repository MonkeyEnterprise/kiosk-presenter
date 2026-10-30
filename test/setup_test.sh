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
check '[ "$(crontab -l | grep -c "$REPO/bin/tv-power")" -eq 8 ]' "schedule installed once after two runs"
check '! crontab -l | grep -q -e "__BIN__" -e "^#"' "placeholders and comments filled in or left out"
check 'crontab -l | grep -qF "/usr/bin/true"' "unrelated cron job kept"

echo "== Crontab with a schedule of the kiosk's own"
printf '# own schedule\n0 7 * * 1 __BIN__/tv-power on >/dev/null 2>&1\n' > "$HOME/tv-power.cron"
bash -c "source $REPO/setup.sh && install_crontab" > /dev/null
check '[ "$(crontab -l | grep -c "tv-power")" -eq 1 ] && crontab -l | grep -qxF "0 7 * * 1 $REPO/bin/tv-power on >/dev/null 2>&1"' "~/tv-power.cron is used instead of the default"
rm "$HOME/tv-power.cron"

echo "== Sourcing has no side effects"
bash -c "source $REPO/setup.sh" > /tmp/out 2>&1; rc=$?
check '[ $rc -eq 0 ] && [ ! -s /tmp/out ]' "sourcing setup.sh prints and runs nothing"

finish
