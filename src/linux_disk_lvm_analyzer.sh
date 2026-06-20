#!/usr/bin/env bash
set -u

WARNING=85
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --warning-percent) WARNING="${2:-85}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--warning-percent N] [--output DIR]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$WARNING" =~ ^[0-9]+$ ]] || { echo "Threshold must be numeric" >&2; exit 2; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./linux-storage-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/storage-report.txt"
CSV="$OUTPUT_DIR/filesystems.csv"
JSON="$OUTPUT_DIR/storage-summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"

section() { local title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
have() { command -v "$1" >/dev/null 2>&1; }

section "Collection metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; id'
section "Block devices" bash -c 'lsblk -o NAME,PATH,TYPE,FSTYPE,FSVER,LABEL,UUID,SIZE,FSAVAIL,FSUSE%,MOUNTPOINTS,MODEL,SERIAL 2>/dev/null || lsblk'
section "Filesystem capacity" df -hT
section "Inode capacity" df -i
section "Mount table" findmnt -A
section "Persistent mounts" bash -c 'cat /etc/fstab 2>/dev/null || true'
section "Swap" bash -c 'swapon --show 2>/dev/null || cat /proc/swaps'

if have pvs; then section "LVM physical volumes" pvs -a -o +pv_used; fi
if have vgs; then section "LVM volume groups" vgs -a -o +vg_free; fi
if have lvs; then section "LVM logical volumes" lvs -a -o +devices,segtype,data_percent,metadata_percent; fi

section "Read-only and unusual mounts" bash -c 'findmnt -rn -o TARGET,FSTYPE,OPTIONS | awk "$3 ~ /(^|,)ro(,|$)/ || $3 ~ /errors=/"'
section "Kernel storage indicators" bash -c 'journalctl -k --since "24 hours ago" --no-pager 2>/dev/null | grep -Ei "I/O error|buffer I/O|filesystem error|read-only|nvme|ata[0-9]|scsi|ext4|xfs|btrfs" | tail -n 500 || true'

if have smartctl; then
  while read -r dev type; do
    [[ "$type" == "disk" ]] || continue
    section "SMART summary: $dev" smartctl -H -A "$dev"
  done < <(lsblk -dn -o PATH,TYPE)
fi

{
  echo 'source,target,fstype,size_bytes,used_bytes,available_bytes,used_percent,inode_used_percent,status'
  df -P -B1 --output=source,target,fstype,size,used,avail,pcent 2>/dev/null | tail -n +2 | while read -r src target fstype size used avail pcent; do
    pct="${pcent%%%}"
    inode="$(df -Pi "$target" 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5}')"
    status="OK"; [[ "${pct:-0}" -ge "$WARNING" || "${inode:-0}" -ge "$WARNING" ]] && status="WARNING"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$src" "$target" "$fstype" "$size" "$used" "$avail" "${pct:-0}" "${inode:-0}" "$status"
  done
} > "$CSV"

WARNINGS="$(awk -F, 'NR>1 && $9=="WARNING" {c++} END {print c+0}' "$CSV")"
DISKS="$(lsblk -dn -o TYPE | awk '$1=="disk" {c++} END {print c+0}')"
LVM_PRESENT=false; have lvs && lvs >/dev/null 2>&1 && LVM_PRESENT=true

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "physical_disks": ${DISKS:-0},
  "filesystems_over_threshold": ${WARNINGS:-0},
  "warning_threshold_percent": $WARNING,
  "lvm_detected": $LVM_PRESENT
}
EOF

printf '\nStorage analysis completed. Output: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
