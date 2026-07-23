#!/usr/bin/env bash
# Build a bootable Nextor FAT16 image containing the real MSX SymbOS tree.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${MSX_SYMBOS_ROOT:-/var/home/salvogendut/Downloads/MSXSYMBOS}"
IMG="${1:-QA/MSXSYMBOS.IMG}"
SIZE_MB="${MSX_IMG_MB:-64}"
POFF=32
DEPS="${MSX_DEPS:-../geobench/QA/MSXDEPS}"
OPENMSXNET_TSR="${MSX_OPENMSXNET_TSR:-../geobench/build/openmsxnet-test/UNAPINET.COM}"

for t in sfdisk mkfs.fat mcopy mmd; do
    command -v "$t" >/dev/null || { echo "ERROR: missing tool '$t'" >&2; exit 1; }
done
[ -d "$SRC/SYMBOS" ] || { echo "ERROR: SymbOS tree not found at $SRC" >&2; exit 1; }
[ -s "$SRC/SYMBOS/SYM.COM" ] || { echo "ERROR: missing $SRC/SYMBOS/SYM.COM" >&2; exit 1; }
[ -s "$SRC/SYMBOS/NETD-UNA.EXE" ] || { echo "ERROR: missing $SRC/SYMBOS/NETD-UNA.EXE" >&2; exit 1; }
[ -s "$DEPS/NEXTOR.SYS" ] && [ -s "$DEPS/COMMAND2.COM" ] || {
    echo "ERROR: MSX deps incomplete at $DEPS" >&2
    exit 1
}
[ -s "$OPENMSXNET_TSR" ] || { echo "ERROR: missing openMSXnet TSR at $OPENMSXNET_TSR" >&2; exit 1; }
[ -s build/msx/SYMUNAPI.COM ] || { echo "ERROR: missing build/msx/SYMUNAPI.COM" >&2; exit 1; }
[ -s SYMBOS.BAT ] || { echo "ERROR: missing SYMBOS.BAT" >&2; exit 1; }

mkdir -p QA
rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count="$SIZE_MB" status=none
printf 'label: dos\nstart=%s, type=06\n' "$POFF" | sfdisk -q "$IMG" >/dev/null
mkfs.fat -F16 --offset "$POFF" -n MSXSYMBOS "$IMG" >/dev/null

export MTOOLS_SKIP_CHECK=1
MTOOL="-i $IMG@@$((POFF * 512))"

# shellcheck disable=SC2086
mcopy $MTOOL "$DEPS/NEXTOR.SYS" "$DEPS/COMMAND2.COM" ::/
# shellcheck disable=SC2086
mcopy $MTOOL "$OPENMSXNET_TSR" ::/UNAPINET.COM
mcopy $MTOOL build/msx/SYMUNAPI.COM ::/SYMUNAPI.COM
mcopy $MTOOL SYMBOS.BAT ::/SYMBOS.BAT
printf 'UNAPINET\r\nSYMBOS\r\n' > build/msx-autoexec.bat
# shellcheck disable=SC2086
mcopy $MTOOL build/msx-autoexec.bat ::/AUTOEXEC.BAT

# mcopy creates the destination directory when copying a directory with -s, but
# explicit creation gives clearer errors if the image is not writable.
# shellcheck disable=SC2086
mmd $MTOOL ::/SYMBOS
# shellcheck disable=SC2086
mcopy -s $MTOOL "$SRC/SYMBOS"/* ::/SYMBOS/
if [ -s "$SRC/SYMBOS.INI" ]; then
    # shellcheck disable=SC2086
    mcopy $MTOOL "$SRC/SYMBOS.INI" ::/SYMBOS.INI
fi
if [ -s "$SRC/SYMBOS/SYMBOS.CFG" ]; then
    # shellcheck disable=SC2086
    mcopy $MTOOL "$SRC/SYMBOS/SYMBOS.CFG" ::/SYMBOS.CFG
fi

echo "Built $IMG from $SRC with openMSXnet UNAPINET.COM"
