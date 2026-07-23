nolist

DRIVER      equ 6    ;6=MSX TCP/IP UNAPI backend
M4BOARD     equ 0
low_buflen  equ 0
relocate_count equ 0

; Compatibility for the newer symdoc SystemManager LNGLOD helper when building
; against the currently checked-out SymbOS constants snapshot.
MSC_SYS_EXTFNC  equ 30
FNC_DXT_LNGLOD  equ 12

org #1000

; RASM output is selected by the Makefile with -ob.

; This wrapper mirrors the existing daemon wrappers in ../symsys-networkdaemon.
; tools/generate_integrated_daemon.py derives the shared daemon source and adds
; the small DRIVER=6 integration branches needed by the UNAPI backend.
include "../SymbOS-ASM-Developer-kit/LIB/SymbOS-Constants.asm"
include "build/Dmn-Network-Head-UNAPI.asm"
include "build/symbos_lib-SystemManager.asm"
include "build/symbos_lib-DesktopManager.asm"
include "build/symbos_lib-FileManager.asm"
include "Dmn-Network-UNAPI.asm"
include "build/Dmn-Network-UNAPI-integrated.asm"

App_EndTrns

relocate_table
relocate_end
