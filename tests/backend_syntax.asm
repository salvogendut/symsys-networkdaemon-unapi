; Syntax check harness for Dmn-Network-UNAPI.asm.
;
; The backend is normally included before Dmn-Network.asm, which defines the
; daemon error codes and net_status variable. This harness provides just enough
; of that contract to let RASM parse the backend in isolation.

neterrnhw       equ 1
neterrfnc       equ 3
neterruhw       equ 4
neterrcon       equ 5
neterrsfr       equ 8
neterrsex       equ 9
neterrdto       equ 17

net_status      db 0
net_ipaadr      ds 20
App_BnkNum      db 0
jmp_memget      equ #8118
jmp_memfre      equ #811b
jmp_bnkcop      equ #8130
jmp_bnkcll      equ #ff03
jmp_bnkret      equ #ff00
SyFile_FILOPN   equ 0
SyFile_FILINP   equ 0
SyFile_FILCLO   equ 0
prgpstmem       equ 48
sckdatrpo       equ 0
sckdatrip       equ 2
App_BegCode     ds 256
pck_buffer      ds 577
una_tramp_fn    db 0
una_tramp_a     db 0
una_tramp_bc    dw 0
una_tramp_de    dw 0
una_tramp_hl    dw 0
una_tramp_entry dw 0
una_trn_iobuf   ds 1024
una_trn_openbuf ds 13
una_trn_dnsbuf  ds 256

include "../Dmn-Network-UNAPI.asm"
