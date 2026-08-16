# MSX TCP/IP UNAPI Backend Notes

## Sources Used

The backend shape is taken from:

- `../symsys-networkdaemon/Dmn-Network.asm`
- `../symsys-networkdaemon/Dmn-Network-W5100.asm`
- `../symsys-networkdaemon/Dmn-Network-M4CPC.asm`
- `../symsys-networkdaemon-1984/Dmn-Network-1984.asm`
- `../geobench/lib/gb/gbnet_unapi_stub.c`
- `../geobench/tools/gbspike_msx.asm`
- `../MSX-Development/UNAPI/TELNET/src/UnapiHelper.c`
- `../SymbOS-ASM-Developer-kit/LIB/SymbOS_Lib-NetworkDaemon.asm`
- `../symdoc-developer/SymbOS-Network.txt`

## Backend ABI Expected By The Daemon

The shared daemon calls the backend through these labels:

- `lowini` - initialize and configure hardware/network state.
- `lowtop` - open a TCP socket.
- `lowtcl` - close and release a TCP socket.
- `lowtst` - poll TCP status and available RX bytes.
- `lowtrx` - receive TCP bytes into an application bank/address.
- `lowttx` - send TCP bytes from an application bank/address.
- `lowtdc` - disconnect/abort TCP.
- `lowtsk` - skip received TCP bytes.
- `lowtfl` - flush TCP TX, optional.
- `lowuop/lowucl/lowust/lowurx/lowutx/lowusk` - UDP equivalents.

The daemon owns the SymbOS process messaging layer and socket records. The UNAPI
backend only maps between daemon sockets and UNAPI connection handles.

## Provider Snapshot And Import

The daemon imports `A:/SYMBOS/SYMUNAPI.DAT` and
`A:/SYMBOS/SYMUNAPI.SEG` files, with a drive-root fallback for existing
installations. The tracked `SYMUNAPI.COM` utility creates or refreshes this
snapshot under MSX-DOS by discovering TCP/IP UNAPI through EXTBIO:

1. Write `"TCP/IP",0` to the UNAPI argument buffer at `#F847`.
2. Call EXTBIO (`#FFCA`) with `A=0`, `DE=#2222`.
3. If `B=0`, no TCP/IP implementation exists.
4. Call EXTBIO with `A=1`, `DE=#2222` to obtain the selected implementation.
5. `A` is the slot, `B` is the segment, and `HL` is the entry address.
6. For a mapped provider (`HL < #C000`, segment other than `#FF`), obtain the
   UNAPI RAM helper with EXTBIO `A=#FF`.
7. Read the complete mapped 16K provider through RAMHELPR `READRAM`.
8. Write metadata to `SYMUNAPI.DAT` and the provider image to `SYMUNAPI.SEG` in
   the current directory.

The baseline snapshot committed at the repository root is used by QA. A
snapshot is not generally portable across mapped-provider builds or Wi-Fi
configurations. Run `SYMUNAPI.COM` after provider/Wi-Fi initialization whenever
those settings change. The repository `AUTOEXEC.BAT` does this on every boot
before launching SymbOS.

The daemon reserves `#0400-#FEFF` in a free SymbOS secondary bank and loads the
snapshot at its original `#4000` address. It installs a wrapper, private stack,
and call buffers in page 3, then enters the bank through `BNKCLL` and exits
through `BNKRET`.

This full-bank call is required on MSX. The `BNK16C` jump at `#8142` resolves
to a `RET` stub in the tested SymbOS kernel, so it does not execute a
16K-resident routine.

Direct page-3 and ROM-slot providers are left as later targets.

## TCP/IP UNAPI Calls

- `0` - `UNAPI_GET_INFO`
- `1` - `TCPIP_GET_CAPAB`
- `2` - `TCPIP_GET_IPINFO`
- `6` - `TCPIP_DNS_Q`
- `7` - `TCPIP_DNS_S`
- `13` - `TCPIP_TCP_OPEN`
- `14` - `TCPIP_TCP_CLOSE`
- `15` - `TCPIP_TCP_ABORT`
- `16` - `TCPIP_TCP_STATE`
- `17` - `TCPIP_TCP_SEND`
- `18` - `TCPIP_TCP_RCV`
- `29` - `TCPIP_WAIT`

The first milestone requires successful `GET_INFO`, `GET_CAPAB`, DNS query and
active TCP open/send/receive/close through openMSXnet.

## Provider Network Information

After initialization, the daemon uses `TCPIP_GET_IPINFO` to populate the
read-only TCP/IP status tab with the local IP address, subnet mask, default
gateway, and primary and secondary DNS servers. Unsupported fields are shown as
`0.0.0.0`; openMSXnet currently reports only the local IP, while the MSX-SM
provider reports all five fields.

## DNS Integration

The backend provides high-level DNS hook routines:

- `unadns` starts a DNS query for the 0-terminated hostname at `pck_buffer+3`.
- `unadnr` polls query status and returns the resolved IPv4 address in `IX/IY`
  using the same byte layout as the existing daemon DNS path:
  `IXL=ip0`, `IXH=ip1`, `IYL=ip2`, `IYH=ip3`.

`tools/generate_integrated_daemon.py` adds the `DRIVER=6` daemon branch that
routes DNS through `unadns/unadnr` instead of the UDP DNS path.

## Buffer Placement

`BNKCLL` replaces the application's complete 64K view. No application pointer
is valid while the provider is executing, so all register blocks and pointed-to
data are marshalled into the provider bank first.

The provider-bank layout is:

```text
4000-7FFF  Captured 16K UNAPI provider
C000-C3FF  TCP send/receive buffer
C400-C40C  TCP open parameter block
C500-C5FF  DNS name buffer
F800-...   UNAPI call wrapper
F880-...   Marshalled register block
FEF0       Interbank-call stack top
FF00-FFFF  SymbOS interbank jump routines
```

TCP send/receive copies between caller banks, the daemon transfer area, and the
provider bank with `BNKCOP`. Calls are clamped to the 1024-byte staging buffer;
larger sends use the daemon's partial-send contract.

## Status Mapping

UNAPI TCP states map to daemon socket states as follows:

- `2` or `3` (`SYN_SENT`, `SYN_RECEIVED`) -> daemon opening/in process.
- `4` (`ESTABLISHED`) -> daemon established.
- `7` (`CLOSE_WAIT`) and provider `CLOSED` remain logically established while
  the receive queue is drained. Some providers expose these states before all
  final bytes cross the provider boundary, so the backend probes in 1024-byte
  blocks and requires a two-second, MTGCNT-based quiet interval before
  publishing daemon closed.
- A provisional close before the first real received byte preserves the
  opening/established state; the client timeout remains authoritative for a
  connection that never produces a response.

Available RX bytes come from `TCPIP_TCP_STATE` output `HL`. The generated
`DRIVER=6` polling path preserves the larger of that count and the daemon's
cached unread count until `TCPRCV` consumes it, so a later close poll cannot
erase data that the application has not read.

## Implementation Risks

- The generated `DRIVER=6` daemon branch treats DHCP/manual IP configuration as
  backend-owned because TCP/IP UNAPI owns the network setup.
- Passive TCP and UDP are not implemented in the first backend file. Returning
  `neterrfnc` is preferable to pretending support exists.
- The imported provider consumes almost one complete 64K SymbOS bank, so the
  MSX should have at least 1MB RAM for normal use.
- The OCM/SM-X RAM provider uses the BIOS `H_TIMI` hook for some internal
  timeout counters. Successful operations do not depend on expiry, but timeout
  and missing-device paths still require explicit real-hardware stress testing
  under SymbOS.
- The bridge is verified under openMSXnet and on an OCM laptop using the
  OCM/SM-X UNAPI RAM package. Each environment must use a snapshot of its
  currently loaded provider.
