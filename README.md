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

The first backend target is intentionally narrow:

- Detect TCP/IP UNAPI through EXTBIO using the `"TCP/IP"` implementation name.
- Support direct page-3 implementations and mapped page-1 implementations via
  the UNAPI RAM helper.
- Provide active TCP client open/status/receive/send/close/disconnect.
- Route daemon DNS through TCP/IP UNAPI DNS calls.
- Defer passive TCP server and UDP until the TCP client path is verified on real
  MSX hardware and emulator setups.

This follows the GeoBench MSX UNAPI work, especially the rule that I/O buffers
used by UNAPI must live outside the application page because mapped UNAPI calls
may replace page 1.

## Build Notes

The existing daemon wrapper paths in `../symsys-networkdaemon` assume the
original SymbOS source tree layout and SjASM-style syntax. This repo keeps the
upstream source read-only and generates a local RASM-compatible integration file
under `build/`:

```sh
python3 tools/generate_integrated_daemon.py
```

`make check` syntax-checks `Dmn-Network-UNAPI.asm` in isolation and assembles the
integrated daemon wrapper. The current integrated artifact is:

```text
netd-una.exe
```

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
implementation found"; with it, the probe reports implementation count,
slot/segment/entry, call path, `GET_INFO`, `GET_CAPAB`, DNS, and active TCP.

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
