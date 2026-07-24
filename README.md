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
- `netd-una.exe` - SCC-built SymbOS network daemon.
- `SYMUNAPI.COM` - MSX-DOS mapped-provider snapshot utility.
- `SYMUNAPI.DAT` and `SYMUNAPI.SEG` - baseline QA provider snapshot.
- `AUTOEXEC.BAT` - openMSXnet/OCM boot template.
- `LEGACY/` - snapshot utility source and diagnostic utilities.

## Current Scope

The current backend target is intentionally narrow:

- Detect a mapped TCP/IP UNAPI provider through EXTBIO while MSX-DOS and the
  BIOS are still active.
- Import a persistent provider snapshot into a SymbOS-owned secondary bank.
- Invoke the provider with SymbOS `BNKCLL`/`BNKRET`; the MSX kernel's
  `BNK16C` entry is an unimplemented stub and cannot be used.
- Provide active TCP client open/status/receive/send/close/disconnect.
- Route daemon DNS through TCP/IP UNAPI DNS calls.
- Defer passive TCP server and UDP until the TCP client path is verified on real
  MSX hardware and emulator setups.

ROM/direct providers are not imported yet. The current path requires the mapped
provider type used by OpenMSXnet and the OCM/SM-X RAM package.

## Install On MSX And SymbOS

### Requirements

- An MSX capable of running SymbOS with at least 1 MB of mapper RAM.
- A working SymbOS installation on an MSX-DOS or Nextor drive.
- A mapped TCP/IP UNAPI provider loaded before SymbOS starts. The OCM/SM-X RAM
  Wi-Fi package is supported.
- `SYMUNAPI.COM` in the SymbOS directory to capture the active provider.

Build the production daemon with SCC:

```sh
make -j4
```

Copy the runtime programs to the SymbOS directory as:

```text
A:\SYMBOS\NETD-UNA.EXE
A:\SYMBOS\SYMUNAPI.COM
```

The utility is built from `LEGACY/symunapi_msx.asm` and the tracked binary can
be refreshed with:

```sh
make legacy-symunapi
```

`SYMUNAPI.COM` must run after the hardware UNAPI and Wi-Fi setup, but before
SymbOS. It writes `SYMUNAPI.DAT` and `SYMUNAPI.SEG` in the current directory.
These files contain a snapshot of the loaded provider and can change with its
Wi-Fi configuration.

The supplied `AUTOEXEC.BAT` recognizes the repository openMSXnet setup and the
standard OCM/SM-X RAM package layout. Install it at `A:\AUTOEXEC.BAT`. Its boot
order is:

```bat
REM Hardware UNAPI and Wi-Fi setup runs first
CD \SYMBOS
SYMUNAPI.COM
SYM
```

If the machine already has a customized `AUTOEXEC.BAT`, preserve its hardware
and Wi-Fi setup and add the final three commands after that setup. If
`SYMUNAPI.COM` is not run automatically, run it manually from `A:\SYMBOS`
whenever the Wi-Fi settings or UNAPI provider change, before starting SymbOS.
Capturing the 16 KiB mapped provider can take a noticeable amount of time; do
not interrupt the machine while `SYMUNAPI.COM` is running.

### Start The Daemon

From SymbOS, launch `A:\SYMBOS\NETD-UNA.EXE` with SymCommander or SymShell. For
normal use, add that executable to the SymbOS autostart list through Control
Panel so the daemon starts with the desktop.

A successful start creates the network tray icon. Open it and verify:

- Status is `ONLINE`.
- Adapter is `MSX TCP/IP UNAPI`.
- The TCP/IP tab shows the provider's local IP, subnet mask, gateway, and DNS
  addresses when the provider exposes them.

Network applications use the standard SymbOS Network Daemon API; no
application-specific UNAPI configuration is required. `NSLOOKUP`, `TELNET`,
`WGET`, and `SETTIME` have been tested with this daemon.

If the daemon reports `NO DEVICE`, verify that the UNAPI loader ran before
SymbOS and that the snapshot files match the active provider.

## Install In openMSX

The repository QA setup expects openMSXnet and the installed SymbOS image at
`QA/MSXSYMBOS.IMG`. Baseline snapshot files are tracked at the repository root:

```text
SYMUNAPI.DAT
SYMUNAPI.SEG
```

They are useful for QA, but must not be assumed to match a real machine's
current mapped provider and Wi-Fi state. The supplied `AUTOEXEC.BAT` refreshes
them on each boot.

Build and stage the current daemon into an existing image:

```sh
make -j4
make stage-msx-symbos
```

The staging target installs `netd-una.exe`, `SYMUNAPI.COM`, `AUTOEXEC.BAT`, and
the selected initial provider snapshot. Override the initial snapshot with:

```sh
make UNAPI_SNAPSHOT_DIR=/path/to/provider-snapshot stage-msx-symbos
```

Run the image with the openMSXnet extension and 1 MB mapper:

```sh
tools/run_msx.sh QA/MSXSYMBOS.IMG
```

The QA image boot sequence is:

```bat
UNAPINET
CD \SYMBOS
SYMUNAPI.COM
SYM
```

`QA/MSX` is unrelated to the installed SymbOS image. It is an ignored,
generated staging tree used only by the standalone `make msx-spike` diagnostic.

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

This creates the SCC-linked production executable `netd-una.exe`.

Stage the daemon in the installed SymbOS QA image:

```sh
make stage-msx-symbos
```

The MSX-DOS boot order for the QA image is:

```text
UNAPINET              (or the real hardware UNAPI loader)
CD \SYMBOS
SYMUNAPI.COM
SYM
```

The daemon requires current `A:/SYMBOS/SYMUNAPI.DAT` and
`A:/SYMBOS/SYMUNAPI.SEG` provider snapshots. `SYMUNAPI.COM` refreshes both
before SymbOS starts. The QA image builder's initial copies come from
`UNAPI_SNAPSHOT_DIR`, which defaults to the repository root.

Rebuild the tracked snapshot utility with:

```sh
make legacy-symunapi
```

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
implementation found". With it, the spike verifies UNAPI discovery and TCP
operations. The SymbOS daemon separately imports its persistent provider
snapshot and reports `ONLINE` only after provider `GET_INFO` and `GET_CAPAB`
calls succeed.

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

## Autostart TCP Probe

Build and install the SCC diagnostic under the existing SetTime autostart
entry:

```sh
make stage-settime-qa
```

This replaces only `SYMBOS/SETTIME.COM` in `QA/MSXSYMBOS.IMG`. The probe waits
up to 15 seconds for the daemon, allows the imported provider 10 seconds to
settle, resolves `example.com`, and runs two complete HTTP/1.0 transactions.
Each pass reports TCP open, send, receive/close, byte count, and the SymbOS
network error code on failure.

Two successful passes confirm that DNS, TCP send/receive, close, and provider
socket reuse all work. A message box displays the final result, while
`A:/SYMBOS/UNAPITST.LOG` records the latest checkpoint or result for unattended
boots. The executable is also available as `build/msx/SETTIME.COM`.

## WGET Receive Regression

Start the fragmented fixture server on an address reachable by the MSX:

```sh
python3 -u tests/http/wget_fixture_server.py --bind 0.0.0.0 --port 8081
```

Run the installed SymbOS WGET with the host's address:

```bat
A:\SYMBOS\CMD\WGET.COM http://HOST:8081/WGETFIX.TXT A:\SYMBOS\WGETOUT.TXT
```

The server splits the status line, headers, and body across separate TCP
arrivals, then closes immediately after the final fragment. A successful run
produces a 23-byte `WGETOUT.TXT` identical to `tests/http/WGETFIX.TXT`.
