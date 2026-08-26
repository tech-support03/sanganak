================================================================
  OMARCHY INSTALL — READ BEFORE PARTITIONING
================================================================

TWO IDENTICAL 1TB CRUCIAL DRIVES ARE IN THIS MACHINE.
Model and size are the same. Only the SERIAL differs.

    242849D4A723  =  WINDOWS   <-- NEVER TOUCH
    24504CC94939  =  LINUX     <-- install here

Device names (nvme0n1 / nvme1n1) are NOT reliable. They can
swap between boots. Do not trust them.

----------------------------------------------------------------
STEP 1 — boot the Omarchy ISO, then get a shell.
         In the installer press Ctrl+Alt+F2 for a TTY,
         or quit to a prompt. Become root:  sudo -i

STEP 2 — mount this stick and run the guard:

    mkdir -p /mnt/usb
    mount /dev/disk/by-label/Ventoy /mnt/usb
    bash /mnt/usb/WIPE-KIT/protect-windows-drive.sh

    It will say:  "Windows drive is now invisible"
    and show that only ONE drive remains.

    If it says the Windows drive is STILL VISIBLE -> STOP.

STEP 3 — go back to archinstall (Ctrl+Alt+F1).
         Only ONE disk will be listed. That is the right one.
         There is nothing left to choose wrongly.

----------------------------------------------------------------
TO CHECK AT ANY TIME, WITHOUT CHANGING ANYTHING:

    bash /mnt/usb/WIPE-KIT/protect-windows-drive.sh --status

TO IDENTIFY DRIVES MANUALLY:

    lsblk -o NAME,SIZE,SERIAL,FSTYPE,LABEL
    ls -l /dev/disk/by-id/nvme-CT1000P3PSSD8_*

    The Windows drive is the one showing ntfs partitions
    and a 16M "Microsoft reserved" partition.

----------------------------------------------------------------
REMINDERS
  - Root filesystem must be BTRFS (Omarchy needs it for snapshots).
  - Secure Boot must be DISABLED in BIOS before installing.
  - Check BitLocker from Windows first:  manage-bde -status
  - A reboot restores the Windows drive. The guard is temporary.
================================================================
