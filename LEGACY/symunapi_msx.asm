; SYMUNAPI.COM - MSX-DOS to SymbOS TCP/IP UNAPI provider snapshotter.
;
; Run this after the TCP/IP UNAPI provider and RAMHELPR.COM, before SYM.COM.
; It discovers the provider while MSX-DOS/BIOS calls are safe and writes:
;   SYMUNAPI.DAT - provider metadata
;   SYMUNAPI.SEG - complete 16K mapped-RAM provider image
; SymbOS imports the image into memory it owns instead of retaining DOS mapper
; addresses, which cease to be valid after SYM.COM takes over the machine.

BDOS            equ #0005
_TERM0          equ #00
_STROUT         equ #09
_FCLOSE         equ #10
_FDELETE        equ #13
_FCREATE        equ #16
_FWRITE         equ #15
_SETDMA         equ #1a

EXTBIO          equ #ffca
UNAPI_ARG       equ #f847

SYMUNA_BASE     equ #c900
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
SYMUNA_SIZE     equ #600

UNAPI_DIRECT    equ 1
UNAPI_MAPPED    equ 2

                org #100

start:
                ld (old_sp),sp
                ld de,msg_banner
                call strout

                ld hl,SYMUNA_BASE
                ld (bridge_base),hl
                ld hl,(#0006)
                ld de,SYMUNA_BASE+SYMUNA_SIZE
                or a
                sbc hl,de
                jr nc,tpa_ok
                ld de,msg_tpa
                call strout
                jp quit

tpa_ok:
                ld sp,(bridge_base)
                call clear_bridge
                ld hl,magic
                ld de,(bridge_base)
                ld bc,8
                ldir
                ld a,2
                ld e,SYMUNA_VERSION_O
                call put_a

                ld hl,(bridge_base)
                ld de,SYMUNA_CALL_O
                add hl,de
                ex de,hl
                ld hl,bridge_call_code
                ld bc,bridge_call_code_end-bridge_call_code
                ldir
                call patch_bridge_code
                call delete_segment_file

                call discover_tcpip
                jr c,no_device
                ld e,SYMUNA_KIND_O
                call get_a
                cp UNAPI_MAPPED
                jr nz,unsupported
                call write_segment_file
                jr c,snapshot_failed
                ld a,1
                ld e,SYMUNA_STATUS_O
                call put_a
                ld de,msg_online
                call strout
                jr persist

no_device:
                xor a
                ld e,SYMUNA_STATUS_O
                call put_a
                ld de,msg_nodev
                call strout
                jr persist

unsupported:
                xor a
                ld e,SYMUNA_STATUS_O
                call put_a
                ld de,msg_unsupported
                call strout
                jr persist

snapshot_failed:
                xor a
                ld e,SYMUNA_STATUS_O
                call put_a
                ld de,msg_snapshot
                call strout

persist:
                call write_info_file
                ld de,msg_written
                call strout
                ld sp,(old_sp)
quit:
                ld c,_TERM0
                jp BDOS

clear_bridge:
                ld hl,(bridge_base)
                ld d,h
                ld e,l
                inc de
                ld bc,SYMUNA_SIZE-1
                xor a
                ld (hl),a
                ldir
                ret

put_a:
                ld hl,(bridge_base)
                ld d,0
                add hl,de
                ld (hl),a
                ret

put_bc:
                ld hl,(bridge_base)
                add hl,de
                ld (hl),c
                inc hl
                ld (hl),b
                ret

patch_bridge_code:
                ld bc,(bridge_base)
                ld de,SYMUNA_CALL_O+bridge_base_load1-bridge_call_code+2
                call put_bc
                ld bc,(bridge_base)
                ld de,SYMUNA_CALL_O+bridge_base_load2-bridge_call_code+2
                call put_bc
                ld hl,(bridge_base)
                ld de,SYMUNA_CALL_O+bridge_ret-bridge_call_code
                add hl,de
                ld b,h
                ld c,l
                ld de,SYMUNA_CALL_O+bridge_ret_load1-bridge_call_code+1
                call put_bc
                ld hl,(bridge_base)
                ld de,SYMUNA_CALL_O+bridge_ret-bridge_call_code
                add hl,de
                ld b,h
                ld c,l
                ld de,SYMUNA_CALL_O+bridge_ret_load2-bridge_call_code+1
                call put_bc
                ret

discover_tcpip:
                ld hl,tcpip_name
                ld de,UNAPI_ARG
                ld bc,7
                ldir

                xor a
                ld de,#2222
                ld bc,0
                ld hl,0
                call EXTBIO
                ld a,b
                or a
                scf
                ret z

                ld a,1
                ld de,#2222
                ld bc,0
                ld hl,0
                call EXTBIO
                ld (tmp_slot),a
                ld a,b
                ld (tmp_segment),a
                ld b,h
                ld c,l
                ld de,SYMUNA_ENTRY_O
                call put_bc
                ld a,(tmp_slot)
                ld e,SYMUNA_SLOT_O
                call put_a
                ld a,(tmp_segment)
                ld e,SYMUNA_SEGMENT_O
                call put_a

                ld de,SYMUNA_ENTRY_O
                call get_hl
                ld de,#c000
                or a
                sbc hl,de
                jr nc,select_direct

                ld e,SYMUNA_SEGMENT_O
                call get_a
                cp #ff
                scf
                ret z

                ld a,#ff
                ld de,#2222
                ld bc,0
                ld hl,0
                call EXTBIO
                ld a,h
                or l
                scf
                ret z
                ld (tmp_helper),hl
                ld b,h
                ld c,l
                ld de,SYMUNA_HELPER_O
                call put_bc
                ld e,SYMUNA_SLOT_O
                call get_a
                ld b,a
                ld e,SYMUNA_SEGMENT_O
                call get_a
                ld c,a
                ld de,SYMUNA_IY_O
                call put_bc
                call record_mapper_calls
                ld a,UNAPI_MAPPED
                ld e,SYMUNA_KIND_O
                call put_a
                or a
                ret

select_direct:
                ld a,UNAPI_DIRECT
                ld e,SYMUNA_KIND_O
                call put_a
                or a
                ret

record_mapper_calls:
                xor a
                ld de,#0402
                ld bc,0
                ld hl,0
                call EXTBIO
                ld a,h
                or l
                ret z
                push hl
                ld de,30
                add hl,de
                ld b,h
                ld c,l
                ld de,SYMUNA_PUTP1_O
                call put_bc
                pop hl
                ld de,33
                add hl,de
                ld b,h
                ld c,l
                ld de,SYMUNA_GETP1_O
                jp put_bc

get_a:
                ld hl,(bridge_base)
                ld d,0
                add hl,de
                ld a,(hl)
                ret

get_hl:
                ld hl,(bridge_base)
                ld d,0
                add hl,de
                ld a,(hl)
                inc hl
                ld h,(hl)
                ld l,a
                ret

write_info_file:
                ld hl,fcb_template
                ld de,info_fcb
                ld bc,36
                ldir
                ld de,info_fcb
                ld c,_FDELETE
                call BDOS
                ld hl,fcb_template
                ld de,info_fcb
                ld bc,36
                ldir
                ld de,info_fcb
                ld c,_FCREATE
                call BDOS
                inc a
                ret z
                ld de,(bridge_base)
                ld c,_SETDMA
                call BDOS
                ld de,info_fcb
                ld c,_FWRITE
                call BDOS
                ld de,info_fcb
                ld c,_FCLOSE
                jp BDOS

delete_segment_file:
                ld hl,segment_fcb_template
                ld de,info_fcb
                ld bc,36
                ldir
                ld de,info_fcb
                ld c,_FDELETE
                jp BDOS

; Save the complete mapped provider through RAMHELPR's READRAM entry. Reading
; through the helper keeps the DOS TPA mapped while BDOS writes each record.
write_segment_file:
                ld hl,segment_fcb_template
                ld de,info_fcb
                ld bc,36
                ldir
                ld de,info_fcb
                ld c,_FCREATE
                call BDOS
                inc a
                scf
                ret z

                ld hl,(tmp_helper)
                ld de,3
                add hl,de
                ld (tmp_reader),hl
                ld hl,#4000
                ld (snapshot_source),hl
                ld a,128
                ld (snapshot_records),a
                ld de,snapshot_dma
                ld c,_SETDMA
                call BDOS

snapshot_record:
                ld hl,(snapshot_source)
                ld de,snapshot_dma
                ld c,128
snapshot_byte:
                ld a,(tmp_segment)
                ld b,a
                ld a,(tmp_slot)
                ld ix,(tmp_reader)
                call call_ix
                ld (de),a
                inc de
                inc hl
                dec c
                jr nz,snapshot_byte
                ld (snapshot_source),hl

                ld de,info_fcb
                ld c,_FWRITE
                call BDOS
                or a
                jr nz,snapshot_write_failed
                ld hl,snapshot_records
                dec (hl)
                jr nz,snapshot_record

                ld de,info_fcb
                ld c,_FCLOSE
                call BDOS
                or a
                ret

snapshot_write_failed:
                ld de,info_fcb
                ld c,_FCLOSE
                call BDOS
                scf
                ret

; Runtime bridge entry. Copied to SYMUNA_CALL and called by the SymbOS daemon.
bridge_call_code:
                push ix
                push iy
bridge_base_load1:
                ld ix,0
                ld a,(ix+SYMUNA_KIND_O)
                cp UNAPI_DIRECT
                jr z,bridge_direct
                cp UNAPI_MAPPED
                jr z,bridge_mapped
                ld a,15
                ld bc,0
                ld de,0
                ld hl,0
                jr bridge_store

bridge_direct:
bridge_ret_load1:
                ld hl,0
                push hl
                ld l,(ix+SYMUNA_ENTRY_O)
                ld h,(ix+SYMUNA_ENTRY_O+1)
                push hl
                jr bridge_regs

bridge_mapped:
bridge_ret_load2:
                ld hl,0
                push hl
                ld l,(ix+SYMUNA_HELPER_O)
                ld h,(ix+SYMUNA_HELPER_O+1)
                push hl

bridge_regs:
                ld a,(ix+SYMUNA_FN_O)
                ld c,(ix+SYMUNA_BC_O)
                ld b,(ix+SYMUNA_BC_O+1)
                ld e,(ix+SYMUNA_DE_O)
                ld d,(ix+SYMUNA_DE_O+1)
                ld l,(ix+SYMUNA_HL_O)
                ld h,(ix+SYMUNA_HL_O+1)
                push hl
                ld l,(ix+SYMUNA_IY_O)
                ld h,(ix+SYMUNA_IY_O+1)
                push hl
                pop iy
                ld l,(ix+SYMUNA_ENTRY_O)
                ld h,(ix+SYMUNA_ENTRY_O+1)
                push hl
                pop ix
                pop hl
                ret

bridge_ret:
bridge_store:
bridge_base_load2:
                ld ix,0
                ld (ix+SYMUNA_A_O),a
                ld (ix+SYMUNA_BC_O),c
                ld (ix+SYMUNA_BC_O+1),b
                ld (ix+SYMUNA_DE_O),e
                ld (ix+SYMUNA_DE_O+1),d
                ld (ix+SYMUNA_HL_O),l
                ld (ix+SYMUNA_HL_O+1),h
                pop iy
                pop ix
                ret
bridge_call_code_end:

strout:
                ld c,_STROUT
                jp BDOS

call_ix:
                jp (ix)

magic:          db "SYMUNA2",0
tcpip_name:     db "TCP/IP",0
msg_banner:     db "SYMUNAPI provider snapshotter",13,10,"$"
msg_tpa:        db "SYMUNAPI: not enough TPA for metadata",13,10,"$"
msg_online:     db "SYMUNAPI: mapped provider captured",13,10,"$"
msg_nodev:      db "SYMUNAPI: TCP/IP UNAPI not found",13,10,"$"
msg_unsupported: db "SYMUNAPI: provider type not supported",13,10,"$"
msg_snapshot:   db "SYMUNAPI: provider capture failed",13,10,"$"
msg_written:    db "SYMUNAPI: metadata written",13,10,"$"
bridge_base:    dw 0
old_sp:         dw 0
tmp_slot:       db 0
tmp_segment:    db 0
tmp_helper:     dw 0
tmp_reader:     dw 0
snapshot_source: dw 0
snapshot_records: db 0
fcb_template:   db 0,"SYMUNAPI","DAT"
                ds 24,0
segment_fcb_template:
                db 0,"SYMUNAPI","SEG"
                ds 24,0
info_fcb:       ds 36,0
snapshot_dma:   ds 128,0

end:
                save "SYMUNAPI.COM",#100,end-#100
