#!/bin/bash

# =============================================================================
# cec_client.sh and tv-power Tests
# -----------------------------------------------------------------------------
# Runs bin/cec_client.sh and bin/tv-power against a fake cec-client and fake
# CEC devices, to check which HDMI port the commands are sent to. The fake
# prints a scan like the real cec-client, with the TV (device #0) only on the
# port in FAKE_TV_DEVICE, and fails to transmit on the ports in
# FAKE_FAIL_DEVICES. Meant to run inside the container started by
# test/run.sh, with the repository mounted at /repo.
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

source /repo/test/lib.sh

# === CONFIG ===
CEC="/repo/bin/cec_client.sh"
FAKE_DIR="/tmp/fake-cec"
export KIOSK_LOG_DIR="/tmp/logs"
export KIOSK_CEC_DEVICES="$FAKE_DIR/dev/cec*"
export KIOSK_CEC_AS_DELAY=0
export FAKE_CEC_CALLS="$FAKE_DIR/calls"
export PATH="$FAKE_DIR/bin:$PATH"

mkdir -p "$FAKE_DIR/bin" "$FAKE_DIR/dev"
cat > "$FAKE_DIR/bin/cec-client" <<'FAKE'
#!/bin/bash
# Fake cec-client: cec-client -s -d 1 <device>, command on stdin
dev="${!#}"
read -r cmd
if [ "$cmd" == "scan" ]; then
    echo "opening a connection to the CEC adapter..."
    echo "requesting CEC bus information ..."
    echo "CEC bus information"
    echo "==================="
    if [ "$dev" == "$FAKE_TV_DEVICE" ]; then
        printf 'device #0: TV\naddress:       0.0.0.0\npower status:  standby\n\n'
    fi
    printf 'device #1: Recorder 1\naddress:       1.0.0.0\n\n'
    exit 0
fi
echo "$(basename "$dev") $cmd" >> "$FAKE_CEC_CALLS"
echo "opening a connection to the CEC adapter..."
if [[ " $FAKE_FAIL_DEVICES " == *" $dev "* ]]; then
    echo "ERROR:   [  123]   ioctl CEC_TRANSMIT failed - tx_status=08 rx_status=00"
fi
exit 0
FAKE
chmod +x "$FAKE_DIR/bin/cec-client"

# Set up the fake ports: reset_ports <number of ports>
reset_ports() {
    rm -rf "$FAKE_DIR/dev"/* "$FAKE_CEC_CALLS" "$KIOSK_LOG_DIR"
    local i
    for ((i = 0; i < $1; i++)); do
        touch "$FAKE_DIR/dev/cec$i"
    done
    unset FAKE_TV_DEVICE FAKE_FAIL_DEVICES
}

calls() {
    cat "$FAKE_CEC_CALLS" 2> /dev/null
}

# =============================================================================
# Tests
# =============================================================================

echo "== Options"
reset_ports 1
for option in --on --standby --as; do
    "$CEC" "$option" > /dev/null; rc=$?
done
check '[ "$(calls)" == "$(printf "cec0 on 0\ncec0 as\ncec0 standby 0\ncec0 as")" ]' "--on sends 'on 0' and 'as', --standby 'standby 0', --as 'as'"
"$CEC" "on 0" > /tmp/out 2>&1; rc=$?
check '[ $rc -ne 0 ] && grep -q "Usage:" /tmp/out' "a raw command is rejected with usage"
"$CEC" > /tmp/out 2>&1; rc=$?
check '[ $rc -ne 0 ] && grep -q "Usage:" /tmp/out' "no option is rejected with usage"

echo "== TV on the second HDMI port"
reset_ports 2
export FAKE_TV_DEVICE="$FAKE_DIR/dev/cec1"
"$CEC" --on; rc=$?
check '[ $rc -eq 0 ]' "exits successfully"
check '[ "$(calls)" == "$(printf "cec1 on 0\ncec1 as")" ]' "on and as sent only to cec1, the port with the TV"
check 'grep -q "Adapter .*cec1 sees the TV" "$KIOSK_LOG_DIR/cec_client.log"' "log says which port sees the TV"

echo "== TV on the first HDMI port"
reset_ports 2
export FAKE_TV_DEVICE="$FAKE_DIR/dev/cec0"
"$CEC" --standby
check '[ "$(calls)" == "cec0 standby 0" ]' "command sent only to cec0"

echo "== No port sees the TV"
reset_ports 2
"$CEC" --on; rc=$?
check '[ $rc -eq 0 ] && [ "$(calls)" == "$(printf "cec0 on 0\ncec0 as")" ]' "falls back to the first port that responds"

echo "== Transmit fails on the port without the TV"
reset_ports 2
export FAKE_FAIL_DEVICES="$FAKE_DIR/dev/cec0"
"$CEC" --on; rc=$?
check '[ $rc -eq 0 ] && [ "$(calls)" == "$(printf "cec0 on 0\ncec1 on 0\ncec1 as")" ]' "tries the next port, and sends as only there"

echo "== Transmit fails everywhere"
reset_ports 2
export FAKE_FAIL_DEVICES="$FAKE_DIR/dev/cec0 $FAKE_DIR/dev/cec1"
"$CEC" --on; rc=$?
check '[ $rc -ne 0 ] && grep -q "No adapter could transmit" "$KIOSK_LOG_DIR/cec_client.log"' "exits with an error and logs it"
check '! calls | grep -q " as$"' "no as after a failed on"

echo "== No CEC devices"
reset_ports 0
"$CEC" --on; rc=$?
check '[ $rc -ne 0 ] && grep -q "No working CEC adapters found" "$KIOSK_LOG_DIR/cec_client.log"' "exits with an error and logs it"
check '[ -z "$(calls)" ]' "sends nothing"

echo "== tv-power"
reset_ports 2
export FAKE_TV_DEVICE="$FAKE_DIR/dev/cec1"
/repo/bin/tv-power on
check '[ "$(calls)" == "$(printf "cec1 on 0\ncec1 as")" ]' "tv-power on turns the TV on and switches it to the Pi"
rm -f "$FAKE_CEC_CALLS"
/repo/bin/tv-power off
check '[ "$(calls)" == "cec1 standby 0" ]' "tv-power off sends --standby"

finish
