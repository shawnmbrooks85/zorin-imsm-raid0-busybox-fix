# Installation Procedure

End-to-end procedure for installing Zorin OS onto an Intel IMSM RAID 0 array. Assumes BIOS is already configured for RAID mode and the array exists.

## Prerequisites

- Zorin OS install USB (any version based on Ubuntu 22.04+)
- BIOS in UEFI mode, Secure Boot off (or signed with mdadm/dmraid trust - easier to disable)
- Intel RST RAID 0 volume created in BIOS, both NVMes as members
- Working keyboard, ideally a wired one (laptop keyboards on the Alienware can be flaky in early initramfs)

## Step 0 - Boot the live USB

Boot to the USB, pick **Try Zorin** (not Install yet). Land at the live desktop.

## Step 1 - Verify the array

Open a terminal:

```bash
lsblk
```

Expected layout:

```
nvme0n1     259:0    0  3.7T  0 disk
├─md126       9:126  0  7.5T  0 raid0
└─md127       9:127  0    0B  0 md
nvme1n1     259:1    0  3.7T  0 disk
├─md126       9:126  0  7.5T  0 raid0
└─md127       9:127  0    0B  0 md
```

- `md126` is the actual RAID 0 volume (this is what you partition)
- `md127` is the IMSM container (0B is normal - it's metadata, not storage)
- If `md126` already has partitions/LVM under it from a previous attempt, run `scripts/01-prep-array.sh` to nuke them

**Do not open the GNOME Disks utility at any point during this process.** It auto-mounts and probes things behind your back, which causes the partition kernel-busy errors that ate hours of my life.

## Step 2 - Pre-create partitions and format ESP from terminal

This is the critical step that lets the installer succeed. We create the partitions and pre-format the ESP as FAT32 ourselves, because the installer's own format step fails on IMSM arrays in subtle ways related to leftover filesystem signatures.

```bash
sudo sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"  /dev/md126
sudo sgdisk -n 2:0:0     -t 2:8300 -c 2:"root" /dev/md126
sudo partprobe /dev/md126
sudo mkfs.vfat -F32 /dev/md126p1
lsblk -f
```

Expected output from `lsblk -f`:

- `md126p1` shows FSTYPE `vfat`
- `md126p2` shows blank FSTYPE (installer will format it)

If `lsblk -f` shows that, you're good. If `md126p1` shows `ext4` or anything other than `vfat`, repeat `mkfs.vfat`.

## Step 3 - Run the installer

Launch **Install Zorin OS** from the desktop. Click through Language, Keyboard, etc.

At **Updates and other software**: pick whatever you want (normal or minimal install). Tick "Install third-party software" - you'll need NVIDIA bits and codecs.

At **Installation type**: pick **Something else** → Continue.

You'll see a partition list. Configure as follows:

### `/dev/md126p1` (the 510 MB partition)
1. Click the row to highlight
2. Click **Change...**
3. Use as: **EFI System Partition**
4. **Leave the Format checkbox UNTICKED** - we already formatted it
5. OK

### `/dev/md126p2` (the 8.2 TB partition)
1. Click the row
2. Click **Change...**
3. Use as: **Ext4 journaling file system**
4. Mount point: **`/`**
5. **Tick the Format checkbox**
6. OK

### Bootloader target
At the bottom: **Device for boot loader installation** → change from `/dev/nvme0n1` to **`/dev/md126`**.

This is critical. The boot loader must go on the array device itself, not on a single member NVMe. If you write GRUB to nvme0n1, the firmware will see a single drive's stripe-half and fail to boot.

### Install
Click **Install Now** → **Continue** on the "Write changes" popup.

Fill in user details, timezone, etc. Let the installer run.

## Step 4 - STOP. Do not reboot.

When the installation finishes, a popup appears asking **Restart Now** or **Continue Testing**.

**Click Continue Testing.**

If you reboot here, you will drop into a BusyBox initramfs prompt and have to redo this from a live USB chroot anyway. Don't.

## Step 5 - Chroot fix (the actual important part)

Back in a terminal in the live session:

```bash
sudo mount /dev/md126p2 /mnt
sudo mount /dev/md126p1 /mnt/boot/efi
for i in dev dev/pts proc sys run; do sudo mount --bind /$i /mnt/$i; done
sudo chroot /mnt
```

Your prompt should change to something like `root@zorin:/#`. You're now inside the installed system.

```bash
apt install --reinstall mdadm dmraid
update-initramfs -u -k all
update-grub
exit
```

What this does:
- `mdadm` + `dmraid` get installed/reinstalled to ensure the userspace tools are present
- `update-initramfs -u -k all` rebuilds the initramfs for every installed kernel, baking in mdadm/dmraid hooks so initramfs can assemble the IMSM container at boot
- `update-grub` regenerates `/boot/grub/grub.cfg` with the correct root reference

You'll see a lot of output including some `Running in chroot, ignoring command 'daemon-reload'` messages. Those are harmless - systemd inside a chroot can't talk to the outer host's systemd, and it doesn't need to.

What you want to see in the output:

```
update-initramfs: Generating /boot/initrd.img-6.x.x-xx-generic
```

…for each installed kernel, with no errors. And from update-grub:

```
Found linux image: /boot/vmlinuz-6.x.x-xx-generic
Found initrd image: /boot/initrd.img-6.x.x-xx-generic
```

## Step 6 - Unmount and reboot

Back outside the chroot:

```bash
for i in run sys proc dev/pts dev; do sudo umount /mnt/$i; done
sudo umount /mnt/boot/efi
sudo umount /mnt
sudo reboot
```

When the system POSTs, **pull the USB stick** so it doesn't boot back into the live environment.

## Step 7 - First boot

You should land at the GRUB menu, then the Zorin splash, then the login screen. Log in.

Verify the install with:

```bash
lsblk
cat /proc/mdstat
df -h /
```

`lsblk` should show the same RAID layout but with `md126p2` mounted at `/`. `mdstat` should show the array active. `df -h /` should show your full 7.5 TB available.

## Optional post-install

- Install NVIDIA drivers if you didn't tick the third-party box: `sudo ubuntu-drivers autoinstall`
- Add a swapfile (skip swap partition - pointless on a stripe):
  ```bash
  sudo fallocate -l 8G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  ```
- Set up timeshift or similar - RAID 0 is a backup-or-die situation
