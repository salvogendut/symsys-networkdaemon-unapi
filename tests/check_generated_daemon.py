#!/usr/bin/env python3
"""Regression checks for UNAPI-only changes in the generated daemon."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build" / "Dmn-Network-UNAPI-integrated.asm"
BACKEND = ROOT / "Dmn-Network-UNAPI.asm"


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

    dns_start = text.index("if DRIVER==6        ;*** HIGH LEVEL BASED (TCP/IP UNAPI)")
    dns_end = text.index(
        "elseif M4BOARD==1        ;*** HIGH LEVEL BASED (using external function)",
        dns_start,
    )
    dns = text[dns_start:dns_end]
    start_call = require(dns, "        call unadns")
    error_branch = require(dns, "        jr c,dnsrqs1")
    clear_error = require(dns, "        xor a\ndnsrqs1 ld (dnsrqse),a")
    poll_error = require(
        dns,
        "dnsrqr  ld a,(dnsrqse)\n"
        "        or a\n"
        "        scf\n"
        "        ret nz\n"
        "        jp unadnr",
    )
    if not start_call < error_branch < clear_error < poll_error:
        raise SystemExit("UNAPI DNS start errors must be saved before polling")

    dns_poll_start = text.index("netdns  ld a,(ix+sckdatsta)")
    dns_poll = text[dns_poll_start : text.index(";### NETCMD", dns_poll_start)]
    require(
        dns_poll,
        "        ld de,dnsrqbuf\n"
        "        add hl,de               ;queued daemon-owned hostname",
    )
    unapi_start = dns_poll.index("if DRIVER==6")
    unapi_dns_poll = dns_poll[unapi_start : dns_poll.index("else", unapi_start)]
    if "jmp_bnkcop" in unapi_dns_poll:
        raise SystemExit("UNAPI DNS poll must not recopy from the caller bank")

    dns_request_start = text.index("dnsrsv  push de")
    dns_request = text[
        dns_request_start
        : text.index(
            "if DRIVER==6        ;*** HIGH LEVEL BASED", dns_request_start
        )
    ]
    require(
        dns_request,
        "        ld hl,pck_buffer\n"
        "        ld bc,256\n"
        "        ldir                    ;snapshot validated caller hostname",
    )
    require(text, "dnsrqbuf    ds 256*low_sockmax")

    backend = BACKEND.read_text(encoding="latin-1")
    dns_status = backend[backend.index("unadnr  call una_wait") :]
    require(
        dns_status,
        "        ld a,TCPIP_DNS_S\n"
        "        ld bc,#0100             ;B bit 0: consume this result/error",
    )

    print("generated UNAPI TCP and DNS checks passed")


if __name__ == "__main__":
    main()
