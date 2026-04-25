#!/usr/bin/env bash
#
# 02-post-install-chroot.sh
#
# Run from the Zorin live USB AFTER the installer finishes.
# Click "Continue Testing" on the install-complete popup (NOT Restart Now),
# then run this script.
#
# Mounts the freshly installed root + ESP, chroots in, installs mdadm
# and dmraid, rebuilds initramfs (so it can assemble the IMSM container
# at boot), regenerates GRUB config, and unmounts cleanly.
#
# Edit ROOT_PART / ESP_PART if your partitions aren't /dev/md126p2 /
# /dev/md126p1.
#
# Usage:
#   chmod +x 02-post-install-chroot.sh
#   sudo ./02-post-install-chroot.sh

set -euo pipefail

ROOT_PART="/dev/md126p2"
ESP_PART="/dev/md126p1"
MNT="/mnt"

# --- sanity checks --------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
fi

for p in "$ROOT_PART" "$ESP_PART"; do
    if [[ ! -b "$p" ]]; then
        echo "Block device $p not found." >&2
        echo "Check 'lsblk' output and adjust the variables in this script." >&2
        exit 1
    fi
done

# --- mount target system --------------------------------------------------

echo "=== Mounting $ROOT_PART at $MNT ==="
mount "$ROOT_PART" "$MNT"

echo "=== Mounting $ESP_PART at $MNT/boot/efi ==="
mkdir -p "$MNT/boot/efi"
mount "$ESP_PART" "$MNT/boot/efi"

echo "=== Bind-mounting /dev /dev/pts /proc /sys /run ==="
for d in dev dev/pts proc sys run; do
    mount --bind "/$d" "$MNT/$d"
done

# --- chroot and fix initramfs ---------------------------------------------

echo "=== Entering chroot to install mdadm/dmraid and rebuild initramfs ==="

chroot "$MNT" /usr/bin/env bash -e <<'CHROOT_EOF'
export DEBIAN_FRONTEND=noninteractive

apt-get install --reinstall -y mdadm dmraid

# Rebuild initramfs for every installed kernel
update-initramfs -u -k all

# Regenerate GRUB config so it references the rebuilt initrds
update-grub

CHROOT_EOF

echo "=== Chroot finished cleanly ==="

# --- unmount in reverse order --------------------------------------------

echo "=== Unmounting ==="
for d in run sys proc dev/pts dev; do
    umount "$MNT/$d"
done
umount "$MNT/boot/efi"
umount "$MNT"

echo
echo "Done. The installed system now has mdadm/dmraid baked into initramfs."
echo "Reboot now: 'sudo reboot'  (and pull the USB stick during POST)"
