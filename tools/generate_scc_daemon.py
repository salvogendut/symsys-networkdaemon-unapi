#!/usr/bin/env python3
from pathlib import Path
import os
import re


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
OUT = BUILD / "netd-una-scc.s"
DIAG_MODE = os.environ.get("SCC_BOOT_DIAG", "")
FLATTEN_DEFAULT_LANGUAGE = os.environ.get("SCC_FLATTEN_LANG", "1") != "0"

SOURCES = [
    ROOT.parent / "SymbOS-ASM-Developer-kit" / "LIB" / "SymbOS-Constants.asm",
    BUILD / "Dmn-Network-Head-UNAPI.asm",
    BUILD / "symbos_lib-SystemManager.asm",
    BUILD / "symbos_lib-DesktopManager.asm",
    BUILD / "symbos_lib-FileManager.asm",
    ROOT / "Dmn-Network-UNAPI.asm",
    BUILD / "Dmn-Network-UNAPI-integrated.asm",
]

EXTRA_CONSTANTS = {
    "DRIVER": 6,
    "M4BOARD": 0,
    "low_buflen": 0,
    "relocate_count": 0,
    "MSC_SYS_EXTFNC": 30,
    "FNC_DXT_LNGLOD": 12,
}

SECTION_LABELS = {
    "relocate_start": ".code",
    "App_BegCode": "App_BegCode:",
    "App_BegData": ".symdata\nApp_BegData:",
    "App_BegTrns": ".symtrans\nApp_BegTrns:",
    "App_EndTrns": "App_EndTrns:",
}

NO_COLON = {
    "adc", "add", "and", "bit", "call", "ccf", "cp", "cpd", "cpdr", "cpi", "cpir",
    "cpl", "daa", "db", "dec", "di", "djnz", "ds", "dw", "ei", "ex", "exx",
    "halt", "im", "in", "inc", "ind", "indr", "ini", "inir", "jp", "jr", "ld",
    "ldd", "lddr", "ldi", "ldir", "neg", "nop", "or", "otdr", "otir", "out",
    "outd", "outi", "pop", "push", "res", "ret", "reti", "retn", "rl", "rla",
    "rlc", "rlca", "rld", "rr", "rra", "rrc", "rrca", "rrd", "rst", "sbc",
    "scf", "set", "sla", "sll", "sra", "srl", "sub", "xor", "equ", "include",
    "list", "nolist", "macro", "endm", "if", "ifdef", "elseif", "else", "endif",
    "cond", "endc",
}

DATA_OPS = {"db", "dw", "ds"}


def strip_comment(line: str) -> tuple[str, str]:
    in_quote = False
    quote = ""
    for i, ch in enumerate(line):
        if ch in ("'", '"'):
            if not in_quote:
                in_quote = True
                quote = ch
            elif quote == ch:
                in_quote = False
        elif ch == ";" and not in_quote:
            return line[:i], line[i:]
    return line, ""


def split_statements(line: str) -> list[str]:
    code, comment = strip_comment(line.rstrip("\n"))
    parts = []
    in_quote = False
    quote = ""
    start = 0
    for i, ch in enumerate(code):
        if ch in ("'", '"'):
            if not in_quote:
                in_quote = True
                quote = ch
            elif quote == ch:
                in_quote = False
        elif ch == ":" and not in_quote:
            part = code[start:i].rstrip()
            if part:
                parts.append(part)
            start = i + 1
    tail = code[start:].rstrip()
    if tail or comment:
        parts.append((tail + (" " + comment if comment and tail else comment)).rstrip())
    return parts or [line.rstrip("\n")]


def include_line(line: str, base: Path) -> list[str]:
    code, _ = strip_comment(line)
    m = re.match(r'\s*include\s+"([^"]+)"', code, flags=re.I)
    if not m:
        return [line]
    rel = m.group(1).replace("\\", "/")
    path = (base / rel).resolve()
    if not path.exists():
        path = (ROOT / rel).resolve()
    return flatten(path)


def flatten(path: Path) -> list[str]:
    out = []
    for raw in path.read_text(encoding="latin-1").splitlines():
        out.extend(include_line(raw, path.parent))
    return out


def parse_equ(line: str):
    code, _ = strip_comment(line)
    m = re.match(r"\s*([A-Za-z_.$][A-Za-z0-9_.$]*)\s+equ\s+(.+?)\s*$", code, flags=re.I)
    if not m:
        return None
    expr = m.group(2).strip()
    if re.fullmatch(r"-?\d+", expr):
        return m.group(1), int(expr)
    if re.fullmatch(r"#[0-9A-Fa-f]+", expr):
        return m.group(1), int(expr[1:], 16)
    return None


def eval_expr(expr: str, constants: dict[str, int]) -> bool:
    expr = expr.strip()
    m = re.fullmatch(r'("?)([A-Za-z_.$][A-Za-z0-9_.$]*)\1\s*(==|=)\s*(-?\d+|#[0-9A-Fa-f]+)', expr)
    if m:
        value = int(m.group(4)[1:], 16) if m.group(4).startswith("#") else int(m.group(4))
        return constants.get(m.group(2), 0) == value
    m = re.fullmatch(r"([A-Za-z_.$][A-Za-z0-9_.$]*)", expr)
    if m:
        return constants.get(m.group(1), 0) != 0
    m = re.fullmatch(r"([A-Za-z_.$][A-Za-z0-9_.$]*)\s*=\s*1", expr)
    if m:
        return constants.get(m.group(1), 0) == 1
    return False


def filter_conditionals(lines: list[str], constants: dict[str, int]) -> list[str]:
    out = []
    stack = []
    skipping_macro = False

    def active():
        return all(frame["active"] for frame in stack)

    for line in lines:
        code, comment = strip_comment(line)
        stripped = code.strip()
        low = stripped.lower()

        if skipping_macro:
            if low in ("endm", "mend"):
                skipping_macro = False
            continue
        if low.startswith("macro "):
            skipping_macro = True
            continue

        m = re.match(r"(if|ifdef)\s+(.+)$", stripped, flags=re.I)
        if m:
            cond = eval_expr(m.group(2), constants) if active() else False
            stack.append({"parent": active(), "seen": cond, "active": active() and cond})
            continue

        m = re.match(r"elseif\s+(.+)$", stripped, flags=re.I)
        if m:
            frame = stack[-1]
            cond = (not frame["seen"]) and eval_expr(m.group(1), constants) if frame["parent"] else False
            frame["active"] = frame["parent"] and cond
            frame["seen"] = frame["seen"] or cond
            continue

        if low == "else":
            frame = stack[-1]
            cond = frame["parent"] and not frame["seen"]
            frame["active"] = cond
            frame["seen"] = True
            continue

        if low == "endif":
            stack.pop()
            continue

        if active():
            equ = parse_equ(line)
            if equ:
                constants[equ[0]] = equ[1]
            out.append(line)

    if stack:
        raise SystemExit("unterminated conditional assembly block")
    return out


def apply_diagnostic_startup(lines: list[str]) -> list[str]:
    if not DIAG_MODE:
        return lines
    out = []
    skipping = False
    defer_netini = DIAG_MODE in ("post-ui-netini", "unapi-probe-extbio-count")
    skipped_startup_netini = False
    for line in lines:
        if DIAG_MODE == "fast" and line.strip() == "prgprz  call SySystem_HLPINI":
            out.append("prgprz  xor a")
            skipping = True
            continue
        if skipping:
            if line.strip() == "call netini":
                skipping = False
            continue
        if DIAG_MODE == "skip-netini" and line.strip() == "call netini":
            out.append("        xor a")
            continue
        if defer_netini and line.strip() == "call netini" and not skipped_startup_netini:
            out.append("        xor a")
            skipped_startup_netini = True
            continue
        if defer_netini and skipped_startup_netini and line.strip() == "prgprz0 rst #30":
            out.append("        call netini")
            out.append(line)
            skipped_startup_netini = False
            continue
        out.append(line)
    return out


def apply_unapi_probe_overrides(lines: list[str]) -> list[str]:
    if DIAG_MODE != "unapi-probe-extbio-count":
        return lines

    out = []
    replacing = False
    for line in lines:
        if not replacing and line.startswith("unaini  "):
            replacing = True
            out.extend([
                "unaini  or a",
                "        jr z,unaini_probe",
                "        cp 5",
                "        jr z,unaini_probe",
                "        xor a",
                "        ret",
                "unaini_probe",
                "        ld hl,una_tcpip_name",
                "        ld de,UNAPI_ARG",
                "        ld bc,7",
                "        ldir",
                "        xor a",
                "        ld de,#2222",
                "        ld bc,0",
                "        ld hl,0",
                "        call una_extbio",
                "        scf",
                "        ld a,neterrnhw",
                "        ret",
            ])
            continue
        if replacing:
            if line.startswith("una_tcpip_name"):
                replacing = False
                out.append(line)
            continue
        out.append(line)
    return out


def apply_startup_overrides(lines: list[str]) -> list[str]:
    if not FLATTEN_DEFAULT_LANGUAGE:
        return lines
    out = []
    for line in lines:
        if line.strip() == "call prglng":
            out.append("        xor a")
            continue
        out.append(line)
    return out


def convert_numbers(text: str) -> str:
    text = re.sub(r"#([0-9A-Fa-f]+)", lambda m: str(int(m.group(1), 16)), text)
    text = re.sub(r"%([01]+)", lambda m: str(int(m.group(1), 2)), text)
    text = re.sub(r"(?<![#A-Za-z0-9_])0([0-9]+)\b", lambda m: str(int(m.group(0), 10)), text)
    text = re.sub(
        r"\b(\d+)\s*\*\s*(\d+)\s*([+-])\s*(\d+)\b",
        lambda m: str(int(m.group(1)) * int(m.group(2)) + (int(m.group(4)) if m.group(3) == "+" else -int(m.group(4)))),
        text,
    )
    text = re.sub(
        r"\b(\d+)\s*\*\s*(\d+)\b",
        lambda m: str(int(m.group(1)) * int(m.group(2))),
        text,
    )
    text = re.sub(
        r"\b(\d+)\s*\+\s*(\d+)\b",
        lambda m: str(int(m.group(1)) + int(m.group(2))),
        text,
    )
    return text


def first_token(code: str) -> tuple[str, str]:
    m = re.match(r"\s*([A-Za-z_.$][A-Za-z0-9_.$]*)(.*)$", code)
    if not m:
        return "", code
    return m.group(1), m.group(2).lstrip()


def colonize(line: str) -> str:
    code, comment = strip_comment(line)
    indent = re.match(r"\s*", code).group(0)
    stripped = code.strip()
    if not stripped:
        return line
    if stripped.startswith(".") or stripped.endswith(":"):
        return line
    if re.match(r"\s*[A-Za-z_.$][A-Za-z0-9_.$]*:", code):
        return line
    token, rest = first_token(code)
    if not token:
        return line
    if token.lower() in NO_COLON:
        return line
    if rest.lower().startswith("equ "):
        return line
    if not rest:
        return f"{indent}{token}:{comment}"
    return f"{indent}{token}: {rest}{comment}"


def section_and_header_fix(line: str) -> list[str]:
    code, comment = strip_comment(line)
    stripped = code.strip()
    if stripped in SECTION_LABELS:
        return SECTION_LABELS[stripped].splitlines()
    if stripped in ("relocate_table", "relocate_end"):
        return []
    if re.match(r"\s*dw\s+App_BegData-App_BegCode\b", code):
        return ["dw 0"]
    if re.match(r"\s*dw\s+App_BegTrns-App_BegData\b", code):
        return ["dw 0"]
    if re.match(r"\s*dw\s+App_EndTrns-App_BegTrns\b", code):
        return ["dw 0"]
    if re.match(r"\s*prgdatadr:?\s+dw\s+(#1000|4096)\b", code, flags=re.I):
        return ["prgdatadr: dw 0" + (" " + comment if comment else "")]
    if re.match(r"\s*prgtrnadr:?\s+dw\s+relocate_count\b", code, flags=re.I):
        return ["prgtrnadr: dw 0"]
    if re.match(r"\s*prgprztab:?\s+dw\s+prgstk-App_BegTrns\b", code, flags=re.I):
        return ["prgprztab: dw 128"]
    if re.match(r"\s*db\s+1\s*$", code) and "flags" in comment:
        return ["db 0"]
    return [line]


def replace_char_literals(code: str) -> str:
    def repl(match):
        return str(ord(match.group(1)))

    if re.match(r"\s*(db|ascii)\b", code, flags=re.I):
        return code
    return re.sub(r'"([^"])"', repl, code)


def rewrite_pseudo_registers(line: str) -> list[str]:
    code, comment = strip_comment(line)
    stripped = code.strip()
    label_prefix = ""
    mlabel = re.match(r"([A-Za-z_.$][A-Za-z0-9_.$]*:\s*)(.+)$", stripped)
    if mlabel:
        label_prefix = mlabel.group(1)
        stripped = mlabel.group(2).strip()
    pseudo = {
        "ixh": ("221", "h"),
        "ixl": ("221", "l"),
        "iyh": ("253", "h"),
        "iyl": ("253", "l"),
    }

    m = re.match(r"(ld|inc|dec)\s+(ixh|ixl|iyh|iyl)\b(.*)$", stripped, flags=re.I)
    if m:
        op, reg, rest = m.groups()
        prefix, real = pseudo[reg.lower()]
        return [f"{label_prefix}db {prefix}", f"{op} {real}{rest}{(' ' + comment) if comment else ''}"]

    m = re.match(r"ld\s+(ix|iy)\s*,\s*(.+)$", stripped, flags=re.I)
    if m:
        prefix = "221" if m.group(1).lower() == "ix" else "253"
        return [f"{label_prefix}db {prefix}", f"ld hl,{m.group(2)}{(' ' + comment) if comment else ''}"]

    m = re.match(r"ld\s+\((.+)\)\s*,\s*(ix|iy)\s*$", stripped, flags=re.I)
    if m:
        prefix = "221" if m.group(2).lower() == "ix" else "253"
        return [f"{label_prefix}db {prefix}", f"ld ({m.group(1)}),hl{(' ' + comment) if comment else ''}"]

    m = re.match(r"ld\s+a\s*,\s*(ixh|ixl|iyh|iyl)\s*$", stripped, flags=re.I)
    if m:
        prefix, real = pseudo[m.group(1).lower()]
        return [f"{label_prefix}db {prefix}", f"ld a,{real}{(' ' + comment) if comment else ''}"]

    m = re.match(r"(or|and|cp|add|adc|sbc|sub)\s+(ixh|ixl|iyh|iyl)\s*$", stripped, flags=re.I)
    if m:
        prefix, real = pseudo[m.group(2).lower()]
        return [f"{label_prefix}db {prefix}", f"{m.group(1)} {real}{(' ' + comment) if comment else ''}"]

    return [line]


def normalize_accumulator_arithmetic(line: str) -> str:
    m = re.match(r"(\s*(?:[A-Za-z_.$][A-Za-z0-9_.$]*:\s*)?)(add|adc|sbc)\s+(.+)$", line, flags=re.I)
    if not m:
        return line
    prefix, op, operand = m.groups()
    if "," in operand:
        return line
    operand = operand.strip()
    if op.lower() == "add" and operand.lower() == "a":
        operand = "a"
    return f"{prefix}{op} a,{operand}"


def split_db_items(items: str) -> list[str]:
    out = []
    in_quote = False
    quote = ""
    start = 0
    for i, ch in enumerate(items):
        if ch in ("'", '"'):
            if not in_quote:
                in_quote = True
                quote = ch
            elif quote == ch:
                in_quote = False
        elif ch == "," and not in_quote:
            out.append(items[start:i].strip())
            start = i + 1
    out.append(items[start:].strip())
    return out


def split_db_strings(line: str) -> list[str]:
    code, comment = strip_comment(line)
    m = re.match(r"(\s*(?:(?:[A-Za-z_.$][A-Za-z0-9_.$]*:)\s*)?)db\s+(.+)$", code, flags=re.I)
    if not m or '"' not in m.group(2):
        return [line]
    label, items = m.groups()
    out = []
    pending = []
    first = True

    def flush_pending():
        nonlocal first, pending
        if pending:
            out.append(("db " if not first else label + "db ") + ",".join(pending))
            first = False
            pending = []

    for item in split_db_items(items):
        if re.fullmatch(r'"[^"]*"', item):
            flush_pending()
            out.append((".ascii " if not first else label + ".ascii ") + item)
            first = False
        else:
            pending.append(item)
    flush_pending()
    if comment and out:
        out[-1] += " " + comment
    return out


def split_long_data(line: str) -> list[str]:
    code, comment = strip_comment(line)
    m = re.match(r"(\s*(?:[A-Za-z_.$][A-Za-z0-9_.$]*:\s*)?(db|dw)\s+)(.+)$", code, flags=re.I)
    if not m:
        return [line]
    prefix, op, items = m.groups()
    parts = []
    cur = ""
    in_quote = False
    quote = ""
    start = 0
    split_items = []
    split_items = split_db_items(items)
    chunk = []
    first = True
    for item in split_items:
        tentative = ",".join(chunk + [item])
        if chunk and len((f"{op} " if not first else prefix) + tentative) > 48:
            parts.append((prefix if first else f"{op} ") + ",".join(chunk))
            first = False
            chunk = [item]
        else:
            chunk.append(item)
    if chunk:
        parts.append((prefix if first else f"{op} ") + ",".join(chunk) + (" " + comment if comment else ""))
    return parts


def split_dollar_icon(line: str) -> list[str]:
    code, comment = strip_comment(line)
    m = re.match(
        r"\s*([A-Za-z_.$][A-Za-z0-9_.$]*)\s+db\s+([^:]+):dw\s+\$\+7(?:,\s*|\s*:dw\s+)\$\+4\s*,\s*([^:]+):db\s+([^:]+):\s*db\s+(.+)$",
        code,
        flags=re.I,
    )
    if m:
        label, dims, length, mode, data = m.groups()
        return [
            f"{label}: db {dims}",
            f"dw {label}_gfx",
            f"dw {label}_mode,{length}",
            f"{label}_mode: db {mode}",
            f"{label}_gfx: db {data}{(' ' + comment) if comment else ''}",
        ]
    return [line]


def convert_line(line: str) -> list[str]:
    out = []
    for icon_line in split_dollar_icon(line):
        for part in split_statements(icon_line):
            for fixed in section_and_header_fix(part):
                code, _comment = strip_comment(fixed)
                if code.strip().lower() in ("list", "nolist"):
                    continue
                converted = convert_numbers(colonize(replace_char_literals(code.rstrip())))
                converted = normalize_accumulator_arithmetic(converted)
                converted = re.sub(r"\badd\s+a,65-97\b", "sub 32", converted, flags=re.I)
                for regline in rewrite_pseudo_registers(converted):
                    for dbline in split_db_strings(regline):
                        out.extend(split_long_data(dbline))
    return out


def rewrite_multiline_dollar_icons(lines: list[str]) -> list[str]:
    out = []
    i = 0
    pending_gfx_label = None
    while i < len(lines):
        if pending_gfx_label and re.match(r"\s*(?:db|\.byte)\s+", lines[i], flags=re.I):
            out.append(f"{pending_gfx_label}: {lines[i].lstrip()}")
            pending_gfx_label = None
            i += 1
            continue
        m0 = re.match(r"([A-Za-z_.$][A-Za-z0-9_.$]*):\s+db\s+(.+)$", lines[i])
        if (
            m0
            and i + 3 < len(lines)
            and re.match(r"\s*dw\s+\$\+7\s*$", lines[i + 1])
        ):
            m2 = re.match(r"\s*dw\s+\$\+4\s*,\s*(.+)$", lines[i + 2])
            m3 = re.match(r"\s*db\s+(.+)$", lines[i + 3])
            if m2 and m3:
                label = m0.group(1)
                out.extend([
                    f"{label}: db {m0.group(2)}",
                    f"dw {label}_gfx",
                    f"dw {label}_mode,{m2.group(1)}",
                    f"{label}_mode: db {m3.group(1)}",
                ])
                pending_gfx_label = f"{label}_gfx"
                i += 4
                continue
        out.append(lines[i])
        i += 1
    return out


def canonicalize_data_directives(lines: list[str]) -> list[str]:
    out = []
    for line in lines:
        line = re.sub(
            r'^(statxtbtb_eng:\s*)(?:db|\.byte|\.ascii)\s+"Network settings"(.*)$',
            r'\1.ascii "UNAPI provider"\2',
            line,
            flags=re.I,
        )
        line = re.sub(r"^(\s*(?:[A-Za-z_.$][A-Za-z0-9_.$]*:\s*)?)db\b", r"\1.byte", line, flags=re.I)
        line = re.sub(r"^(\s*(?:[A-Za-z_.$][A-Za-z0-9_.$]*:\s*)?)dw\b", r"\1.word", line, flags=re.I)
        out.append(line)
    return out


def flatten_default_language_records(lines: list[str]) -> list[str]:
    if not FLATTEN_DEFAULT_LANGUAGE:
        return lines

    out = []
    aliases: dict[str, list[str]] = {}
    i = 0
    while i < len(lines):
        m = re.match(r"^([A-Za-z_.$][A-Za-z0-9_.$]*):\s*\.byte\s+1\s*$", lines[i])
        if m and i + 1 < len(lines):
            w = re.match(r"^\s*\.word\s+([A-Za-z_.$][A-Za-z0-9_.$]*)\s*$", lines[i + 1])
            if w:
                aliases.setdefault(w.group(1), []).append(m.group(1))
                i += 2
                continue

        label = re.match(r"^([A-Za-z_.$][A-Za-z0-9_.$]*):(.*)$", lines[i])
        if label and label.group(1) in aliases:
            for alias in aliases.pop(label.group(1)):
                out.append(f"{alias}:")
        out.append(lines[i])
        i += 1

    for remaining in aliases.values():
        out.extend(f"{alias}: .byte 0" for alias in remaining)
    return out


def main():
    constants = dict(EXTRA_CONSTANTS)
    raw = []
    raw.append("; generated by tools/generate_scc_daemon.py")
    raw.extend(f"{k} equ {v}" for k, v in EXTRA_CONSTANTS.items())
    for path in SOURCES:
        raw.append(f"; source: {path}")
        raw.extend(flatten(path))
    filtered = filter_conditionals(raw, constants)
    filtered = apply_startup_overrides(filtered)
    filtered = apply_unapi_probe_overrides(filtered)
    filtered = apply_diagnostic_startup(filtered)
    converted = []
    for line in filtered:
        converted.extend(convert_line(line))
    converted = rewrite_multiline_dollar_icons(converted)
    converted = canonicalize_data_directives(converted)
    converted = flatten_default_language_records(converted)
    OUT.write_text("\n".join(converted) + "\n", encoding="latin-1")
    print(f"generated {OUT}")


if __name__ == "__main__":
    main()
