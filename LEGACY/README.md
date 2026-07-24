# Legacy SYMUNAPI Utilities

These files are retained for building and inspecting the provider snapshot
consumed by the SymbOS daemon:

- `symunapi_msx.asm` builds the tracked root-level MSX-DOS snapshot utility.
- `unadump_scc.c` and `unadump_scc.o` are the old SymbOS metadata dump probe.

The daemon requires `A:/SYMBOS/SYMUNAPI.DAT` and
`A:/SYMBOS/SYMUNAPI.SEG` files captured from the currently loaded provider.
Build or refresh the root-level utility with:

```sh
make legacy-symunapi
```

Run it from `A:\SYMBOS` after the UNAPI provider and Wi-Fi configuration have
loaded. Run it again whenever that configuration changes, or use the repository
`AUTOEXEC.BAT` to refresh the snapshot on every boot. The daemon also accepts
the former drive-root locations for backward compatibility. The byte-by-byte
16 KiB capture can take a noticeable amount of time and must not be interrupted.
