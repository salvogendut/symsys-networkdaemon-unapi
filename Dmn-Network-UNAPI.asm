;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
;@                                                                            @
;@               S y m b O S   -   N e t w o r k - D a e m o n                @
;@                    MSX TCP/IP UNAPI LOWLEVEL ROUTINES                       @
;@                                                                            @
;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

; This backend implements the low* contract consumed by Dmn-Network.asm.
; Under SymbOS we do not call MSX EXTBIO directly. SYMUNAPI.COM must run under
; MSX-DOS before SYM.COM; it discovers TCP/IP UNAPI and writes metadata plus a
; complete image of the mapped provider. The daemon imports that image into a
; dedicated SymbOS bank and invokes it with the kernel interbank-call API.

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
SYMUNA_ENTRY_O  equ 13

UNAPI_MAPPED    equ 2

UNA_IO_MAX      equ 1024
UNA_PROVIDER_SIZE equ #4000
UNA_BANK_BASE   equ #0400
UNA_BANK_SIZE   equ #fb00
UNA_BANK_PROVIDER equ #4000
UNA_BANK_IOBUF  equ #c000
UNA_BANK_OPENBUF equ #c400
UNA_BANK_DNSBUF equ #c500
UNA_BANK_WRAPPER equ #f800
UNA_BANK_PARAM  equ #f880
UNA_BANK_STACK  equ #fef0
UNA_PARAM_SIZE  equ 10

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
UNA_ERR_NOT_IMP equ 1
UNA_ERR_NO_NET  equ 2
UNA_ERR_NO_DATA equ 3
UNA_ERR_NO_FREE equ 9
UNA_ERR_NO_CONN equ 11
UNA_ERR_BUFFER  equ 13

UNA_TCP_SYN_SENT     equ 2
UNA_TCP_SYN_RECEIVED equ 3
UNA_TCP_ESTABLISHED  equ 4
UNA_TCP_CLOSE_WAIT   equ 7

;--- BACKEND STATE ------------------------------------------------------------

una_ready       db 0
una_kind        db 0
una_entry       dw 0
una_provider_bank db 0
una_provider_addr dw 0
una_provider_memrec dw 0

una_fn          db 0
una_a           db 0
una_bc          dw 0
una_de          dw 0
una_hl          dw 0
una_info_handle db 0
una_provider_handle db 0
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
        call una_shutdown
        call una_load_info_file
        jr c,unaini_fail
        ld ix,una_info_buf
        ld a,(ix+SYMUNA_STATUS_O)
        cp 1
        jr nz,unaini_fail

        ld a,(ix+SYMUNA_KIND_O)
        ld (una_kind),a
        ld l,(ix+SYMUNA_ENTRY_O)
        ld h,(ix+SYMUNA_ENTRY_O+1)
        ld (una_entry),hl
        ld a,(una_kind)
        cp UNAPI_MAPPED
        jr nz,unaini_fail
        ld hl,(una_entry)
        ld a,h
        cp #40
        jr c,unaini_fail
        cp #80
        jr nc,unaini_fail
        call una_loadp
        jr c,unaini_fail
        call una_probe_caps
        jr c,unaini_fail
        ld a,1
        ld (una_ready),a
        ld a,#ff
        ld (net_status),a
        xor a
        ret

unaini_fail
        call una_shutdown
        scf
        ld a,neterrnhw
        ret

;### UNA_SHUTDOWN -> release the imported provider and clear runtime state
una_shutdown
        xor a
        ld (una_ready),a
        ld (una_kind),a
        ld (net_status),a
        ld hl,(una_provider_memrec)
        ld a,h
        or l
        jr z,una_shutdown_free
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ld hl,0
        ld (una_provider_memrec),hl
una_shutdown_free
        ld a,(una_provider_bank)
        or a
        jr z,una_shutdown_done
        ld hl,(una_provider_addr)
        ld bc,UNA_BANK_SIZE
        rst #20:dw jmp_memfre
una_shutdown_done
        xor a
        ld (una_provider_bank),a
        ld hl,0
        ld (una_provider_addr),hl
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
        ld a,(una_info_buf+SYMUNA_VERSION_O)
        cp 2
        jr nz,una_load_fail
        xor a
        ret
una_load_fail
        scf
        ret

una_bridge_magic db "SYMUNA2",0
una_info_path db "A:/SYMUNAPI.DAT",0
una_provider_path db "A:/SYMUNAPI.SEG",0

;### UNA_LOAD_PROVIDER -> reserve a whole bank and import the provider image
;### Output CF=0 ok, CF=1 allocation/file/image error
una_loadp
        xor a
        ld e,0
        ld bc,UNA_BANK_SIZE
        rst #20:dw jmp_memget
        ret c
        ld (una_provider_bank),a
        ld (una_provider_addr),hl

        ld a,h
        cp UNA_BANK_BASE/256
        jr nz,una_loadp_fail
        ld a,l
        or a
        jr nz,una_loadp_fail
        call una_register_provider
        jr c,una_loadp_fail

        ld hl,una_provider_path
        ld a,(App_BnkNum)
        db #dd:ld h,a
        call SyFile_FILOPN
        jr c,una_loadp_fail
        ld (una_provider_handle),a
        ld hl,UNA_BANK_PROVIDER
        ld a,(una_provider_bank)
        ld e,a
        ld bc,UNA_PROVIDER_SIZE
        ld a,(una_provider_handle)
        call SyFile_FILINP
        push af
        push bc
        ld a,(una_provider_handle)
        call SyFile_FILCLO
        pop bc
        pop af
        jr c,una_loadp_fail
        ld a,b
        cp UNA_PROVIDER_SIZE/256
        jr nz,una_loadp_fail
        ld a,c
        or a
        jr nz,una_loadp_fail

        call una_prepare_provider
        ret nc
una_loadp_fail
        call una_shutdown
        scf
        ret

; Register the allocation so Program Manager can reclaim it after an external
; process termination as well as through our normal shutdown path.
una_register_provider
        ld hl,App_BegCode+prgpstmem
        ld b,8
una_register_find
        ld a,(hl)
        or a
        jr z,una_register_found
        ld de,5
        add hl,de
        djnz una_register_find
        scf
        ret
una_register_found
        ld (una_provider_memrec),hl
        ld a,(una_provider_bank)
        ld (hl),a
        inc hl
        ld de,(una_provider_addr)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld de,UNA_BANK_SIZE
        ld (hl),e
        inc hl
        ld (hl),d
        or a
        ret

; Install the wrapper in the dedicated bank. The wrapper and all buffers live
; in page 3, which remains available to code entered through BNKCLL.
una_prepare_provider
        ld hl,una_exec_wrap
        ld de,UNA_BANK_WRAPPER
        ld bc,una_exec_end-una_exec_wrap
        ld a,(una_provider_bank)
        add a:add a:add a:add a
        ld d,a
        ld a,(App_BnkNum)
        or d
        ld de,UNA_BANK_WRAPPER
        rst #20:dw jmp_bnkcop

        or a
        ret

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
        ld a,(ix+0):ld (hl),a:inc hl
        ld a,(ix+1):ld (hl),a
        pop bc

        ld a,TCPIP_TCP_OPEN
        ld bc,0
        ld de,0
        ld hl,una_trn_openbuf
        call una_call
        or a
        jp nz,una_map_call_error
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
        ld hl,pck_buffer+3
        ld de,una_trn_dnsbuf
        ld b,255
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
        jp una_map_dns_error

;### UNADNR -> DNS check for resolve
;### Input      UNADNS has been called before
;### Output     CF=0 -> IP received, IX,IY=IP
;###            CF=1 -> A=status (0=still in progress, >0=error)
;### Destroyed  AF,BC,DE,HL,IX,IY
unadnr  call una_wait
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
        call una_stage_call

        ld a,(una_fn)
        ld (una_tramp_fn),a
        xor a
        ld (una_tramp_a),a
        ld bc,(una_bc)
        ld (una_tramp_bc),bc
        ld de,(una_de)
        ld (una_tramp_de),de
        ld hl,(una_hl)
        ld (una_tramp_hl),hl
        ld hl,(una_entry)
        ld (una_tramp_entry),hl

        ld hl,una_tramp_fn
        ld de,UNA_BANK_PARAM
        ld bc,UNA_PARAM_SIZE
        call una_copy_app_provider

        push ix
        push iy
        ld ix,UNA_BANK_WRAPPER
        ld a,(una_provider_bank)
        ld b,a
        ld iy,UNA_BANK_STACK
        call jmp_bnkcll
        pop iy
        pop ix

        ld hl,UNA_BANK_PARAM
        ld de,una_tramp_fn
        ld bc,UNA_PARAM_SIZE
        call una_copy_provider_app

        ld a,(una_tramp_a)
        ld (una_a),a
        ld bc,(una_tramp_bc)
        ld (una_bc),bc
        ld de,(una_tramp_de)
        ld (una_de),de
        ld hl,(una_tramp_hl)
        ld (una_hl),hl
        call una_unstage_call
        ld a,(una_a)
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

; Copied into page 3 of the dedicated provider bank. BNKCLL maps the complete
; bank and gives this routine its private stack. It must return via BNKRET.
UNA_EXEC_RETURN equ UNA_BANK_WRAPPER+una_exec_ret-una_exec_wrap
una_exec_wrap
        ld hl,UNA_EXEC_RETURN
        push hl
        ld hl,(UNA_BANK_PARAM+8)
        push hl
        ld a,(UNA_BANK_PARAM+0)
        ld bc,(UNA_BANK_PARAM+2)
        ld de,(UNA_BANK_PARAM+4)
        ld hl,(UNA_BANK_PARAM+6)
        ret
una_exec_ret
        ld (UNA_BANK_PARAM+1),a
        ld (UNA_BANK_PARAM+2),bc
        ld (UNA_BANK_PARAM+4),de
        ld (UNA_BANK_PARAM+6),hl
        jp jmp_bnkret
una_exec_end

; Marshal pointers and data into addresses that remain visible while the
; complete provider bank is mapped.
una_stage_call
        ld a,(una_fn)
        cp TCPIP_TCP_OPEN
        jr z,una_stage_open
        cp TCPIP_DNS_Q
        jr z,una_stage_dns
        cp TCPIP_TCP_SEND
        jr z,una_stage_send
        cp TCPIP_TCP_RCV
        jr z,una_stage_receive
        ret
una_stage_open
        ld hl,una_trn_openbuf
        ld de,UNA_BANK_OPENBUF
        ld bc,13
        call una_copy_app_provider
        ld hl,UNA_BANK_OPENBUF
        ld (una_hl),hl
        ret
una_stage_dns
        ld hl,una_trn_dnsbuf
        ld de,UNA_BANK_DNSBUF
        ld bc,256
        call una_copy_app_provider
        ld hl,UNA_BANK_DNSBUF
        ld (una_hl),hl
        ret
una_stage_send
        ld hl,una_trn_iobuf
        ld de,UNA_BANK_IOBUF
        ld bc,(una_hl)
        call una_copy_app_provider
        ld hl,UNA_BANK_IOBUF
        ld (una_de),hl
        ret
una_stage_receive
        ld hl,UNA_BANK_IOBUF
        ld (una_de),hl
        ret

; Copy received bytes back to the application's transfer staging buffer.
una_unstage_call
        ld a,(una_fn)
        cp TCPIP_TCP_RCV
        ret nz
        ld a,(una_a)
        or a
        ret nz
        ld bc,(una_bc)
        call una_clamp_io
        ld a,b
        or c
        ret z
        ld hl,UNA_BANK_IOBUF
        ld de,una_trn_iobuf
        jp una_copy_provider_app

; Input HL=source, DE=destination, BC=length.
una_copy_app_provider
        push de
        ld a,(una_provider_bank)
        add a:add a:add a:add a
        ld d,a
        ld a,(App_BnkNum)
        or d
        pop de
        rst #20:dw jmp_bnkcop
        ret

; Input HL=source, DE=destination, BC=length.
una_copy_provider_app
        push de
        ld a,(App_BnkNum)
        add a:add a:add a:add a
        ld d,a
        ld a,(una_provider_bank)
        or d
        pop de
        rst #20:dw jmp_bnkcop
        ret

;==============================================================================
;### HELPERS ##################################################################
;==============================================================================

; Translate the small set of provider errors with direct SymbOS equivalents.
una_map_call_error
        cp UNA_ERR_NOT_IMP
        jr z,una_map_not_imp
        cp UNA_ERR_NO_NET
        jr z,una_map_no_net
        cp UNA_ERR_NO_FREE
        jr z,una_map_no_free
        scf
        ld a,neterruhw
        ret
una_map_not_imp
        scf
        ld a,neterrfnc
        ret
una_map_no_net
        scf
        ld a,neterrcon
        ret
una_map_no_free
        scf
        ld a,neterrsfr
        ret

una_map_dns_error
        cp UNA_ERR_NOT_IMP
        jr z,una_map_not_imp
        cp UNA_ERR_NO_NET
        jr z,una_map_no_net
        scf
        ld a,neterrdto
        ret

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
