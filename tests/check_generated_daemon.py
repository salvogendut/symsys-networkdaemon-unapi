#!/usr/bin/env python3
"""Regression checks for UNAPI-only changes in the generated daemon."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build" / "Dmn-Network-UNAPI-integrated.asm"


def require(section: str, fragment: str) -> int:
    count = section.count(fragment)
    if count != 1:
        raise SystemExit(
            f"expected one generated occurrence of {fragment!r}, found {count}"
        )
    return section.index(fragment)


def main() -> None:
    text = SOURCE.read_text(encoding="latin-1")
    start = text.index("nettcp  ld a,c")
    end = text.index(";### NETUDP -> manages UDP socket", start)
    tcp = text[start:end]

    merge = require(tcp, "; A provider close/status poll must not erase bytes")
    compare = require(tcp, "        ld l,(ix+sckdatsta)\n        cp l")
    cached_low = require(
        tcp,
        "        ld (ix+sckdatrcv+0),c  ;update even if status is unchanged",
    )
    cached_high = require(tcp, "        ld (ix+sckdatrcv+1),b\n        pop de")
    require(tcp, "        sbc hl,de\n        jr nc,nettcp6_count")
    require(tcp, "        ld c,e\n        ld b,d                  ;keep the larger cached count")
    ready = require(tcp, "        set 7,a                 ;cached bytes remain readable")

    if not merge < cached_low < cached_high < ready < compare:
        raise SystemExit(
            "UNAPI pending-count merge must finish before the status equality shortcut"
        )

    # The larger generated TCP path must use absolute branches at its edges.
    require(text, "        jp z,netudp\n        jp netdns")
    require(tcp, "        jp z,netpol0\nnettcp2")
    require(tcp, "        call nettcp3\n        jp netpol0")

    print("generated UNAPI TCP pending-count checks passed")


if __name__ == "__main__":
    main()
