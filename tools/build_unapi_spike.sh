#!/usr/bin/env bash
# Build and stage UNAPISPK.COM on a bootable Nextor image.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rasm >/dev/null || { echo "ERROR: rasm not on PATH" >&2; exit 1; }

mkdir -p build/msx QA/MSX/DIAG
( cd build/msx && rasm "$OLDPWD/tools/unapispike_msx.asm" )
[ -s build/msx/UNAPISPK.COM ] || { echo "ERROR: UNAPISPK.COM not produced" >&2; exit 1; }

UNAPI_PACK="${MSX_UNAPI_PACK:-/var/home/salvogendut/Downloads/onechipbook-wifi/OCM-SM.UNAPI.PACK.1.5/TO SDCARD ROOT (RAIZ CARTAO SD) RAM}"
OPENMSXNET_TSR="${MSX_OPENMSXNET_TSR:-../geobench/build/openmsxnet-test/UNAPINET.COM}"

rm -rf QA/MSX
mkdir -p QA/MSX/DIAG
if [ -d "$UNAPI_PACK" ] && [ -z "${MSX_UNAPI_TSR:-}" ]; then
    cp -a "$UNAPI_PACK"/. QA/MSX/
fi

cp build/msx/UNAPISPK.COM QA/MSX/DIAG/
rm -f QA/MSX/UNAPINET.COM
if [ -n "${MSX_UNAPI_TSR:-}" ] || [ -s "$OPENMSXNET_TSR" ]; then
    TSR="${MSX_UNAPI_TSR:-$OPENMSXNET_TSR}"
    [ -s "$TSR" ] || { echo "ERROR: MSX_UNAPI_TSR not found: $TSR" >&2; exit 1; }
    cp "$TSR" QA/MSX/UNAPINET.COM
    printf 'UNAPINET\r\nDIAG\\UNAPISPK\r\n' > QA/MSX/AUTOEXEC.BAT
elif [ -d "$UNAPI_PACK" ]; then
    {
        printf 'CD \\\r\n'
        printf 'SET PATH=A:\\;A:\\UNAPI;A:\\WIFI\r\n'
        printf 'ESP8266.COM\r\n'
        printf 'DIAG\\UNAPISPK\r\n'
    } > QA/MSX/AUTOEXEC.BAT
else
    printf 'DIAG\\UNAPISPK\r\n' > QA/MSX/AUTOEXEC.BAT
fi

bash tools/build_msx_img.sh QA/MSX QA/UNAPISPK.IMG
echo "Spike staged: QA/UNAPISPK.IMG autoruns UNAPISPK"
