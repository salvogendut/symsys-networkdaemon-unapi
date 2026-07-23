#!/usr/bin/env bash
# Build a bootable Nextor FAT16 hard-disk image for the UNAPI spike.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-QA/MSX}"
IMG="${2:-QA/UNAPISPK.IMG}"
SIZE_MB="${MSX_IMG_MB:-32}"
POFF=32
DEPS="${MSX_DEPS:-../geobench/QA/MSXDEPS}"

for t in sfdisk mkfs.fat mcopy; do
    command -v "$t" >/dev/null || { echo "ERROR: missing tool '$t'" >&2; exit 1; }
done
[ -s "$DEPS/NEXTOR.SYS" ] && [ -s "$DEPS/COMMAND2.COM" ] || {
    echo "ERROR: MSX deps incomplete at $DEPS" >&2
    exit 1
}

rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count="$SIZE_MB" status=none
printf 'label: dos\nstart=%s, type=06\n' "$POFF" | sfdisk -q "$IMG" >/dev/null
mkfs.fat -F16 --offset "$POFF" -n UNAPISPK "$IMG" >/dev/null

export MTOOLS_SKIP_CHECK=1
mcopy -i "$IMG@@$((POFF * 512))" "$DEPS/NEXTOR.SYS" "$DEPS/COMMAND2.COM" ::/
if [ -d "$SRC" ]; then
    mcopy -s -i "$IMG@@$((POFF * 512))" "$SRC"/* ::/
fi

echo "Built $IMG from $SRC using deps $DEPS"
