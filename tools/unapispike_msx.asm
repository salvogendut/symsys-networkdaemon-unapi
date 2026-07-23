; tools/unapispike_msx.asm - MSX-DOS TCP/IP UNAPI discovery diagnostic.
;
; Build: rasm tools/unapispike_msx.asm
; Run:   stage UNAPISPK.COM on a Nextor image, optionally run UNAPINET first,
;        then run UNAPISPK from AUTOEXEC.BAT.

BDOS            equ #0005
_CONOUT         equ #02
_STROUT         equ #09
_TERM0          equ #00

EXTBIO          equ #ffca
UNAPI_ARG       equ #f847

UNAPI_DIRECT    equ 1
UNAPI_MAPPED    equ 2

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

                org #100

start:
                ld de,msg_banner
                call strout

                ld hl,tcpip_name
                ld de,UNAPI_ARG
                ld bc,7
                ldir

                xor a
                ld de,#2222
                ld bc,0
                ld hl,0
                call EXTBIO
                ld (impl_count),a        ;keep A too for diagnostics
                ld a,b
                ld (impl_count),a
                ld de,msg_count
                call strout
                ld a,(impl_count)
                call print_a_hex
                call crlf
                ld a,(impl_count)
                or a
                jr nz,have_impl

                ld de,msg_no_impl
                call strout
                jp quit

have_impl:
                ld a,1
                ld de,#2222
                ld bc,0
                ld hl,0
                call EXTBIO
                ld (impl_slot),a
                ld a,b
                ld (impl_segment),a
                ld (impl_entry),hl

                ld de,msg_slot
                call strout
                ld a,(impl_slot)
                call print_a_hex
                ld de,msg_segment
                call strout
                ld a,(impl_segment)
                call print_a_hex
                ld de,msg_entry
                call strout
                ld hl,(impl_entry)
                call print_hl_hex
                call crlf

                ld hl,(impl_entry)
                ld de,#c000
                or a
                sbc hl,de
                jr nc,select_direct

                ld a,(impl_segment)
                cp #ff
                jr nz,select_mapped
                ld de,msg_rom_mapped
                call strout
                jp quit

select_direct:
                ld a,UNAPI_DIRECT
                ld (call_kind),a
                ld de,msg_direct
                call strout
                jr call_info

select_mapped:
                ld a,#ff
                ld de,#2222
                ld bc,0
                ld hl,0
                call EXTBIO
                ld (impl_helper),hl
                ld a,h
                or l
                jr nz,have_helper
                ld de,msg_no_helper
                call strout
                jp quit
have_helper:
                ld a,(impl_slot)
                ld h,a
                ld a,(impl_segment)
                ld l,a
                ld (impl_iy),hl
                ld a,UNAPI_MAPPED
                ld (call_kind),a
                ld de,msg_mapped
                call strout
                ld de,msg_helper
                call strout
                ld hl,(impl_helper)
                call print_hl_hex
                call crlf

call_info:
                ld a,TCPIP_GET_INFO
                ld bc,0
                ld de,0
                ld hl,0
                call unapi_call
                ld (last_err),a
                ld de,msg_info
                call strout
                ld a,(last_err)
                call print_a_hex
                ld de,msg_ver
                call strout
                ld a,(last_bc+1)
                call print_a_hex
                ld a,'.'
                call conout
                ld a,(last_bc)
                call print_a_hex
                ld de,msg_spec
                call strout
                ld hl,(last_de)
                call print_hl_hex
                call crlf
                ld a,(last_err)
                or a
                jr nz,quit

                ld a,TCPIP_GET_CAPAB
                ld bc,#0100             ;capability block 1
                ld de,0
                ld hl,0
                call unapi_call
                ld (last_err),a
                ld de,msg_cap
                call strout
                ld a,(last_err)
                call print_a_hex
                ld de,msg_cap_hl
                call strout
                ld hl,(last_hl)
                call print_hl_hex
                call crlf

                ld de,msg_ok
                call strout
                call dns_smoke
                call tcp_smoke

quit:
                ld c,_TERM0
                jp BDOS

; ---------------------------------------------------------------------------
; DNS smoke test: resolve localhost, then use the result for TCP smoke.
; ---------------------------------------------------------------------------

dns_smoke:
                ld de,msg_dns_begin
                call strout
                ld a,TCPIP_DNS_Q
                ld b,0
                ld c,0
                ld de,0
                ld hl,dns_host
                call unapi_call
                ld de,msg_dns_q
                call strout
                ld a,(last_a)
                call print_a_hex
                call crlf
                ld a,(last_a)
                or a
                ret nz

                ld hl,#0400
                ld (wait_count),hl
dns_wait_loop:
                ld a,TCPIP_DNS_S
                ld b,0
                ld c,0
                ld de,0
                ld hl,0
                call unapi_call
                ld a,(last_a)
                or a
                jr nz,dns_failed
                ld a,(last_bc+1)
                cp 2
                jr z,dns_done
                cp 1
                jr nz,dns_failed
                call tcp_wait_tick
                ld hl,(wait_count)
                dec hl
                ld (wait_count),hl
                ld a,h
                or l
                jr nz,dns_wait_loop

dns_failed:
                ld de,msg_dns_fail
                call strout
                ld a,(last_a)
                call print_a_hex
                ld de,msg_state_b
                call strout
                ld a,(last_bc+1)
                call print_a_hex
                call crlf
                or 1
                ret

dns_done:
                ld hl,(last_hl)
                ld (dns_ip+0),hl
                ld (tcp_open_params+0),hl
                ld hl,(last_de)
                ld (dns_ip+2),hl
                ld (tcp_open_params+2),hl
                ld de,msg_dns_ok
                call strout
                ld a,(dns_ip+0)
                call print_a_hex
                ld a,'.'
                call conout
                ld a,(dns_ip+1)
                call print_a_hex
                ld a,'.'
                call conout
                ld a,(dns_ip+2)
                call print_a_hex
                ld a,'.'
                call conout
                ld a,(dns_ip+3)
                call print_a_hex
                call crlf
                xor a
                ret

; ---------------------------------------------------------------------------
; TCP smoke test: resolved localhost:8080, HTTP/1.0 request.
; ---------------------------------------------------------------------------

tcp_smoke:
                ld de,msg_tcp_begin
                call strout

                ld a,TCPIP_TCP_OPEN
                ld bc,0
                ld de,0
                ld hl,tcp_open_params
                call unapi_call
                ld de,msg_tcp_open
                call strout
                ld a,(last_a)
                call print_a_hex
                ld de,msg_handle
                call strout
                ld a,(last_bc+1)
                ld (tcp_handle),a
                call print_a_hex
                call crlf
                ld a,(last_a)
                or a
                ret nz

                call tcp_wait_established
                ret nz

                ld de,msg_tcp_send
                call strout
                ld a,TCPIP_TCP_SEND
                push af
                ld a,(tcp_handle)
                ld b,a
                pop af
                ld c,1
                ld de,http_request
                ld hl,http_request_end-http_request
                call unapi_call
                ld a,(last_a)
                call print_a_hex
                call crlf
                ld a,(last_a)
                or a
                jr nz,tcp_abort

                call tcp_wait_rx
                jr nz,tcp_abort

                ld de,msg_tcp_recv
                call strout
                ld a,TCPIP_TCP_RCV
                push af
                ld a,(tcp_handle)
                ld b,a
                pop af
                ld c,0
                ld de,tcp_rxbuf
                ld hl,256
                call unapi_call
                ld a,(last_a)
                call print_a_hex
                ld de,msg_rx_bc
                call strout
                ld hl,(last_bc)
                call print_hl_hex
                call crlf
                ld a,(last_a)
                or a
                jr nz,tcp_abort

                ld de,msg_tcp_close
                call strout
                ld a,TCPIP_TCP_CLOSE
                push af
                ld a,(tcp_handle)
                ld b,a
                pop af
                ld c,0
                ld de,0
                ld hl,0
                call unapi_call
                ld a,(last_a)
                call print_a_hex
                call crlf
                ld de,msg_tcp_ok
                call strout
                xor a
                ret

tcp_abort:
                ld de,msg_tcp_abort
                call strout
                ld a,TCPIP_TCP_ABORT
                push af
                ld a,(tcp_handle)
                ld b,a
                pop af
                ld c,0
                ld de,0
                ld hl,0
                call unapi_call
                ld a,(last_a)
                call print_a_hex
                call crlf
                or 1
                ret

tcp_wait_established:
                ld hl,#0400
                ld (wait_count),hl
tcp_wait_established_loop:
                call tcp_state
                ld a,(last_a)
                or a
                jr nz,tcp_wait_established_fail
                ld a,(last_bc+1)
                cp 4
                jr z,tcp_wait_established_ok
                cp 7
                jr z,tcp_wait_established_ok
                call tcp_wait_tick
                ld hl,(wait_count)
                dec hl
                ld (wait_count),hl
                ld a,h
                or l
                jr nz,tcp_wait_established_loop
tcp_wait_established_fail:
                ld de,msg_tcp_state
                call strout
                ld a,(last_a)
                call print_a_hex
                ld de,msg_state_b
                call strout
                ld a,(last_bc+1)
                call print_a_hex
                call crlf
                or 1
                ret
tcp_wait_established_ok:
                ld de,msg_tcp_est
                call strout
                xor a
                ret

tcp_wait_rx:
                ld hl,#0800
                ld (wait_count),hl
tcp_wait_rx_loop:
                call tcp_state
                ld a,(last_a)
                or a
                jr nz,tcp_wait_rx_fail
                ld hl,(last_hl)
                ld a,h
                or l
                jr nz,tcp_wait_rx_ok
                call tcp_wait_tick
                ld hl,(wait_count)
                dec hl
                ld (wait_count),hl
                ld a,h
                or l
                jr nz,tcp_wait_rx_loop
tcp_wait_rx_fail:
                ld de,msg_tcp_rxwait
                call strout
                ld a,(last_a)
                call print_a_hex
                ld de,msg_state_b
                call strout
                ld a,(last_bc+1)
                call print_a_hex
                ld de,msg_avail
                call strout
                ld hl,(last_hl)
                call print_hl_hex
                call crlf
                or 1
                ret
tcp_wait_rx_ok:
                ld de,msg_tcp_rxready
                call strout
                ld hl,(last_hl)
                call print_hl_hex
                call crlf
                xor a
                ret

tcp_state:
                ld a,TCPIP_TCP_STATE
                push af
                ld a,(tcp_handle)
                ld b,a
                pop af
                ld c,0
                ld de,0
                ld hl,0
                jp unapi_call

tcp_wait_tick:
                ld a,TCPIP_WAIT
                ld bc,0
                ld de,0
                ld hl,0
                jp unapi_call

; ---------------------------------------------------------------------------
; UNAPI call bridge
; ---------------------------------------------------------------------------

unapi_call:
                ld (call_fn),a
                ld (call_bc),bc
                ld (call_de),de
                ld (call_hl),hl
                push ix
                push iy
                ld a,(call_kind)
                cp UNAPI_DIRECT
                jp z,call_direct
                cp UNAPI_MAPPED
                jp z,call_mapped
                ld a,#ff
                jr unapi_store

call_direct:
                ld hl,unapi_ret
                push hl
                ld hl,(impl_entry)
                push hl
                jr unapi_regs

call_mapped:
                ld iy,(impl_iy)
                ld ix,(impl_entry)
                ld hl,unapi_ret
                push hl
                ld hl,(impl_helper)
                push hl

unapi_regs:
                ld a,(call_fn)
                ld bc,(call_bc)
                ld de,(call_de)
                ld hl,(call_hl)
                ret

unapi_ret:
unapi_store:
                ld (last_a),a
                ld (last_bc),bc
                ld (last_de),de
                ld (last_hl),hl
                pop iy
                pop ix
                ret

; ---------------------------------------------------------------------------
; Console helpers
; ---------------------------------------------------------------------------

strout:
                ld c,_STROUT
                jp BDOS

crlf:
                ld de,msg_crlf
                jr strout

conout:
                ld e,a
                ld c,_CONOUT
                jp BDOS

print_hl_hex:
                push hl
                ld a,h
                call print_a_hex
                pop hl
                ld a,l
                jr print_a_hex

print_a_hex:
                push af
                rrca
                rrca
                rrca
                rrca
                call print_nibble
                pop af
print_nibble:
                and #0f
                add a,'0'
                cp '9'+1
                jr c,print_digit
                add a,7
print_digit:
                jp conout

; ---------------------------------------------------------------------------
; State and text
; ---------------------------------------------------------------------------

tcpip_name:     db "TCP/IP",0

impl_count:     db 0
impl_slot:      db 0
impl_segment:   db 0
impl_entry:     dw 0
impl_helper:    dw 0
impl_iy:        dw 0
call_kind:      db 0
call_fn:        db 0
call_bc:        dw 0
call_de:        dw 0
call_hl:        dw 0
last_a:         db 0
last_err:       db 0
last_bc:        dw 0
last_de:        dw 0
last_hl:        dw 0
tcp_handle:     db 0
wait_count:     dw 0
dns_ip:         db 127,0,0,1
dns_host:       db "localhost",0

tcp_open_params:
                db 127,0,0,1            ;host loopback through openMSXnet
                db #90,#1f              ;remote port 8080
                db #ff,#ff              ;random local port
                db 0,0                  ;implementation default timeout
                db 0                    ;active, transient, no TLS

http_request:
                db "GET / HTTP/1.0",13,10
                db "Host: 127.0.0.1",13,10
                db "Connection: close",13,10
                db 13,10
http_request_end:

tcp_rxbuf:      ds 256

msg_banner:     db "UNAPISPK - TCP/IP UNAPI probe",13,10,"$"
msg_count:      db "Implementations: $"
msg_no_impl:    db "No TCP/IP UNAPI implementation found",13,10,"$"
msg_slot:       db "Slot: $"
msg_segment:    db " Segment: $"
msg_entry:      db " Entry: $"
msg_direct:     db "Call path: direct page-3",13,10,"$"
msg_mapped:     db "Call path: mapped helper",13,10,"$"
msg_helper:     db "Helper: $"
msg_rom_mapped: db "ROM mapped implementation below C000 not supported yet",13,10,"$"
msg_no_helper:  db "UNAPI RAM helper not available",13,10,"$"
msg_info:       db "GET_INFO err: $"
msg_ver:        db " version: $"
msg_spec:       db " spec: $"
msg_cap:        db "GET_CAPAB err: $"
msg_cap_hl:     db " HL: $"
msg_ok:         db "UNAPISPK OK - GET_CAPAB succeeded",13,10,"$"
msg_dns_begin:  db "DNS smoke: localhost",13,10,"$"
msg_dns_q:      db "DNS_Q err: $"
msg_dns_fail:   db "DNS failed/timeout err: $"
msg_dns_ok:     db "DNS OK: $"
msg_tcp_begin:  db "TCP smoke: localhost:8080",13,10,"$"
msg_tcp_open:   db "TCP_OPEN err: $"
msg_handle:     db " handle: $"
msg_tcp_est:    db "TCP established",13,10,"$"
msg_tcp_state:  db "TCP_STATE failed/timeout err: $"
msg_state_b:    db " state: $"
msg_tcp_send:   db "TCP_SEND err: $"
msg_tcp_rxready: db "RX available: $"
msg_tcp_rxwait: db "RX wait failed/timeout err: $"
msg_avail:      db " avail: $"
msg_tcp_recv:   db "TCP_RCV err: $"
msg_rx_bc:      db " bytes: $"
msg_tcp_close:  db "TCP_CLOSE err: $"
msg_tcp_abort:  db "TCP_ABORT err: $"
msg_tcp_ok:     db "TCP smoke OK",13,10,"$"
msg_crlf:       db 13,10,"$"

spike_end:
                save"UNAPISPK.COM",#100,spike_end-#100
