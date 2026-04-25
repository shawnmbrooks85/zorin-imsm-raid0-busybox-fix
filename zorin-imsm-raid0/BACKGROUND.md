# Background: Why the Default Install Fails

If you just want it to work, follow `INSTALL.md`. This document explains what's actually going on, so when something breaks in a future install, the symptoms make sense.

## What is IMSM?

Intel Matrix Storage Manager (IMSM), now branded Intel Rapid Storage Technology (RST), is **firmware-assisted RAID**. The RAID metadata lives on the drives in an Intel-defined format, and the BIOS option ROM presents the array as if it were a single disk during boot. Once the OS loads, though, all the actual RAID work is done by the OS - Intel's "RAID" controller is really just a metadata format and a BIOS shim.

On Linux, IMSM arrays are assembled by `mdadm` (the same tool used for native Linux software RAID), but using a different metadata format. `mdadm` knows how to read Intel's metadata, find the member drives, and present the array as `/dev/md126` (the volume) plus `/dev/md127` (the empty container holding the metadata).

## Why the Ubiquity installer trips on it

Ubuntu's installer (Ubiquity, used by Zorin and most Ubuntu derivatives) can detect and target an IMSM array. The "Something else" partitioner shows `/dev/md126` and lets you create partitions on it. Installation completes successfully. GRUB writes itself to the array's ESP. The partition table is correct, the filesystems are mounted right, the bootloader entries are valid.

But Ubiquity ships an initramfs that doesn't include `dmraid` or, on some kernels, the right mdadm hooks for IMSM specifically. So when you boot:

1. **Firmware** sees the array (because Intel's option ROM presents it as a single disk in the boot list)
2. **GRUB loads** from the ESP (also fine - GRUB has its own driver layer)
3. **Kernel starts** loading from initramfs
4. **Initramfs** tries to find `/dev/md126p2` to mount as root
5. **It can't**, because the assembly tools and udev rules needed to bring the IMSM container up aren't in initramfs
6. After a timeout, the boot scripts give up and drop you to a `(initramfs)` BusyBox prompt

The fix - installing `mdadm` and `dmraid` in the *target system* and rebuilding initramfs - bakes those tools into the boot environment so step 5 succeeds.

## Why pre-formatting the ESP matters

When you partition `/dev/md126` and the installer formats the ESP, it uses `mkfs.vfat` under the hood. But the installer's wrapper around it has a known issue on IMSM arrays where it fails if the partition has any pre-existing filesystem signature - and partitions on a freshly created GPT can sometimes inherit signatures from previous metadata in the same physical sectors (especially after multiple install attempts).

The error you'll see is:

> Failed to create a file system. The efi file system creation in partition #1 of RAID0 device #126 failed.

The simplest workaround is to format the ESP yourself before launching the installer, then tell the installer "use this as ESP, don't reformat." `mkfs.vfat` from a live terminal handles the leftover signatures fine; the installer's wrapped version doesn't.

## Why bootloader target must be /dev/md126

If you let the installer write GRUB to `/dev/nvme0n1`, it writes to the GPT of one physical drive. But that drive contains a *stripe* of the array - half of every block, interleaved with the other drive. The ESP filesystem isn't readable from a single member; it only exists at the array level.

In practice this might *appear* to work because EFI firmware sees the IMSM array as a logical disk and reads the ESP that way. But you've created a fragile setup where the bootloader install location and the actual filesystem location disagree, and updates (`grub-install` re-runs after kernel updates) can write to the wrong place.

Always target `/dev/md126` for IMSM. The array IS the disk, as far as the OS is concerned.

## Why "Erase disk" fails

The installer's "Erase disk and install" mode makes assumptions about layout:
- It expects to create its own partition table
- It defaults to LVM-on-encrypted or LVM-plain
- It writes GRUB to whichever device it considers the "main" disk

On IMSM, the "main disk" detection is unreliable - you sometimes get GRUB on a single member NVMe, and the LVM defaults add a layer that makes recovery harder if anything goes wrong. "Something else" gives you control over all three of the things that matter: partition layout, filesystem types, and bootloader target.

## Why the kernel-busy errors happen

When you partition or wipe a block device, the kernel needs to update its in-memory partition table. It does this when:
- No process has the device open
- No filesystem is mounted from it
- No device-mapper or LVM target uses it

If any of those are violated, the kernel keeps the *old* partition table and `partprobe`/`partx` can't refresh it. udisks2 (the GNOME daemon that powers the Disks utility and auto-mounting) is famous for opening every block device it can see and holding probes open. The Ubuntu installer also keeps things open even after errors.

In a normal workflow (boot live USB → make partitions → install), you don't hit this. But if you've already had one failed install, the kernel has stale references and the next attempt's `mkfs` fails with "Device or resource busy."

The clean solution is a reboot. Heroic measures - `kpartx`, `dmsetup remove_all`, stopping the array, etc. - sometimes work but often don't. Reboot is faster.

## Should you use IMSM at all?

Probably not, unless you have a specific reason:

**Use IMSM if:**
- Dual-booting Windows, and Windows needs to see the array
- You want the array to survive reinstalling the OS without rebuilding
- BIOS literally won't let you switch out of RAID mode

**Don't use IMSM if:**
- Linux-only system
- You want to use modern features like RAID 1E, RAID 6, or anything beyond 0/1/5/10
- You want to avoid initramfs surprises on every kernel update

**Pure mdadm alternative:**

1. Reboot to BIOS, switch SATA/NVMe controller from RAID to AHCI
2. Boot live USB
3. Create the array natively:
   ```bash
   sudo mdadm --create /dev/md0 --level=0 --raid-devices=2 \
       --metadata=1.2 /dev/nvme0n1 /dev/nvme1n1
   ```
4. Partition `/dev/md0` and install normally

Native mdadm is fully supported by Ubuntu's default initramfs - no chroot fix needed, no surprises on kernel updates. The downside is Windows can't read it, and switching the BIOS mode after Windows is installed requires Windows-side tweaks (or a reinstall) to avoid an Inaccessible Boot Device BSOD.

## RAID 0 risk reminder

RAID 0 doubles the surface area for failure. With two drives at the same MTBF, your effective MTBF is roughly halved. If either drive fails, all data is gone - there's no parity, no mirror, nothing to rebuild from.

This is fine for:
- Workstations where data lives in version control / cloud sync
- Scratch volumes for build artifacts
- Gaming installs that can be redownloaded

This is bad for:
- The only copy of anything

Set up backups before you put anything important on it. Timeshift for system snapshots, plus a separate backup of `/home` to an external drive or cloud, is the minimum.
