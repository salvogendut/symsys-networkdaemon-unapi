#!/usr/bin/env bash
# Launch an MSX image in openMSX/openMSXnet.
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${1:-QA/MSXSYMBOS.IMG}"
MACHINE="${MSX_MACHINE:-Philips_NMS_8250}"
UNAPI_ENABLED="${MSX_UNAPI:-1}"
OPENMSXNET_HOME="${OPENMSXNET_HOME:-../geobench/QA/MSXDEPS/openmsxnet}"
[ -s "$IMG" ] || { echo "ERROR: $IMG not found - run tools/build_unapi_spike.sh" >&2; exit 1; }

EXT=(-ext SunriseIDE_Nextor)
case "${MSX_RAM:-1mb}" in
    stock) ;;
    512k) EXT+=(-ext ram512k) ;;
    1mb|1024k) EXT+=(-ext ram1mb) ;;
    2mb|2048k) EXT+=(-ext ram2mb) ;;
    4mb|4096k) EXT+=(-ext ram4mb) ;;
    *) echo "ERROR: unsupported MSX_RAM='${MSX_RAM}' (use stock, 512k, 1mb, 2mb, or 4mb)" >&2; exit 1 ;;
esac
[ "$UNAPI_ENABLED" = 1 ] && EXT+=(-ext unapinet)

ARGS=(-machine "$MACHINE" "${EXT[@]}" -hda "$IMG")
SCRIPT=

if [ -n "${MSX_SHOTS:-}" ]; then
    mkdir -p build/msx
    SCRIPT=$(mktemp -p build/msx --suffix=.tcl)
    trap 'rm -f "$SCRIPT"' EXIT
    {
        echo 'set throttle off'
        last=0
        for t in $MSX_SHOTS; do last=$t; done
        for t in $MSX_SHOTS; do
            action="catch { screenshot -raw $PWD/build/msx/unapispk-t$t.png }"
            [ "$t" = "$last" ] && action="$action ; exit"
            echo "after time $t { $action }"
        done
    } > "$SCRIPT"
    ARGS+=(-script "$SCRIPT")
    echo "headless run: screenshots at ${MSX_SHOTS}s -> build/msx/unapispk-t*.png"
elif [ -n "${MSX_SCRIPT:-}" ]; then
    ARGS+=(-script "$MSX_SCRIPT")
else
    mkdir -p build/msx
    SCRIPT=$(mktemp -p build/msx --suffix=.tcl)
    trap 'rm -f "$SCRIPT"' EXIT
    printf 'set throttle off\nafter realtime %s { set throttle on }\n' "${MSX_FF:-4}" > "$SCRIPT"
    ARGS+=(-script "$SCRIPT")
fi

if [ -n "${OPENMSX:-}" ]; then
    # shellcheck disable=SC2206
    OPENMSX_CMD=($OPENMSX)
elif [ "$UNAPI_ENABLED" = 1 ] && [ -x "$OPENMSXNET_HOME/openmsx" ]; then
    export OPENMSX_SYSTEM_DATA="${OPENMSX_SYSTEM_DATA:-$OPENMSXNET_HOME/share}"
    OPENMSXNET_BIN=$(realpath "$OPENMSXNET_HOME/openmsx")
    OPENMSXNET_DATA=$(realpath "$OPENMSX_SYSTEM_DATA")
    if LDD_OUT=$(ldd "$OPENMSXNET_BIN" 2>&1) &&
       [[ "$LDD_OUT" != *"not found"* ]]; then
        OPENMSX_CMD=("$OPENMSXNET_BIN")
    elif command -v distrobox >/dev/null 2>&1; then
        MSX_DISTROBOX="${MSX_DISTROBOX:-my-distrobox}"
        if DISTRO_LDD=$(distrobox enter "$MSX_DISTROBOX" -- \
            ldd "$OPENMSXNET_BIN" 2>&1) &&
           [[ "$DISTRO_LDD" != *"not found"* ]]; then
            OPENMSX_CMD=(distrobox enter "$MSX_DISTROBOX" -- env \
                "OPENMSX_SYSTEM_DATA=$OPENMSXNET_DATA" "$OPENMSXNET_BIN")
        else
            echo "ERROR: openMSXnet has unresolved libraries on the host and in distrobox '$MSX_DISTROBOX'" >&2
            exit 1
        fi
    else
        echo "ERROR: openMSXnet has unresolved host libraries and distrobox is unavailable" >&2
        exit 1
    fi
elif command -v openmsx >/dev/null 2>&1; then
    OPENMSX_CMD=(openmsx)
elif command -v flatpak >/dev/null 2>&1 && flatpak info org.openmsx.openMSX >/dev/null 2>&1; then
    OPENMSX_CMD=(flatpak run --command=openmsx org.openmsx.openMSX)
else
    echo "ERROR: openMSX not found" >&2
    exit 1
fi

exec "${OPENMSX_CMD[@]}" "${ARGS[@]}"
