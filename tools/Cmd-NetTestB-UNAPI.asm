;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
;@                                                                            @
;@                           SymbOS network daemon                            @
;@                               N E T T E S T                                @
;@                                                                            @
;@               (c) 2015 by Prodatron / SymbiosiS (Jörn Mika)                @
;@                                                                            @
;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


;### PRGPRZ -> Programm-Prozess
tmpbuf  ds 256

prgprz  call SyShell_PARALL     ;angehangene Parameter und Shell-Prozess, -Höhe und -Breite holen
        call SyShell_PARSHL
        jp c,prgend

        ld hl,txttit            ;title text
        ld e,0
        call SyShell_STROUT
        jp c,prgend

        call SyNet_NETINI           ;init network API
        ld hl,txterrdmn
        jp c,prgend0
        ld a,(SyNet_PrcID)
        call clcdez
        ld (txtdmnfnd1),hl
        ld hl,txtdmnfnd
        ld e,0
        call SyShell_STROUT

        ld a,0                      ;open connection
        ld hl,-1
        ld ix,1
        ld iy,1
        ld de,80
        call SyNet_TCPOPN
        ld (netsck),a
        ld hl,txterrcon
        jp c,prgend0
        ld hl,txtstaopn:call SyShell_STROUT0

prgprz1 rst #30                     ;wait until established
        call SyNet_NETEVT
        jr c,prgprz1
        ld a,l
        and 127
        cp 2
        jr c,prgprz1
        ld hl,txterrest
        jp nz,prgprz5
        ld hl,txtstaest:call SyShell_STROUT0

        ld hl,nettstdata            ;send testdata1
        ld bc,nettstdata0-nettstdata
        ld de,(App_BnkNum)
        ld a,(netsck)
        call netsnd
        ld hl,txterrsnd
        jp c,prgprz5
        ld hl,txtstasnd:call SyShell_STROUT0
        call SyShell_CHRINP0

        ld hl,nettstdatb            ;send testdata2
        ld bc,nettstdatb0-nettstdatb
        ld de,(App_BnkNum)
        ld a,(netsck)
        call netsnd
        ld hl,txterrsnd
        jp c,prgprz5
        ld hl,txtstasnd:call SyShell_STROUT0
        call SyShell_CHRINP0

        ld hl,nettstdatc            ;send testdata3
        ld bc,nettstdatc0-nettstdatc
        ld de,(App_BnkNum)
        ld a,(netsck)
        call netsnd
        ld hl,txterrsnd
        jp c,prgprz5
        ld hl,txtstasnd:call SyShell_STROUT0
        call SyShell_CHRINP0

        ld hl,nettstdatd            ;send testdata4
        ld bc,nettstdatd0-nettstdatd
        ld de,(App_BnkNum)
        ld a,(netsck)
        call netsnd
        ld hl,txterrsnd
        jp c,prgprz5
        ld hl,txtstasnd:call SyShell_STROUT0
        call SyShell_CHRINP0

        ld hl,nettstdate            ;send testdata4
        ld bc,nettstdate0-nettstdate
        ld de,(App_BnkNum)
        ld a,(netsck)
        call netsnd
        ld hl,txterrsnd
        jp c,prgprz5
        ld hl,txtstasnd:call SyShell_STROUT0
        call SyShell_CHRINP0

        jr prgprz4

prgprz5 call SyShell_STROUT0
        jr prgprz4
prgprz4 ld a,(netsck)               ;close connection
        call SyNet_TCPCLO
        ld hl,txtstaclo:call SyShell_STROUT0
        jr prgend



;### PRGEND -> Programm beenden
prgend0 ld e,0
        call SyShell_STROUT
prgend  call SyShell_EXIT       ;tell Shell, that process will quit
        ld hl,(App_BegCode+prgpstnum)
        call SySystem_PRGEND
prgend1 rst #30
        jr prgend1


;==============================================================================
;### SUB-ROUTINEN #############################################################
;==============================================================================

;### NETSND -> sends data to a TCP connection
;### Input      A=handle, HL=address, E=bank, BC=length
;### Output     CF=0 ok, CF=1 connection closed (BC=remaining length)
;### Destroyed  ??
netsnd  push de
        push hl
        call SyNet_TCPSND   ;BC=bytes sent, HL=bytes remaining
        ex de,hl
        pop hl
        add hl,bc
        ld c,e
        ld b,d
        pop de
        ret z
        rst #30
        jr netsnd

;### CLCDEZ -> Rechnet Byte in zwei Dezimalziffern um
;### Eingabe    A=Wert
;### Ausgabe    L=10er-Ascii-Ziffer, H=1er-Ascii-Ziffer
;### Veraendert AF
clcdez  ld l,"0"
clcdez1 sub 10
        jr c,clcdez2
        inc l
        jr clcdez1
clcdez2 add "0"+10
        ld h,a
        ret


;==============================================================================
;### DATEN-TEIL ###############################################################
;==============================================================================

txttit  db 13,10
        db "NetTest 1.0 (c)oded 2015 by Prodatron",13,10,0
txtdmnfnd   db "Network daemon found as process "
txtdmnfnd1  db "##",13,10,0

txterrdmn   db "Network daemon not running!",13,10,0
txterrcon   db "Error: Can't open connection",13,10,0

txtstaopn   db "Opening 1.1.1.1:80",13,10,0
txtstaest   db "Connection established",13,10,0
txtstasnd   db "Data sent",13,10,0
txtstarcv   db "Data received: ",0
txtstacrm   db "Closed by remote host",13,10,0
txtstaclo   db 13,10,"Connection closed",13,10,0
txtstalfd   db 13,10,0

txterrest   db "Error while establishing connection",13,10,0
txterrrcv   db "Error while receiving data",13,10,0
txterrsnd   db "Error while sending data",13,10,0

nettstdata  db "GET / HTTP/1.0",13,10
            db "Host: 1.1.1.1",13,10
            db "Connection: close",13,10
            db 13,10
nettstdata0
nettstdatb  db ""
nettstdatb0
nettstdatc  db ""
nettstdatc0
nettstdatd  db ""
nettstdatd0
nettstdate  db ""
nettstdate0


nettstdat
db "raahh raahh raahh raahh raahh raahh raahh raahh raahh raahh raahh raahh raahh raahh raahh raahh ",13,10
nettstdat0

netsck      db 0

App_BegData

;### nothing (more) here
db 0

;==============================================================================
;### TRANSFER-TEIL ############################################################
;==============================================================================

App_BegTrns
;### PRGPRZS -> stack for application process
        ds 128
prgstk  ds 6*2
        dw prgprz
App_PrcID db 0
App_MsgBuf ds 14
