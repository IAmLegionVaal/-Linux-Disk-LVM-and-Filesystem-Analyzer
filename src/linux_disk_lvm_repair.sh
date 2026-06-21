#!/usr/bin/env bash
set -u

ACTION=""
TARGET=""
SIZE=""
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: linux_disk_lvm_repair.sh ACTION TARGET [options]

Actions:
  --check-device DEVICE       Run a read-only filesystem check.
  --repair-device DEVICE      Repair an unmounted ext or XFS filesystem.
  --mount-all                 Validate and mount entries from /etc/fstab.
  --remount-rw MOUNTPOINT     Remount a mounted filesystem read-write.
  --extend-lv LV --size SIZE  Extend one logical volume and its filesystem.
  --trim MOUNTPOINT           Run fstrim on one mounted filesystem.

Options:
  --dry-run                   Show commands without changing the system.
  --yes                       Skip confirmation prompts.
  --output DIR                Save logs, backups and verification output in DIR.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-device) ACTION="check"; TARGET="${2:-}"; shift 2 ;;
    --repair-device) ACTION="repair"; TARGET="${2:-}"; shift 2 ;;
    --mount-all) ACTION="mount-all"; shift ;;
    --remount-rw) ACTION="remount-rw"; TARGET="${2:-}"; shift 2 ;;
    --extend-lv) ACTION="extend-lv"; TARGET="${2:-}"; shift 2 ;;
    --size) SIZE="${2:-}"; shift 2 ;;
    --trim) ACTION="trim"; TARGET="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ -n "$ACTION" ] || { echo "Choose one repair action." >&2; exit 2; }
if [ "$ACTION" != "mount-all" ] && [ -z "$TARGET" ]; then echo "A target is required." >&2; exit 2; fi
if [ "$ACTION" = "extend-lv" ] && [ -z "$SIZE" ]; then echo "--size is required for logical-volume extension." >&2; exit 2; fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-./disk-lvm-repair-$STAMP}"
BACKUP_DIR="$OUTPUT_DIR/backup"
mkdir -p "$OUTPUT_DIR" "$BACKUP_DIR"
LOG="$OUTPUT_DIR/repair.log"
BEFORE="$OUTPUT_DIR/before.txt"
AFTER="$OUTPUT_DIR/after.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " answer; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run_action() {
  local description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then printf 'DRY-RUN:' >> "$LOG"; printf ' %q' "$@" >> "$LOG"; printf '\n' >> "$LOG"; return 0; fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_root() { local description="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" sudo "$@"; fi; }
collect_state() {
  local destination="$1"
  {
    echo "Collected: $(date -Is)"
    lsblk -f
    echo
    findmnt
    echo
    df -hT
    echo
    command -v pvs >/dev/null 2>&1 && pvs || true
    command -v vgs >/dev/null 2>&1 && vgs || true
    command -v lvs >/dev/null 2>&1 && lvs -a -o +devices || true
    [ -n "$TARGET" ] && { echo; findmnt "$TARGET" 2>/dev/null || true; blkid "$TARGET" 2>/dev/null || true; }
  } > "$destination"
}

collect_state "$BEFORE"
[ -f /etc/fstab ] && cp -a /etc/fstab "$BACKUP_DIR/fstab" 2>/dev/null || true
confirm "Apply '$ACTION' to '${TARGET:-system fstab}'?" || { log "Repair cancelled."; exit 10; }

case "$ACTION" in
  check)
    [ -b "$TARGET" ] || { echo "Block device not found: $TARGET" >&2; exit 2; }
    FSTYPE=$(blkid -o value -s TYPE "$TARGET" 2>/dev/null || true)
    case "$FSTYPE" in
      ext2|ext3|ext4) run_root "Checking $TARGET" fsck -fn "$TARGET" || true ;;
      xfs) run_root "Checking XFS metadata on $TARGET" xfs_repair -n "$TARGET" || true ;;
      *) echo "Unsupported filesystem type: $FSTYPE" >&2; exit 2 ;;
    esac
    ;;
  repair)
    [ -b "$TARGET" ] || { echo "Block device not found: $TARGET" >&2; exit 2; }
    findmnt -rn -S "$TARGET" >/dev/null 2>&1 && { echo "Refusing to repair a mounted filesystem." >&2; exit 20; }
    FSTYPE=$(blkid -o value -s TYPE "$TARGET" 2>/dev/null || true)
    case "$FSTYPE" in
      ext2|ext3|ext4) run_root "Repairing $TARGET" fsck -fy "$TARGET" || true ;;
      xfs) run_root "Repairing XFS filesystem on $TARGET" xfs_repair "$TARGET" || true ;;
      *) echo "Unsupported filesystem type: $FSTYPE" >&2; exit 2 ;;
    esac
    ;;
  mount-all)
    run_root "Validating fstab entries" findmnt --verify --verbose || true
    run_root "Mounting configured filesystems" mount -a || true
    ;;
  remount-rw)
    findmnt -rn "$TARGET" >/dev/null 2>&1 || { echo "Mount point not found: $TARGET" >&2; exit 2; }
    run_root "Remounting $TARGET read-write" mount -o remount,rw "$TARGET" || true
    ;;
  extend-lv)
    command -v lvs >/dev/null 2>&1 || { echo "LVM tools are not installed." >&2; exit 3; }
    lvs "$TARGET" >/dev/null 2>&1 || { echo "Logical volume not found: $TARGET" >&2; exit 2; }
    case "$SIZE" in
      +[0-9]*%FREE|+[0-9]*%VG) run_root "Extending $TARGET by $SIZE and resizing its filesystem" lvextend -r -l "$SIZE" "$TARGET" || true ;;
      +[0-9]*[KkMmGgTt]) run_root "Extending $TARGET by $SIZE and resizing its filesystem" lvextend -r -L "$SIZE" "$TARGET" || true ;;
      *) echo "Use a positive size such as +10G or +25%FREE." >&2; exit 2 ;;
    esac
    ;;
  trim)
    findmnt -rn "$TARGET" >/dev/null 2>&1 || { echo "Mount point not found: $TARGET" >&2; exit 2; }
    run_root "Trimming unused blocks on $TARGET" fstrim -v "$TARGET" || true
    ;;
esac

collect_state "$AFTER"
if [ "$FAILURES" -gt 0 ]; then exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
