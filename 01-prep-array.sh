#!/usr/bin/env bash
#
# 01-prep-array.sh
#
# Run from the Zorin live USB BEFORE launching the installer.
# Wipes any existing LVM/partitions on the IMSM array and lays down
# a fresh GPT with an ESP (FAT32) and a root partition (unformatted,
# the installer will format it).
#
# Edit ARRAY_DEVICE if your array isn't /dev/md126.
#
# Usage:
#   chmod +x 01-prep-array.sh
#   sudo ./01-prep-array.sh

set -euo pipefail

ARRAY_DEVICE="/dev/md126"
ESP_SIZE_MB=512

# --- sanity checks --------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
fi

if [[ ! -b "$ARRAY_DEVICE" ]]; then
    echo "Block device $ARRAY_DEVICE not found." >&2
    echo "Check 'lsblk' output and adjust ARRAY_DEVICE in this script." >&2
    exit 1
fi

echo "=== Current layout ==="
lsblk "$ARRAY_DEVICE" || true
echo

read -r -p "About to wipe $ARRAY_DEVICE. Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# --- tear down LVM if present ---------------------------------------------

echo "=== Tearing down any existing LVM ==="
swapoff -a || true

# Look for VGs that have PVs on the array, deactivate and remove them
for vg in $(pvs --noheadings -o vg_name "${ARRAY_DEVICE}"* 2>/dev/null | awk '{print $1}' | sort -u); do
    if [[ -n "$vg" ]]; then
        echo "Removing volume group: $vg"
        vgchange -an "$vg" || true
        vgremove -f "$vg" || true
    fi
done

# Remove any PVs on the array
for part in "${ARRAY_DEVICE}"p*; do
    [[ -b "$part" ]] || continue
    pvremove -ff -y "$part" 2>/dev/null || true
done

# --- wipe filesystem signatures and partition table ----------------------

echo "=== Wiping filesystem signatures ==="
for part in "${ARRAY_DEVICE}"p*; do
    [[ -b "$part" ]] || continue
    wipefs -a "$part" || true
done
wipefs -a "$ARRAY_DEVICE" || true

echo "=== Zapping GPT ==="
sgdisk --zap-all "$ARRAY_DEVICE"
partprobe "$ARRAY_DEVICE" || true

# --- create new partition layout -----------------------------------------

echo "=== Creating new GPT layout ==="
sgdisk -n "1:0:+${ESP_SIZE_MB}M" -t 1:ef00 -c 1:"EFI"  "$ARRAY_DEVICE"
sgdisk -n "2:0:0"                -t 2:8300 -c 2:"root" "$ARRAY_DEVICE"
partprobe "$ARRAY_DEVICE"

echo "=== Formatting ESP as FAT32 ==="
mkfs.vfat -F32 "${ARRAY_DEVICE}p1"

# --- verify ---------------------------------------------------------------

echo
echo "=== Final layout ==="
lsblk -f "$ARRAY_DEVICE"
echo
echo "Done. ${ARRAY_DEVICE}p1 is FAT32 ESP, ${ARRAY_DEVICE}p2 is empty for the installer."
echo
echo "Next: launch the installer, pick 'Something else', and:"
echo "  - ${ARRAY_DEVICE}p1  -> Use as: EFI System Partition (DO NOT tick Format)"
echo "  - ${ARRAY_DEVICE}p2  -> Use as: Ext4, Mount: /  (TICK Format)"
echo "  - Bootloader target: ${ARRAY_DEVICE}"
echo
echo "After install completes, click 'Continue Testing' (NOT Restart)."
echo "Then run scripts/02-post-install-chroot.sh"
