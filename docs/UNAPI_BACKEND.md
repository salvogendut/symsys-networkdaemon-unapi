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

## UNAPI Discovery

TCP/IP UNAPI is discovered through EXTBIO:

1. Write `"TCP/IP",0` to the UNAPI argument buffer at `#F847`.
2. Call EXTBIO (`#FFCA`) with `A=0`, `DE=#2222`.
3. If `B=0`, no TCP/IP implementation exists.
4. Call EXTBIO with `A=1`, `DE=#2222` to obtain the selected implementation.
5. `A` is the slot, `B` is the segment, and `HL` is the entry address.
6. If `HL >= #C000`, call the implementation directly.
7. If `HL < #C000` and the segment is not `#FF`, obtain the UNAPI RAM helper
   with EXTBIO `A=#FF`, then call through the helper with `IY=slot:segment` and
   `IX=entry`.

ROM-slot mapped implementations (`segment=#FF` with an entry below `#C000`) are
left as a later target. GeoBench currently treats these as unsupported too.

## TCP/IP UNAPI Calls

- `0` - `UNAPI_GET_INFO`
- `1` - `TCPIP_GET_CAPAB`
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

## DNS Integration

The backend provides high-level DNS hook routines:

- `unadns` starts a DNS query for the 0-terminated hostname at `pck_buffer+3`.
- `unadnr` polls query status and returns the resolved IPv4 address in `IX/IY`
  using the same byte layout as the existing daemon DNS path:
  `IXL=ip0`, `IXH=ip1`, `IYL=ip2`, `IYH=ip3`.

`tools/generate_integrated_daemon.py` adds the `DRIVER=6` daemon branch that
routes DNS through `unadns/unadnr` instead of the UDP DNS path.

## Buffer Placement

UNAPI calls may page out the daemon's page-1 code while executing. Any buffer
given to UNAPI must live in memory that remains visible to the implementation.

The backend reserves a page-3 staging buffer at `una_iobuf`. TCP send/receive
copy between SymbOS application banks and this buffer with the kernel
`jmp_bnkcop` service before calling UNAPI. Each low-level call is clamped to the
1024-byte staging buffer; larger sends rely on the daemon's existing partial
send contract and should be retried by the caller.

## Status Mapping

UNAPI TCP states map to daemon socket states as follows:

- `2` or `3` (`SYN_SENT`, `SYN_RECEIVED`) -> daemon opening/in process.
- `4` (`ESTABLISHED`) -> daemon established.
- `7` (`CLOSE_WAIT`) -> daemon close-wait.
- anything else after a failed state call -> daemon closed.

Available RX bytes come from `TCPIP_TCP_STATE` output `HL`.

## Implementation Risks

- The generated `DRIVER=6` daemon branch treats DHCP/manual IP configuration as
  backend-owned because TCP/IP UNAPI owns the network setup.
- Passive TCP and UDP are not implemented in the first backend file. Returning
  `neterrfnc` is preferable to pretending support exists.
- Cross-bank memory copies now use `jmp_bnkcop`, but still need real SymbOS
  runtime verification under openMSX with the daemon loaded.
