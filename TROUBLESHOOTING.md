# Troubleshooting

Issues actually encountered during this install, with the resolutions that worked.

## Boot drops to `(initramfs)` BusyBox prompt after install

**Cause:** Initramfs doesn't include mdadm/dmraid hooks, so it can't assemble the IMSM container to find root.

**Fix:** Boot back into the live USB and run the chroot procedure (`scripts/02-post-install-chroot.sh` or Step 5 in `INSTALL.md`).

You can sometimes recover from BusyBox without a USB. See `scripts/03-recover-busybox.md`.

## Installer error: "Failed to create a file system. The efi file system creation in partition #1 of RAID0 device #126 failed"

**Cause:** Leftover ext4 (or other) signature on the partition the installer is trying to format as FAT32. The installer's format step doesn't always wipe pre-existing signatures cleanly on IMSM arrays.

**Fix:** Quit the installer, pre-format the ESP yourself:

```bash
sudo wipefs -a /dev/md126p1
sudo mkfs.vfat -F32 /dev/md126p1
```

Then relaunch the installer and **leave the Format checkbox UNTICKED** for the ESP. It just needs to be flagged as `Use as: EFI System Partition`.

## `wipefs` / `mkfs` says "Device or resource busy"

**Cause:** Kernel is holding a stale partition reference from a previous failed install attempt. udisks, ubiquity, or the kernel itself has the device open and `partprobe` couldn't update the partition table.

**Symptoms:**
```
wipefs: error: /dev/md126p1: probing initialization failed: Device or resource busy
mkfs.vfat: unable to open /dev/md126p1: Device or resource busy
```

**Fix order (try each, then retry the failing command):**

1. Kill installer remnants:
   ```bash
   sudo pkill -9 ubiquity
   sudo pkill -9 ubi-partman
   ```

2. Stop udisks:
   ```bash
   sudo systemctl stop udisks2
   ```

3. Force the kernel to reread the partition table:
   ```bash
   sudo blockdev --rereadpt /dev/md126
   sudo partx -d /dev/md126 && sudo partx -a /dev/md126
   ```

4. **Just reboot the live USB.** Honestly, if step 3 fails, stop trying to be clever. A reboot takes 60 seconds and clears every kernel reference. After fighting this for an hour I learned: when the kernel has md126 wedged, even `mdadm --stop` can't unwedge it. Reboot.

After the reboot, **don't open Disks utility** before going back to terminal work, and **don't open the installer** before pre-formatting the ESP.

## "Cannot get exclusive access to /dev/md126" when running mdadm --stop

**Cause:** Same as above — something has the array open. LVM is the most common culprit, but stale udisks references will do it too.

**Fix:**
```bash
sudo swapoff -a
sudo vgchange -an vgzorin       # if LVM was set up
sudo vgremove -f vgzorin        # if LVM was set up
sudo systemctl stop udisks2
sudo mdadm --stop /dev/md126
```

If `mdadm --stop` still complains, reboot.

## LVM volume group "vgzorin" exists from a previous install

This was the default of the failed first install (Ubiquity defaults to LVM-on-LUKS-or-not when you pick "Erase disk"). It blocks repartitioning of `/dev/md126` because the LVs hold the partition open.

**Fix:**
```bash
sudo swapoff -a
sudo vgchange -an vgzorin
sudo vgremove -f vgzorin
sudo pvremove -ff /dev/md126p2   # whichever partition was the PV
sudo wipefs -a /dev/md126p1 /dev/md126p2 /dev/md126
sudo sgdisk --zap-all /dev/md126
sudo partprobe /dev/md126
```

Reboot the live USB if `partprobe` warns about the kernel still using the old table.

## Installer's "Erase disk and install Zorin" doesn't see the array correctly

Don't use it. Always pick **Something else** for IMSM. The Erase mode tries to be helpful and either targets a single member NVMe or sets up LVM you don't want.

## After successful install, system boots but RAID shows degraded

**Check:**
```bash
cat /proc/mdstat
sudo mdadm --detail /dev/md126
```

If a member is missing, one NVMe might be loose, dead, or excluded from the IMSM volume in BIOS. Reboot to BIOS, check Intel RST status, reseat the NVMes.

If the array is fine in BIOS but Linux sees it degraded, that's an mdadm assembly issue — `sudo update-initramfs -u -k all` and reboot.

## GRUB doesn't appear, system boots straight to firmware setup

**Cause:** Bootloader was written to a member NVMe instead of `/dev/md126`, OR the EFI System Partition isn't flagged correctly in the firmware boot list.

**Check from a live USB chroot:**
```bash
sudo efibootmgr -v
```

You should see a Zorin/Ubuntu entry pointing to `\EFI\zorin\shimx64.efi` or similar. If it's missing or pointing wrong, regenerate:

```bash
# inside chroot
apt install --reinstall grub-efi-amd64 shim-signed
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=zorin --recheck
update-grub
```

## `os-prober` warning during update-grub

```
Warning: os-prober will not be executed to detect other bootable partitions.
```

Harmless on a single-OS install. If you're dual-booting, edit `/etc/default/grub` and set `GRUB_DISABLE_OS_PROBER=false`, then re-run `update-grub`.
