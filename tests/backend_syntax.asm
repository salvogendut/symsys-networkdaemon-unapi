; Syntax check harness for Dmn-Network-UNAPI.asm.
;
; The backend is normally included before Dmn-Network.asm, which defines the
; daemon error codes and net_status variable. This harness provides just enough
; of that contract to let RASM parse the backend in isolation.

neterrnhw       equ 1
neterrfnc       equ 3
neterrcon       equ 5
neterrsex       equ 9
neterrdto       equ 17

net_status      db 0
App_BnkNum      db 0
jmp_bnkcop      equ #8130
pck_buffer      ds 577

include "../Dmn-Network-UNAPI.asm"
