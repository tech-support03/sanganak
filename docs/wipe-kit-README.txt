================================================================
  OMARCHY INSTALL — READ BEFORE PARTITIONING
================================================================

TWO IDENTICAL 1TB CRUCIAL DRIVES ARE IN THIS MACHINE.
Model and size are identical. Only the SERIAL differs.

    242849D4A723  =  WINDOWS   <-- NEVER TOUCH
    24504CC94939  =  LINUX     <-- install here

Device names (nvme0n1 / nvme1n1) are NOT reliable. They can
swap between boots. Do not trust them. Do not trust the
installer's disk list either: both drives report the same
model and the same 931.5 GiB.

----------------------------------------------------------------
ORDER MATTERS. Arm the guard BEFORE archinstall reads the
disks. If archinstall is already open at a menu, quit it and
relaunch after arming -- it caches the disk list at startup and
will keep showing a drive that is no longer there.
----------------------------------------------------------------

STEP 1 — boot this stick. Get a root shell:
         Ctrl+Alt+F2 for a TTY (or quit the installer to a
         prompt), then:   sudo -i

STEP 2 — mount this stick:

    mkdir -p /mnt/usb
    mount /dev/disk/by-label/Ventoy /mnt/usb

STEP 3 — arm the guard:

    bash /mnt/usb/WIPE-KIT/protect-windows-drive.sh

    Expect:  "Windows drive is now invisible"
             WINDOWS ... hidden / not bound  OK
             LINUX   ... /dev/nvmeXn1 (install target)

    >>> IF IT SAYS "STILL VISIBLE" -> STOP. DO NOT INSTALL. <<<

STEP 4 — confirm with your own eyes:

    lsblk -o NAME,SIZE,SERIAL,FSTYPE

    Exactly ONE nvme drive must be listed, serial 24504CC94939.
    If you see two, STOP.

STEP 5 — NOW start archinstall (fresh, not a session that was
         already open). One disk will be offered. Choose btrfs
         for the root filesystem.

----------------------------------------------------------------
AFTER THE INSTALL

  Reboot. The Windows drive comes back on its own -- the guard
  is temporary and nothing was written to it.

  Confirm Windows still boots before doing anything else.
  Its boot entry may need re-adding to Omarchy's boot menu;
  the drive itself is untouched either way.

----------------------------------------------------------------
ANY TIME, CHANGES NOTHING:

    bash /mnt/usb/WIPE-KIT/protect-windows-drive.sh --status

UNDO WITHOUT REBOOTING:

    bash /mnt/usb/WIPE-KIT/protect-windows-drive.sh --undo

MANUAL IDENTIFICATION:

    lsblk -o NAME,SIZE,SERIAL,FSTYPE,LABEL
    ls -l /dev/disk/by-id/nvme-CT1000P3PSSD8_*

    The Windows drive shows ntfs partitions and a 16M
    "Microsoft reserved" partition. The Linux drive does not.

----------------------------------------------------------------
REMINDERS
  - Root filesystem must be BTRFS (Omarchy needs it for snapshots).
  - Secure Boot must be DISABLED in BIOS before installing.
  - BitLocker: confirmed OFF. Nothing to worry about there.
================================================================
