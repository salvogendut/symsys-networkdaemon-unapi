# SymbOS MSX UNAPI Network Daemon

This repository is the MSX TCP/IP UNAPI backend target for the SymbOS Network
Daemon.

The implementation is intended to reuse the existing daemon front-end and
SymbOS message API from `../symsys-networkdaemon`, while replacing the hardware
backend with TCP/IP UNAPI calls on MSX hosts.

## Source Layout

- `Dmn-Network-UNAPI.asm` - low-level backend contract for TCP/IP UNAPI.
- `Dmn-Network-#UNA.asm` - assembler wrapper for the UNAPI daemon variant.
- `docs/UNAPI_BACKEND.md` - design notes and implementation constraints.

## Current Scope

The current backend target is intentionally narrow:

- Detect a mapped TCP/IP UNAPI provider through EXTBIO while MSX-DOS and the
  BIOS are still active.
- Snapshot the provider with `SYMUNAPI.COM`, then import it into a
  SymbOS-owned secondary bank.
- Invoke the provider with SymbOS `BNKCLL`/`BNKRET`; the MSX kernel's
  `BNK16C` entry is an unimplemented stub and cannot be used.
- Provide active TCP client open/status/receive/send/close/disconnect.
- Route daemon DNS through TCP/IP UNAPI DNS calls.
- Defer passive TCP server and UDP until the TCP client path is verified on real
  MSX hardware and emulator setups.

ROM/direct providers are not imported yet. The current path requires the mapped
provider type used by OpenMSXnet and the OCM/SM-X RAM package.

## Build Notes

The existing daemon wrapper paths in `../symsys-networkdaemon` assume the
original SymbOS source tree layout and SjASM-style syntax. This repo keeps the
upstream source read-only and generates a local RASM-compatible integration file
under `build/`:

```sh
python3 tools/generate_integrated_daemon.py
```

The production executable is built with SCC:

```sh
make -j4
make check
```

This creates `netd-una-scc.exe` and copies it to `netd-una.exe`.

Stage the daemon and DOS snapshotter in the installed SymbOS QA image:

```sh
make stage-msx-symbos
```

The MSX-DOS boot order must be:

```text
UNAPINET              (or the real hardware UNAPI loader)
SYMBOS
```

`SYMBOS.BAT` runs `SYMUNAPI`, changes to `\SYMBOS`, and launches `SYM`.

Run the repository image with at least 1MB RAM:

```sh
tools/run_msx.sh QA/MSXSYMBOS.IMG
```

The daemon reserves one secondary bank (`0400h-FEFFh`) for the imported
provider, its private buffers, wrapper, and stack.

## MSX UNAPI Spike

Build a bootable diagnostic image:

```sh
make msx-spike
```

Run it in the same openMSX/openMSXnet setup used by GeoBench:

```sh
MSX_SHOTS="20 30" tools/run_msx.sh
```

For the emulator path, `make msx-spike` auto-detects the local openMSXnet TSR at:

```text
../geobench/build/openmsxnet-test/UNAPINET.COM
```

For the OCM/SM-X RAM-driver hardware path, the build can stage the pack from:

```text
/var/home/salvogendut/Downloads/onechipbook-wifi/OCM-SM.UNAPI.PACK.1.5/TO SDCARD ROOT (RAIZ CARTAO SD) RAM
```

Override that with `MSX_UNAPI_PACK=/path/to/pack`.

For openMSXnet specifically, provide its `UNAPINET.COM` TSR when building:

```sh
MSX_UNAPI_TSR=/path/to/UNAPINET.COM make msx-spike
MSX_SHOTS="20 30" tools/run_msx.sh
```

Without the TSR, the expected diagnostic result is "No TCP/IP UNAPI
implementation found". With it, `SYMUNAPI.COM` writes `SYMUNAPI.DAT` and
`SYMUNAPI.SEG`; the daemon reports `ONLINE` only after provider `GET_INFO` and
`GET_CAPAB` calls succeed.

The current smoke test resolves `localhost`, then connects to port 8080 through
openMSXnet. Run a host HTTP server while launching the emulator:

```sh
python3 -m http.server 8080 --bind 127.0.0.1
MSX_SHOTS="120" bash tools/run_msx.sh
```

In this environment the verified result is:

```text
DNS_Q err: 00
DNS OK: 7F.00.00.01
TCP_OPEN err: 00 handle: 01
TCP established
TCP_SEND err: 00
RX available: 0200
TCP_RCV err: 00 bytes: 0100
TCP_CLOSE err: 00
TCP smoke OK
```

The SymbOS-side `NETRAW 1.1.1.1 80` test has also been verified to return
`open res=0` through the imported provider.
