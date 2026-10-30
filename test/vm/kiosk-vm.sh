#!/bin/bash

# =============================================================================
# Kiosk Test VM
# -----------------------------------------------------------------------------
# Runs a Debian arm64 VM on an Apple Silicon Mac (QEMU with hvf, no emulation)
# that is set up like a fresh Raspberry Pi: a kiosk user with passwordless
# sudo and console autologin on tty1. Use it to test the full installation
# with setup.sh, or a migration with migrate.sh. CEC does not work in a VM.
#
# Usage:
#   test/vm/kiosk-vm.sh create    Download the Debian cloud image, create a fresh disk
#   test/vm/kiosk-vm.sh start     Start the VM; its screen opens in a window
#   test/vm/kiosk-vm.sh ssh [cmd] SSH into the VM as kiosk (or run a command)
#   test/vm/kiosk-vm.sh sync      Copy the local working tree over ~/kiosk-presenter
#                                 in the VM, to test changes before pushing them
#   test/vm/kiosk-vm.sh stop      Shut the VM down
#   test/vm/kiosk-vm.sh reset     Throw the disk away and create a fresh one
#
# Environment:
#   KIOSK_VM_DIR      Where the image and disk are kept (default ~/.cache/kiosk-presenter-vm)
#   KIOSK_VM_RELEASE  Debian release: bookworm (12, default) or trixie (13)
#
# Requirements: brew install qemu
#
# Author: Lorenzo Pouw 2025
# Project: https://github.com/MonkeyEnterprise/kiosk-presenter
# =============================================================================

# === CONFIG ===
VM_DIR="${KIOSK_VM_DIR:-$HOME/.cache/kiosk-presenter-vm}"
RELEASE="${KIOSK_VM_RELEASE:-bookworm}"
SSH_PORT=2222
MEMORY=2048
CPUS=4
DISK_SIZE=16G

case "$RELEASE" in
    bookworm) VERSION=12 ;;
    trixie) VERSION=13 ;;
    *) echo "Unsupported release: $RELEASE (use bookworm or trixie)"; exit 1 ;;
esac

IMAGE_NAME="debian-$VERSION-generic-arm64.qcow2"
IMAGE_URL="https://cloud.debian.org/images/cloud/$RELEASE/latest"
IMAGE="$VM_DIR/$IMAGE_NAME"
DISK="$VM_DIR/disk-$RELEASE.qcow2"
SEED="$VM_DIR/seed.iso"
SSH_KEY="$VM_DIR/id_ed25519"
PID_FILE="$VM_DIR/qemu.pid"
FIRMWARE="$(brew --prefix 2>/dev/null)/share/qemu/edk2-aarch64-code.fd"

log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $*"
}

ssh_vm() {
    ssh -i "$SSH_KEY" -p "$SSH_PORT" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        kiosk@localhost "$@"
}

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2> /dev/null
}

download_image() {
    if [ -f "$IMAGE" ]; then
        return 0
    fi
    log "Downloading $IMAGE_NAME..."
    curl -fL --progress-bar -o "$IMAGE.part" "$IMAGE_URL/$IMAGE_NAME" || exit 1

    local expected actual
    expected=$(curl -fsL "$IMAGE_URL/SHA512SUMS" | awk -v f="$IMAGE_NAME" '$2 == f {print $1}')
    actual=$(shasum -a 512 "$IMAGE.part" | awk '{print $1}')
    if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
        log "Checksum of $IMAGE_NAME does not match SHA512SUMS."
        rm -f "$IMAGE.part"
        exit 1
    fi
    mv "$IMAGE.part" "$IMAGE"
    log "Checksum OK."
}

# cloud-init config: the kiosk user, the SSH key and autologin on tty1, like
# 'raspi-config > Console Autologin' on the Pi
create_seed() {
    local dir="$VM_DIR/seed"
    rm -rf "$dir" "$SEED"
    mkdir -p "$dir"

    cat > "$dir/meta-data" <<EOF
instance-id: kiosk-vm-$(date +%s)
local-hostname: kiosk-vm
EOF

    cat > "$dir/user-data" <<EOF
#cloud-config
users:
  - name: kiosk
    gecos: Kiosk
    shell: /bin/bash
    groups: [sudo, video, audio, input]
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    plain_text_passwd: kiosk
    ssh_authorized_keys:
      - $(cat "$SSH_KEY.pub")
ssh_pwauth: false
write_files:
  - path: /etc/systemd/system/getty@tty1.service.d/autologin.conf
    content: |
      [Service]
      ExecStart=
      ExecStart=-/sbin/agetty --autologin kiosk --noclear %I \$TERM
runcmd:
  - systemctl daemon-reload
  - systemctl restart getty@tty1
EOF

    hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o "$SEED" "$dir"
}

create() {
    if is_running; then
        echo "The VM is running. Stop it first: $0 stop"
        exit 1
    fi
    mkdir -p "$VM_DIR"
    download_image
    [ -f "$SSH_KEY" ] || ssh-keygen -q -t ed25519 -N "" -C kiosk-vm -f "$SSH_KEY"
    create_seed

    rm -f "$DISK"
    qemu-img create -q -f qcow2 -F qcow2 -b "$IMAGE" "$DISK" "$DISK_SIZE"
    log "Fresh disk created: $DISK (Debian $VERSION, $RELEASE)"
}

start() {
    if is_running; then
        echo "The VM is already running."
        exit 0
    fi
    if [ ! -f "$DISK" ]; then
        create
    fi
    if [ ! -f "$FIRMWARE" ]; then
        echo "QEMU firmware not found at $FIRMWARE. Install QEMU: brew install qemu"
        exit 1
    fi

    log "Starting the VM (screen opens in a window, SSH on port $SSH_PORT)..."
    qemu-system-aarch64 \
        -machine virt -accel hvf -cpu host -smp "$CPUS" -m "$MEMORY" \
        -bios "$FIRMWARE" \
        -drive file="$DISK",if=virtio,format=qcow2 \
        -drive file="$SEED",if=virtio,format=raw,readonly=on \
        -device virtio-gpu-pci -display cocoa \
        -device qemu-xhci -device usb-kbd -device usb-tablet \
        -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:"$SSH_PORT"-:22 \
        -pidfile "$PID_FILE" > "$VM_DIR/qemu.log" 2>&1 &
    disown

    log "Waiting for SSH..."
    local i
    for ((i = 0; i < 60; i++)); do
        if ! is_running && [ "$i" -gt 1 ]; then
            log "QEMU stopped. See $VM_DIR/qemu.log"
            exit 1
        fi
        if ssh_vm -o ConnectTimeout=2 true 2> /dev/null; then
            log "VM is up. Connect with: $0 ssh"
            return 0
        fi
        sleep 5
    done
    log "SSH did not come up within 5 minutes."
    exit 1
}

# Copy the working tree (without .git) over the clone in the VM, so the VM
# runs the local, unpushed version
sync_repo() {
    local repo_dir
    repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
    ssh_vm 'mkdir -p ~/kiosk-presenter' || exit 1
    COPYFILE_DISABLE=1 tar -C "$repo_dir" --exclude .git --exclude .DS_Store -cf - . \
        | ssh_vm 'tar -C ~/kiosk-presenter -xf - 2> /dev/null' || exit 1
    log "Copied $repo_dir to ~/kiosk-presenter in the VM."
}

stop() {
    if ! is_running; then
        echo "The VM is not running."
        return 0
    fi
    ssh_vm sudo poweroff 2> /dev/null
    local i
    for ((i = 0; i < 30; i++)); do
        is_running || { log "VM stopped."; rm -f "$PID_FILE"; return 0; }
        sleep 1
    done
    kill "$(cat "$PID_FILE")"
    rm -f "$PID_FILE"
    log "VM killed."
}

case "${1:-}" in
    create) create ;;
    start) start ;;
    ssh) shift; ssh_vm "$@" ;;
    sync) sync_repo ;;
    stop) stop ;;
    reset) stop; create ;;
    *)
        sed -n '/^# Usage:/,/^# Requirements/p' "$0" | sed -e 's/^# \{0,1\}//' -e '$d'
        exit 1
        ;;
esac
