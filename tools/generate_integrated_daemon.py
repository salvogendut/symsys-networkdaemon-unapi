#!/usr/bin/env python3
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT.parent / "symsys-networkdaemon" / "Dmn-Network.asm"
OUT = ROOT / "build" / "Dmn-Network-UNAPI-integrated.asm"
HEAD_SRC = ROOT.parent / "symsys-networkdaemon" / "Dmn-Network-Head.asm"
HEAD_OUT = ROOT / "build" / "Dmn-Network-Head-UNAPI.asm"
LIBS = (
    ROOT.parent / "symdoc-developer" / "symbos_lib-SystemManager.asm",
    ROOT.parent / "symdoc-developer" / "symbos_lib-DesktopManager.asm",
    ROOT.parent / "symdoc-developer" / "symbos_lib-FileManager.asm",
)


def replace_once(text, old, new):
    if old not in text:
        raise SystemExit(f"missing expected source pattern:\n{old}")
    return text.replace(old, new, 1)


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    head_text = HEAD_SRC.read_text(encoding="latin-1")
    HEAD_OUT.write_text(head_text, encoding="latin-1")
    print(f"generated {HEAD_OUT}")

    for lib in LIBS:
        lib_text = lib.read_text(encoding="latin-1")
        lib_text = re.sub(r"^[ \t]+(if|ifdef|elseif|else|endif)\b", r"\1", lib_text, flags=re.MULTILINE)
        lib_text = re.sub(r"^if ([A-Za-z0-9_]+)=1$", r"if \1", lib_text, flags=re.MULTILINE)
        lib_out = OUT.parent / lib.name
        lib_out.write_text(lib_text, encoding="latin-1")
        print(f"generated {lib_out}")

    text = SRC.read_text(encoding="latin-1")
    text = re.sub(
        r"^(if|elseif) ([A-Za-z0-9_]+)=(-?[0-9]+)",
        r"\1 \2==\3",
        text,
        flags=re.MULTILINE,
    )

    text = replace_once(text, '        cp "\\"', "        cp #5c")
    text = replace_once(
        text,
        'read"Dmn-Network-i18n.asm"',
        'include "../../symsys-networkdaemon/Dmn-Network-i18n.asm"',
    )
    text = replace_once(
        text,
        'read "..\\..\\..\\SRC-Main\\build.asm"',
        '            db "UNAPI"',
    )

    text = replace_once(
        text,
        "if DRIVER==2\ncfg_slots   db 0,0      ;index=0 as default for gr8net\nelse\ncfg_slots   db 1,0      ;pslot=1 as default for denyonet\nendif",
        (
            "if DRIVER==2\n"
            "cfg_slots   db 0,0      ;index=0 as default for gr8net\n"
            "elseif DRIVER==6\n"
            "cfg_slots   db 0,0      ;UNAPI owns the TCP/IP adapter setup\n"
            "else\n"
            "cfg_slots   db 1,0      ;pslot=1 as default for denyonet\n"
            "endif"
        ),
    )

    text = replace_once(
        text,
        "elseif DRIVER==4\n        db #fd:ld h,0",
        (
            "elseif DRIVER==6\n"
            "        ld c,32                 ;UNAPI link is backend-owned\n"
            "        ld a,c\n"
            "elseif DRIVER==4\n"
            "        db #fd:ld h,0"
        ),
    )

    text = replace_once(
        text,
        "else\n;### NETINI -> Initializes network hardware (W5100 based)",
        (
            "elseif DRIVER==6\n"
            ";### NETINI -> Initializes network hardware (TCP/IP UNAPI)\n"
            "netini  xor a\n"
            "        call lowini\n"
            "        ld a,0\n"
            "        jr c,netini0\n"
            "        ld a,-1\n"
            "netini0 ld (net_status),a\n"
            "        ld hl,staupdflg\n"
            "        set 3,(hl)\n"
            "        ret\n"
            "\n"
            ";### NETIPS -> initialize IP and DNS settings (TCP/IP UNAPI)\n"
            "netips  jp netini\n"
            "\n"
            "else\n"
            ";### NETINI -> Initializes network hardware (W5100 based)"
        ),
    )

    text = replace_once(
        text,
        "if M4BOARD==1        ;*** HIGH LEVEL BASED (using external function) for M4Board",
        (
            "if DRIVER==6        ;*** HIGH LEVEL BASED (TCP/IP UNAPI)\n"
            "\n"
            ";### DNSRQS -> send DNS request\n"
            ";### Input      HL=domain name string (dot separated, 0-terminated), A=socket\n"
            ";### Destroyed  AF,BC,DE,HL,IX,IYH\n"
            "dnsrqs  ld de,pck_buffer+3\n"
            "        ld bc,256\n"
            "        ldir\n"
            "        jp unadns\n"
            "\n"
            ";### DNSRQR -> check for DNS resolve\n"
            ";### Input      DNSRQS has been called before\n"
            ";### Output     CF=0 -> IP received, IX,IY=IP\n"
            ";###            CF=1 -> A=status (0=still in progress, >0=error)\n"
            ";### Destroyed  AF,BC,DE,HL,IX,IY\n"
            "dnsrqr  jp unadnr\n"
            "\n"
            "elseif M4BOARD==1        ;*** HIGH LEVEL BASED (using external function) for M4Board"
        ),
    )

    text = replace_once(
        text,
        "if DRIVER==0\n"
        "dhcbeg  ret\n"
        "dhcpol  ld a,-1\n"
        "        jp netini0\n"
        "\n"
        "elseif M4BOARD==1",
        (
            "if DRIVER==0\n"
            "dhcbeg  ret\n"
            "dhcpol  ld a,-1\n"
            "        jp netini0\n"
            "\n"
            "elseif DRIVER==6\n"
            "dhcbeg  ret\n"
            "dhcpol  ld a,-1\n"
            "        jp netini0\n"
            "\n"
            "elseif M4BOARD==1"
        ),
    )

    text = replace_once(
        text,
        'elseif DRIVER==5\ncfgdatids   db "M4 EP ESP8266":     ds 32-13\ncfgdatver   db 1,0\nendif',
        (
            'elseif DRIVER==5\n'
            'cfgdatids   db "M4 EP ESP8266":     ds 32-13\n'
            "cfgdatver   db 1,0\n"
            "elseif DRIVER==6\n"
            'cfgdatids   db "MSX TCP/IP UNAPI":  ds 32-15\n'
            "cfgdatver   db low_vermin,low_vermaj\n"
            "endif"
        ),
    )

    text = replace_once(
        text,
        'elseif DRIVER==4\nstatxttxa   db "Adapter: Net4CPC W5100S",0\nendif',
        (
            'elseif DRIVER==4\n'
            'statxttxa   db "Adapter: Net4CPC W5100S",0\n'
            "elseif DRIVER==6\n"
            'statxttxa   db "Adapter: MSX TCP/IP UNAPI",0\n'
            "endif"
        ),
    )

    text = replace_once(
        text,
        ";### STACFG -> opens/focus config window\n"
        "stacfg  ld a,(cfgwinid)\n"
        "        or a\n"
        "        jr nz,stacfg1",
        (
            ";### STACFG -> opens/focus config window\n"
            "stacfg\n"
            "if DRIVER==6\n"
            "        jp prgprz0             ;UNAPI provider owns TCP/IP settings\n"
            "stacfg1 jp prgprz0\n"
            "else\n"
            "        ld a,(cfgwinid)\n"
            "        or a\n"
            "        jr nz,stacfg1"
        ),
    )

    text = replace_once(
        text,
        "stacfg1 call SyDesktop_WINTOP\n"
        "        jp prgprz0\n"
        "\n"
        "if M4BOARD==1",
        (
            "stacfg1 call SyDesktop_WINTOP\n"
            "        jp prgprz0\n"
            "endif\n"
            "\n"
            "if M4BOARD==1"
        ),
    )

    text = replace_once(
        text,
        "elseif DRIVER==4\nstawingrpc  db 30,0:dw stawindatc,0,0,4*256+3,0,0,2\nendif",
        (
            "elseif DRIVER==4\n"
            "stawingrpc  db 30,0:dw stawindatc,0,0,4*256+3,0,0,2\n"
            "elseif DRIVER==6\n"
            "stawingrpc  db 18,0:dw stawindatc,0,0,4*256+3,0,0,2\n"
            "endif"
        ),
    )

    text = replace_once(
        text,
        "elseif DRIVER==4     ;*** Net4CPC ***************",
        (
            "elseif DRIVER==6     ;*** MSX TCP/IP UNAPI ******\n"
            "\n"
            "dw      0,  255*256+10\n"
            "stawindatc0 dw          stactllg0,     9,    27,     6,     6, 0    ;display     TX\n"
            "dw      0,  255*256+ 1, stactltxl,    18,    26,    60,     8, 0    ;description\n"
            "dw      0,  255*256+10, stactllg1,    39,    27,     6,     6, 0    ;display     LINK\n"
            "dw      0,  255*256+ 1, stactltxm,    48,    26,    60,     8, 0    ;description\n"
            "dw      0,  255*256+64,         0,     0,     0,     1,     1, 0    ;-\n"
            "dw      0,  255*256+64,         0,     0,     0,     1,     1, 0    ;-\n"
            "dw      0,  255*256+10, stactllg0,     9,    35,     6,     6, 0    ;display     RX\n"
            "dw      0,  255*256+ 1, stactltxo,    18,    34,    60,     8, 0    ;description\n"
            "dw      0,  255*256+64,         0,     0,     0,     1,     1, 0    ;-\n"
            "dw      0,  255*256+64,         0,     0,     0,     1,     1, 0    ;-\n"
            "dw      0,  255*256+64,         0,     0,     0,     1,     1, 0    ;-\n"
            "dw      0,  255*256+64,         0,     0,     0,     1,     1, 0    ;-\n"
            "dw      0,  255*256+ 3, stactlfrf,     0,    49,   155,    57, 0    ;frame Settings\n"
            "\n"
            "elseif DRIVER==4     ;*** Net4CPC ***************"
        ),
    )

    text = replace_once(
        text,
        "tcpopn1 ld (iy+sckdatsta),d\n"
        "        ld ix,tcpopns\n"
        "        push af\n"
        "        call lowtop\n"
        "        pop bc\n"
        "        ret c\n"
        "        ld a,b\n"
        "        ld (netscknum),a\n"
        "        ret\n",
        "tcpopn1 ld (iy+sckdatsta),d\n"
        "        ld ix,tcpopns\n"
        "        push af\n"
        "        call lowtop\n"
        "        pop bc\n"
        "        jr c,tcpopn3\n"
        "        ld a,b\n"
        "        ld (netscknum),a\n"
        "        ret\n"
        "tcpopn3 push af\n"
        "        ld (iy+sckdattyp),scktypfre\n"
        "        call sckdec\n"
        "        pop af\n"
        "        scf\n"
        "        ret\n",
    )

    text = replace_once(
        text,
        "tcpfls  call sckget\n"
        "        ret c\n"
        "        jp lowtfl\n",
        "tcpfls  ld c,scktyptcp\n"
        "        call sckget\n"
        "        ret c\n"
        "        jp lowtfl\n",
    )

    text = replace_once(
        text,
        "        call lowttx\n"
        "        call netdou\n"
        "        scf\n"
        "        ccf\n"
        "        ret\n",
        (
            "        call lowttx\n"
            "if DRIVER==6\n"
            "        ret c\n"
            "endif\n"
            "        call netdou\n"
            "        scf\n"
            "        ccf\n"
            "        ret\n"
        ),
    )

    text = replace_once(
        text,
        "stawindat   dw #3501,0,56,26,155,122,0,0,155,122,155,122,155,122,prgicnsml,statxttit,0,stamendat",
        (
            "if DRIVER==6\n"
            "stawindat   dw #3501,0,56,26,155,122,0,0,155,122,155,122,155,122,prgicnsml,statxttit,0,0\n"
            "else\n"
            "stawindat   dw #3501,0,56,26,155,122,0,0,155,122,155,122,155,122,prgicnsml,statxttit,0,stamendat\n"
            "endif"
        ),
    )

    text = replace_once(
        text,
        "App_MsgBuf ds 14",
        (
            "App_MsgBuf ds 14\n"
            "\n"
            "if DRIVER==6\n"
            ";### MSX TCP/IP UNAPI transfer-area call/buffer block\n"
            "una_tramp_fn       db 0\n"
            "una_tramp_a        db 0\n"
            "una_tramp_bc       dw 0\n"
            "una_tramp_de       dw 0\n"
            "una_tramp_hl       dw 0\n"
            "una_tramp_entry    dw 0\n"
            "una_trn_iobuf      ds UNA_IO_MAX\n"
            "una_trn_openbuf    ds 13\n"
            "una_trn_dnsbuf     ds 256\n"
            "endif"
        ),
    )

    text = replace_once(
        text,
        "prgend  ld a,(neticnid)",
        (
            "prgend\n"
            "if DRIVER==6\n"
            "        call una_shutdown\n"
            "endif\n"
            "        ld a,(neticnid)"
        ),
    )

    OUT.write_text(text, encoding="latin-1")
    print(f"generated {OUT}")


if __name__ == "__main__":
    main()
