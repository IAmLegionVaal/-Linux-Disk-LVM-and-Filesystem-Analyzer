# Linux Disk, LVM and Filesystem Analyzer

A Linux support toolkit for diagnosing storage problems and applying selected guarded filesystem, mount and LVM repairs.

## Diagnostic script

```bash
chmod +x src/linux_disk_lvm_analyzer.sh
sudo ./src/linux_disk_lvm_analyzer.sh
```

The diagnostic script reports block devices, filesystems, mounts, LVM layout, capacity, inode usage, SMART indicators and kernel storage errors.

## Repair script

Run a read-only filesystem check:

```bash
chmod +x src/linux_disk_lvm_repair.sh
sudo ./src/linux_disk_lvm_repair.sh --check-device /dev/sdb1
```

Repair an unmounted ext or XFS filesystem:

```bash
sudo ./src/linux_disk_lvm_repair.sh --repair-device /dev/sdb1
```

Validate and mount configured filesystems:

```bash
sudo ./src/linux_disk_lvm_repair.sh --mount-all
```

Remount a selected filesystem read-write:

```bash
sudo ./src/linux_disk_lvm_repair.sh --remount-rw /data
```

Extend one logical volume and resize its filesystem:

```bash
sudo ./src/linux_disk_lvm_repair.sh \
  --extend-lv /dev/vg0/data \
  --size +10G
```

Percentage-based growth is also supported, for example `--size +25%FREE`. Use `--dry-run` to preview an operation.

## What the repair does

- Performs read-only ext or XFS checks.
- Repairs one unmounted ext or XFS filesystem.
- Validates `/etc/fstab` and runs `mount -a`.
- Can remount one selected filesystem read-write.
- Can extend one LVM logical volume and resize its filesystem.
- Can run `fstrim` on one selected mount point.
- Captures storage state before and after repair and backs up `/etc/fstab`.

## Safety and limitations

The script refuses filesystem repair while the target device is mounted. Filesystem repair and LVM extension can be disruptive and require a verified backup. It does not create filesystems, erase disks, change partition tables or shrink logical volumes.

## Author

Dewald Pretorius — L2 IT Support Engineer
