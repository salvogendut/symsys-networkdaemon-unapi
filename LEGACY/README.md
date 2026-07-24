# Legacy SYMUNAPI Utilities

These files are retained for creating and inspecting the persistent provider
snapshot consumed by the SymbOS daemon:

- `symunapi_msx.asm` builds the one-time MSX-DOS snapshot utility.
- `unadump_scc.c` and `unadump_scc.o` are the old SymbOS metadata dump probe.

The daemon does not need `SYMUNAPI.COM` on every boot. It does still require
`A:/SYMBOS/SYMUNAPI.DAT` and `A:/SYMBOS/SYMUNAPI.SEG` files. The pair committed
at the repository root is verified with openMSXnet and the tested OCM/SM-X
setup. Build the legacy utility to capture another mapped provider with:

```sh
make legacy-symunapi
```

Run it once from `A:\SYMBOS` after the UNAPI provider has loaded. The daemon
also accepts the former drive-root locations for backward compatibility.
