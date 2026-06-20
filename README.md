# Linux Disk, LVM and Filesystem Analyzer

A read-only Bash toolkit for diagnosing Linux storage layout, capacity, filesystem, LVM, mount, and device-health issues.

## Features

- Block-device, partition, filesystem, UUID, and mount inventory
- Capacity and inode utilisation thresholds
- LVM physical volume, volume group, and logical volume evidence
- Read-only, failed, and unusual mount-state detection
- SMART summary where `smartctl` is available
- Kernel storage-error indicators
- Largest-directory evidence for selected mount points
- Text, CSV, and JSON reports

## Usage

```bash
chmod +x src/linux_disk_lvm_analyzer.sh
sudo ./src/linux_disk_lvm_analyzer.sh
```

Optional filesystem threshold:

```bash
sudo ./src/linux_disk_lvm_analyzer.sh --warning-percent 85
```

## Safety

The script does not format disks, mount or unmount filesystems, resize LVM volumes, repair filesystems, or modify partition tables.

## Validation

Test on a standard partitioned VM, an LVM-based VM, a near-capacity filesystem, and a host without SMART tooling.

## Author

Dewald Pretorius — L2 IT Support Engineer
