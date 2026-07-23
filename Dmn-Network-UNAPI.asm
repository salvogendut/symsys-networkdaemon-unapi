;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
;@                                                                            @
;@               S y m b O S   -   N e t w o r k - D a e m o n                @
;@                    MSX TCP/IP UNAPI LOWLEVEL ROUTINES                       @
;@                                                                            @
;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

; This backend implements the low* contract consumed by Dmn-Network.asm.
; Under SymbOS we do not call MSX EXTBIO directly. SYMUNAPI.COM must run under
; MSX-DOS before SYM.COM; it discovers TCP/IP UNAPI and writes SYMUNAPI.DAT.
; This daemon reads that file through the SymbOS FileManager.

;--- UNAPI CONTROL ROUTINES ---------------------------------------------------
;### UNAINI -> init TCP/IP UNAPI and setup daemon-visible network state

;--- UNAPI TCP ROUTINES -------------------------------------------------------
;### UNATOP -> TCP open connection
;### UNATCL -> TCP close connection
;### UNATST -> TCP test connection status
;### UNATRX -> TCP receive data from connection
;### UNATTX -> TCP send data to connection
;### UNATDC -> TCP disconnect connection
;### UNATSK -> TCP skip received data from connection
;### UNATFL -> TCP flush outgoing data

;--- UNAPI DNS ROUTINES -------------------------------------------------------
;### UNADNS -> DNS start request
;### UNADNR -> DNS check for resolve

;--- HIGHLEVEL INTERFACE EQUATES ---------------------------------------------

low_vermaj      equ 0
low_vermin      equ 1
low_sockmax     equ 4

lowini          equ unaini

lowtop          equ unatop
lowtcl          equ unatcl
lowtst          equ unatst
lowtrx          equ unatrx
lowttx          equ unattx
lowtdc          equ unatdc
lowtsk          equ unatsk
lowtfl          equ unatfl

lowuop          equ unauop
lowucl          equ unaucl
lowust          equ unaust
lowurx          equ unaurx
lowutx          equ unautx
lowusk          equ unausk

;--- MSX / UNAPI CONSTANTS ----------------------------------------------------

SYMUNA_MAGIC_O  equ 0
SYMUNA_VERSION_O equ 8
SYMUNA_STATUS_O equ 9
SYMUNA_KIND_O   equ 10
SYMUNA_SLOT_O   equ 11
SYMUNA_SEGMENT_O equ 12
SYMUNA_ENTRY_O  equ 13
SYMUNA_HELPER_O equ 15
SYMUNA_IY_O     equ 17
SYMUNA_FN_O     equ 19
SYMUNA_A_O      equ 20
SYMUNA_BC_O     equ 21
SYMUNA_DE_O     equ 23
SYMUNA_HL_O     equ 25
SYMUNA_PUTP1_O  equ 27
SYMUNA_GETP1_O  equ 29
SYMUNA_CALL_O   equ 32
SYMUNA_IOBUF_O  equ #100

UNAPI_DIRECT    equ 1
UNAPI_MAPPED    equ 2

UNA_IO_MAX      equ 1024
UNA_SEND_CHUNK  equ 512

TCPIP_GET_INFO  equ 0
TCPIP_GET_CAPAB equ 1
TCPIP_DNS_Q     equ 6
TCPIP_DNS_S     equ 7
TCPIP_TCP_OPEN  equ 13
TCPIP_TCP_CLOSE equ 14
TCPIP_TCP_ABORT equ 15
TCPIP_TCP_STATE equ 16
TCPIP_TCP_SEND  equ 17
TCPIP_TCP_RCV   equ 18
TCPIP_WAIT      equ 29

UNA_ERR_OK      equ 0
UNA_ERR_NO_DATA equ 3
UNA_ERR_NO_CONN equ 11
UNA_ERR_BUFFER  equ 13

UNA_TCP_SYN_SENT     equ 2
UNA_TCP_SYN_RECEIVED equ 3
UNA_TCP_ESTABLISHED  equ 4
UNA_TCP_CLOSE_WAIT   equ 7

;--- BACKEND STATE ------------------------------------------------------------

una_ready       db 0
una_bridge_base dw 0
una_kind        db 0
una_slot        db 0
una_segment     db 0
una_entry       dw 0
una_helper      dw 0
una_iy          dw 0            ;IY = slot:segment for CALL_MAP helper
una_putp1       dw 0
una_getp1       dw 0

una_fn          db 0
una_a           db 0
una_bc          dw 0
una_de          dw 0
una_hl          dw 0
una_info_handle db 0
una_info_buf    ds 32

una_handles     ds low_sockmax
una_rx_avail    ds low_sockmax*2
una_socket_tmp  db 0
una_handle_tmp  db 0
una_xfer_addr   dw 0
una_xfer_bank   db 0
una_req_len     dw 0
una_xfer_len    dw 0
una_dns_ip      ds 4
una_status_rec  dw 0

;==============================================================================
;### UNAPI CONTROL #############################################################
;==============================================================================

;### UNAINI -> init TCP/IP UNAPI
;### Input      A=type. 0/5=detect, other config operations are accepted as no-op
;### Output     CF=0 ok, CF=1 no hardware/unsupported implementation
;### Destroyed  AF,BC,DE,HL,IX,IY
unaini  or a
        jr z,unaini_detect
        cp 5
        jr z,unaini_detect
        xor a
        ret

unaini_detect
        call una_load_info_file
        jr c,unaini_fail
        ld ix,una_info_buf
        ld a,(ix+SYMUNA_STATUS_O)
        cp 1
        jr nz,unaini_fail

        ld a,(ix+SYMUNA_KIND_O)
        ld (una_kind),a
        ld a,(ix+SYMUNA_SLOT_O)
        ld (una_slot),a
        ld a,(ix+SYMUNA_SEGMENT_O)
        ld (una_segment),a
        ld l,(ix+SYMUNA_ENTRY_O)
        ld h,(ix+SYMUNA_ENTRY_O+1)
        ld (una_entry),hl
        ld l,(ix+SYMUNA_HELPER_O)
        ld h,(ix+SYMUNA_HELPER_O+1)
        ld (una_helper),hl
        ld l,(ix+SYMUNA_IY_O)
        ld h,(ix+SYMUNA_IY_O+1)
        ld (una_iy),hl
        ld l,(ix+SYMUNA_PUTP1_O)
        ld h,(ix+SYMUNA_PUTP1_O+1)
        ld (una_putp1),hl
        ld l,(ix+SYMUNA_GETP1_O)
        ld h,(ix+SYMUNA_GETP1_O+1)
        ld (una_getp1),hl
        call una_normalize_mapper_calls
        call una_install_trampoline
        ld a,1
        ld (una_ready),a
        ld a,#ff
        ld (net_status),a
        xor a
        ret

unaini_fail
        xor a
        ld (una_ready),a
        ld (una_kind),a
        ld (net_status),a
        scf
        ld a,neterrnhw
        ret

una_normalize_mapper_calls
        ld hl,(una_putp1)
        ld de,(una_getp1)
        or a
        sbc hl,de
        ret c                       ;PUT_P1 < GET_P1, expected order
        ret z
        ld hl,(una_putp1)
        push hl
        ld hl,(una_getp1)
        ld (una_putp1),hl
        pop hl
        ld (una_getp1),hl
        ret

una_load_info_file
        ld hl,una_info_path
        ld a,(App_BnkNum)
        db #dd:ld h,a
        call SyFile_FILOPN
        ret c
        ld (una_info_handle),a
        ld hl,una_info_buf
        ld bc,32
        ld de,(App_BnkNum)
        call SyFile_FILINP
        push af
        ld a,(una_info_handle)
        call SyFile_FILCLO
        pop af
        jr c,una_load_fail
        ld hl,una_info_buf
        ld de,una_bridge_magic
        ld b,8
una_load_sig
        ld a,(de)
        cp (hl)
        jr nz,una_load_fail
        inc hl
        inc de
        djnz una_load_sig
        xor a
        ret
una_load_fail
        scf
        ret

una_bridge_magic db "SYMUNA1",0
una_info_path db "A:/SYMUNAPI.DAT",0

;### UNA_PROBE_CAPS -> verify TCP/IP UNAPI info and active TCP capability
;### Output CF=0 ok, CF=1 unsupported
una_probe_caps
        ld a,TCPIP_GET_INFO
        ld bc,0
        ld de,0
        ld hl,0
        call una_call
        or a
        scf
        ret nz
        ld hl,(una_de)
        ld de,#0100
        or a
        sbc hl,de
        ccf
        ret c
        ld a,TCPIP_GET_CAPAB
        ld bc,#0100
        ld de,0
        ld hl,0
        call una_call
        or a
        scf
        ret nz
        ld hl,(una_hl)
        bit 3,l                    ;active TCP capability
        scf
        ret z
        or a
        ret

;==============================================================================
;### UNAPI TCP #################################################################
;==============================================================================

;### UNATOP -> open active TCP connection
;### Input      A=socket number, E=mode, IX=open structure
;### Output     CF=0 ok, CF=1 error (A=error code)
unatop  ld b,a
        ld (una_socket_tmp),a
        ld a,(una_ready)
        or a
        scf
        ld a,neterrnhw
        ret z
        ld a,e
        or a
        scf
        ld a,neterrfnc
        ret nz                    ;passive/server TCP is not implemented yet

        push bc
        call una_clear_openbuf
        ld hl,una_trn_openbuf
        ld a,(ix+2):ld (hl),a:inc hl
        ld a,(ix+3):ld (hl),a:inc hl
        ld a,(ix+4):ld (hl),a:inc hl
        ld a,(ix+5):ld (hl),a:inc hl
        ld a,(ix+6):ld (hl),a:inc hl
        ld a,(ix+7):ld (hl),a:inc hl
        ld (hl),#ff:inc hl        ;random local port
        ld (hl),#ff
        pop bc

        ld a,TCPIP_TCP_OPEN
        ld bc,0
        ld de,0
        ld hl,una_trn_openbuf
        scf
        ld a,neterrfnc            ;runtime UNAPI calls disabled in safe build
        ret
        ld a,(una_bc+1)           ;B=UNAPI connection handle
        or a
        scf
        ld a,65                   ;diagnostic: TCP_OPEN returned no handle
        ret z
        ld c,a
        ld a,(una_socket_tmp)
        ld e,a
        ld d,0
        ld hl,una_handles
        add hl,de
        ld (hl),c
        xor a
        ret
;### UNATCL -> close TCP connection
;### Input A=socket number
unatcl  call una_get_handle
        ret c
        ld b,a
        ld a,TCPIP_TCP_CLOSE
        ld c,0
        ld de,0
        ld hl,0
        call una_call
        call una_forget_handle
        xor a
        ret

;### UNATDC -> abort/disconnect TCP connection
unatdc  call una_get_handle
        ret c
        ld b,a
        ld a,TCPIP_TCP_ABORT
        ld c,0
        ld de,0
        ld hl,0
        call una_call
        call una_forget_handle
        xor a
        ret

;### UNATST -> test TCP status
;### Output A=status, BC=rx bytes, IX/IY=remote IP, DE=remote port
unatst  push ix
        pop hl
        ld (una_status_rec),hl
        call una_get_handle
        ret c
        push af
        call una_wait
        pop af
        ld b,a
        ld a,TCPIP_TCP_STATE
        ld c,0
        ld de,0
        ld hl,0
        call una_call
        or a
        jr nz,unatst_closed
        ld bc,(una_hl)            ;available RX bytes
        call una_store_rx_avail
        ld a,(una_bc+1)           ;UNAPI state in B
        cp UNA_TCP_ESTABLISHED
        ld l,2
        jr z,unatst_done
        cp UNA_TCP_CLOSE_WAIT
        ld l,3
        jr z,unatst_done
        cp UNA_TCP_SYN_SENT
        jr z,unatst_opening
        cp UNA_TCP_SYN_RECEIVED
        jr z,unatst_opening
unatst_closed
        ld bc,0
        call una_store_rx_avail
        ld l,4
        jr unatst_done
unatst_opening
        push bc
        ld a,TCPIP_WAIT
        ld bc,0
        ld de,0
        ld hl,0
        call una_call
        pop bc
        ld l,1
unatst_done
        call una_status_endpoint
        ld a,b
        or c
        ld a,l
        ret z
        add 128
        ret

;### UNA_STATUS_ENDPOINT -> return stored remote endpoint for TCP status events
;### Output IX/IY=remote IP, DE=remote port
una_status_endpoint
        push af
        push bc
        ld hl,(una_status_rec)
        ld de,sckdatrpo
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(una_status_rec)
        ld de,sckdatrip
        add hl,de
        ld c,(hl)
        inc hl
        ld b,(hl)
        push bc
        pop ix
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        push bc
        pop iy
        pop bc
        pop af
        ret

;### UNATRX -> receive bytes
;### Input A=socket number, HL=dest address, E=dest bank, BC=length
;### Output BC=remaining bytes
unatrx  ld (una_xfer_addr),hl
        ld a,e
        ld (una_xfer_bank),a
        ld (una_req_len),bc
        call una_get_handle
        jr c,unatrx_err
        ld (una_handle_tmp),a
        ld bc,(una_req_len)
        call una_clamp_io
        ld (una_req_len),bc
        ld a,(una_handle_tmp)
        ld b,a
        ld c,0
        ld de,una_trn_iobuf
        ld hl,(una_req_len)
        ld a,TCPIP_TCP_RCV
        call una_call
        or a
        jr z,unatrx_copy
        cp UNA_ERR_NO_DATA
        jr z,unatrx_none
        ld bc,0
        ret
unatrx_copy
        ld bc,(una_bc)            ;bytes read
        ld (una_xfer_len),bc
        ld a,b
        or c
        jr z,unatrx_none
        call una_copy_from_iobuf
        ld bc,(una_xfer_len)
        call una_consume_rx_avail
        ret
unatrx_none
        ld bc,0
        ret
unatrx_err
        ld bc,0
        ret

;### UNATTX -> send bytes
;### Input A=socket number, HL=source address, E=source bank, BC=length
;### Output BC=sent bytes, HL=remaining bytes, ZF=1 if all sent
unattx  ld (una_xfer_addr),hl
        ld a,e
        ld (una_xfer_bank),a
        ld (una_tx_len),bc
        call una_get_handle
        jr c,unattx_fail
        ld (una_handle_tmp),a
        ld bc,(una_tx_len)
        call una_clamp_io
        ld (una_xfer_len),bc
        call una_copy_to_iobuf
        ld a,(una_handle_tmp)
        ld b,a
        ld c,1                    ;push data
        ld de,una_trn_iobuf
        ld hl,(una_xfer_len)
        ld a,TCPIP_TCP_SEND
        call una_call
        or a
        jr nz,unattx_fail2
        ld bc,(una_xfer_len)
        ld hl,(una_tx_len)
        or a
        sbc hl,bc
        ld a,h
        or l
        ret
unattx_fail
unattx_fail2
        ld bc,0
        ld hl,(una_tx_len)
        or 1
        ret

una_tx_len dw 0

;### UNATSK -> skip received bytes
unatsk  ld (una_req_len),bc
        call una_get_handle
        jr c,unatsk_err
        ld (una_handle_tmp),a
unatsk_loop
        ld bc,(una_req_len)
        ld a,b
        or c
        jr z,unatsk_done
        call una_clamp_io
        ld (una_xfer_len),bc
        ld a,(una_handle_tmp)
        ld b,a
        ld c,0
        ld de,una_trn_iobuf
        ld hl,(una_xfer_len)
        ld a,TCPIP_TCP_RCV
        call una_call
        or a
        jr z,unatsk_got
        cp UNA_ERR_NO_DATA
        jr z,unatsk_done
unatsk_err
        ld bc,0
        ret
unatsk_got
        ld bc,(una_bc)
        ld (una_xfer_len),bc
        ld a,b
        or c
        jr z,unatsk_done
        call una_consume_rx_avail
        ld hl,(una_req_len)
        ld de,(una_xfer_len)
        or a
        sbc hl,de
        jr nc,unatsk_store
        ld hl,0
unatsk_store
        ld (una_req_len),hl
        jr unatsk_loop
unatsk_done
        call una_get_rx_avail
        ret

;### UNATFL -> flush outgoing data
unatfl  ret

;==============================================================================
;### UNAPI DNS #################################################################
;==============================================================================

;### UNADNS -> DNS start request
;### Input      (pck_buffer+3)=domain name string (0-terminated)
;### Output     CF=0 -> ok, DNS lookup in progress
;###            CF=1 -> error (A=error code)
;### Destroyed  AF,BC,DE,HL,IX,IY
unadns  ld a,(una_ready)
        or a
        scf
        ld a,neterrnhw
        ret z
        scf
        ld a,neterrfnc            ;runtime UNAPI calls disabled in safe build
        ret
        ld hl,pck_buffer+3
        ld de,una_trn_dnsbuf
        ld b,0
unadns_copy
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr z,unadns_call
        djnz unadns_copy
        xor a
        ld (de),a
unadns_call
        ld a,TCPIP_DNS_Q
        ld bc,0
        ld de,0
        ld hl,una_trn_dnsbuf
        call una_call
        or a
        ret z
        scf
        ld a,neterrdto
        ret

;### UNADNR -> DNS check for resolve
;### Input      UNADNS has been called before
;### Output     CF=0 -> IP received, IX,IY=IP
;###            CF=1 -> A=status (0=still in progress, >0=error)
;### Destroyed  AF,BC,DE,HL,IX,IY
unadnr  scf
        ld a,neterrfnc            ;runtime UNAPI calls disabled in safe build
        ret
        call una_wait
        ld a,TCPIP_DNS_S
        ld bc,0
        ld de,0
        ld hl,0
        call una_call
        or a
        jr nz,unadnr_err
        ld a,(una_bc+1)          ;B=status: 1=in progress, 2=done
        cp 2
        jr z,unadnr_done
        cp 1
        scf
        ld a,0
        ret z
unadnr_err
        scf
        ld a,neterrdto
        ret
unadnr_done
        ld hl,(una_hl)           ;L,H,E,D = IPv4 bytes
        ld (una_dns_ip+0),hl
        push hl
        pop ix
        ld hl,(una_de)
        ld (una_dns_ip+2),hl
        push hl
        pop iy
        xor a
        ret

;==============================================================================
;### UDP STUBS ################################################################
;==============================================================================

unauop
unaucl
unaust
unaurx
unautx
unausk  scf
        ld a,neterrfnc
        ret

;==============================================================================
;### UNAPI CALL BRIDGE #########################################################
;==============================================================================

;### UNA_CALL -> call selected UNAPI implementation
;### Input A=function, BC/DE/HL=UNAPI registers
;### Output A=UNAPI error/status, returned regs in una_* variables
una_call
        ld (una_fn),a
        ld (una_bc),bc
        ld (una_de),de
        ld (una_hl),hl
        call una_trampoline_area
        ret

una_wait
        push bc
        push de
        push hl
        ld a,TCPIP_WAIT
        ld bc,0
        ld de,0
        ld hl,0
        call una_call
        pop hl
        pop de
        pop bc
        ret

unatramp_src_beg
        push ix
        push iy
        ld a,(una_kind)
        cp UNAPI_DIRECT
        jr z,unatramp_src_direct
        cp UNAPI_MAPPED
        jr z,unatramp_src_mapped
        ld a,15
        ld bc,0
        ld de,0
        ld hl,0
        jr unatramp_src_store

unatramp_src_direct
unatramp_direct_ret
        ld hl,0
        push hl
        ld hl,(una_entry)
        push hl
        jr unatramp_src_regs

unatramp_src_mapped
        ld a,(una_fn)
        ld (una_tramp_fn),a
        ld hl,(una_bc)
        ld (una_tramp_bc),hl
        ld hl,(una_de)
        ld (una_tramp_de),hl
        ld hl,(una_hl)
        ld (una_tramp_hl),hl
        in a,(#fd)
        ld (una_tramp_savep1),a
        ld a,(una_segment)
        out (#fd),a
utmra
        ld hl,0
        push hl
        ld hl,(una_entry)
        push hl
        ld a,(una_tramp_fn)
        ld bc,(una_tramp_bc)
        ld de,(una_tramp_de)
        ld hl,(una_tramp_hl)
        ret

utmr
        ld (una_tramp_a),a
        ld (una_tramp_bc),bc
        ld (una_tramp_de),de
        ld (una_tramp_hl),hl
        ld a,(una_tramp_savep1)
        out (#fd),a
        ld a,(una_tramp_a)
        ld bc,(una_tramp_bc)
        ld de,(una_tramp_de)
        ld hl,(una_tramp_hl)
        jr unatramp_src_store

unatramp_src_regs
        ld a,(una_fn)
        ld bc,(una_bc)
        ld de,(una_de)
        ld hl,(una_hl)
        ret

unatramp_src_store
        ld (una_a),a
        ld (una_bc),bc
        ld (una_de),de
        ld (una_hl),hl
        pop iy
        pop ix
        ret
unatramp_src_end

una_install_trampoline
        ld hl,unatramp_src_beg
        ld de,una_trampoline_area
        ld bc,unatramp_src_end-unatramp_src_beg
        ldir
        ld hl,una_trampoline_area
        ld de,unatramp_src_store-unatramp_src_beg
        add hl,de
        push hl
        ld hl,una_trampoline_area
        ld de,unatramp_direct_ret-unatramp_src_beg+1
        add hl,de
        pop de
        call una_patch_word
        ld hl,una_trampoline_area
        ld de,utmr-unatramp_src_beg
        add hl,de
        push hl
        ld hl,una_trampoline_area
        ld de,utmra-unatramp_src_beg+1
        add hl,de
        pop de
        call una_patch_word
        ret

una_patch_word
        ld (hl),e
        inc hl
        ld (hl),d
        ret

;==============================================================================
;### HELPERS ##################################################################
;==============================================================================

una_clear_openbuf
        ld hl,una_trn_openbuf
        ld de,una_trn_openbuf+1
        ld bc,12
        ld (hl),0
        ldir
        ret

una_get_handle
        ld (una_socket_tmp),a
        cp low_sockmax
        jr nc,una_get_handle_fail
        ld e,a
        ld d,0
        ld hl,una_handles
        add hl,de
        ld a,(hl)
        or a
        ret nz
una_get_handle_fail
        scf
        ld a,neterrsex
        ret

una_forget_handle
        ld a,(una_socket_tmp)
        cp low_sockmax
        ret nc
        ld e,a
        ld d,0
        ld hl,una_handles
        add hl,de
        xor a
        ld (hl),a
        call una_clear_rx_avail
        ret

una_clear_rx_avail
        push de
        push hl
        ld a,(una_socket_tmp)
        add a
        ld e,a
        ld d,0
        ld hl,una_rx_avail
        add hl,de
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        pop hl
        pop de
        ret

;### UNA_CLAMP_IO -> BC=min(BC, UNA_IO_MAX)
una_clamp_io
        ld hl,UNA_IO_MAX
        or a
        sbc hl,bc
        ret nc
        ld bc,UNA_IO_MAX
        ret

;### UNA_COPY_TO_IOBUF -> copy caller banked buffer to UNAPI staging buffer
;### Input (una_xfer_addr)=source, (una_xfer_bank)=source bank, BC=length
una_copy_to_iobuf
        ld hl,(una_xfer_addr)
        ld de,una_trn_iobuf
        ld a,(App_BnkNum)
        add a:add a:add a:add a
        ld (una_bank_dst+1),a
        ld a,(una_xfer_bank)
una_bank_dst
        add 0
        rst #20:dw jmp_bnkcop
        ret

;### UNA_COPY_FROM_IOBUF -> copy UNAPI staging buffer to caller banked buffer
;### Input (una_xfer_addr)=destination, (una_xfer_bank)=destination bank, BC=length
una_copy_from_iobuf
        ld hl,una_trn_iobuf
        ld de,(una_xfer_addr)
        ld a,(una_xfer_bank)
        add a:add a:add a:add a
        ld (una_bank_src+1),a
        ld a,(App_BnkNum)
una_bank_src
        add 0
        rst #20:dw jmp_bnkcop
        ret

;### UNA_STORE_RX_AVAIL -> remember last TCP_STATE available bytes for socket
;### Input BC=available bytes
una_store_rx_avail
        push af
        push de
        push hl
        ld a,(una_socket_tmp)
        add a
        ld e,a
        ld d,0
        ld hl,una_rx_avail
        add hl,de
        ld (hl),c
        inc hl
        ld (hl),b
        pop hl
        pop de
        pop af
        ret

;### UNA_GET_RX_AVAIL -> Output BC=remembered available bytes for socket
una_get_rx_avail
        push de
        push hl
        ld a,(una_socket_tmp)
        add a
        ld e,a
        ld d,0
        ld hl,una_rx_avail
        add hl,de
        ld c,(hl)
        inc hl
        ld b,(hl)
        pop hl
        pop de
        ret

;### UNA_CONSUME_RX_AVAIL -> subtract copied bytes from remembered available count
;### Input BC=copied bytes, Output BC=remaining bytes
una_consume_rx_avail
        push de
        push hl
        push bc
        ld a,(una_socket_tmp)
        add a
        ld e,a
        ld d,0
        ld hl,una_rx_avail
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        pop de
        or a
        sbc hl,de
        jr nc,una_consume_rx_store
        ld hl,0
una_consume_rx_store
        push hl
        ld a,(una_socket_tmp)
        add a
        ld e,a
        ld d,0
        ld hl,una_rx_avail
        add hl,de
        pop bc
        ld (hl),c
        inc hl
        ld (hl),b
        pop hl
        pop de
        ret
