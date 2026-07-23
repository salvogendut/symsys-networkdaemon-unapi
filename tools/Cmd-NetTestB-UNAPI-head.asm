nolist

org #1000
relocate_count equ 0

write "NETTSTB.COM"
include "../../SymbOS-ASM-Developer-kit/LIB/SymbOS-Constants.asm"

relocate_start

App_BegCode

;### APPLICATION HEADER #######################################################

;header structure
prgdatcod       equ 0           ;Length of the code area (OS will place this area everywhere)
prgdatdat       equ 2           ;Length of the data area (screen manager data; OS will place this area inside a 16k block of one 64K bank)
prgdattra       equ 4           ;Length of the transfer area (stack, message buffer, desktop manager data; placed between #c000 and #ffff of a 64K bank)
prgdatorg       equ 6           ;Original origin of the assembler code
prgdatrel       equ 8           ;Number of entries in the relocator table
prgdatstk       equ 10          ;Length of the stack in bytes
prgdatcrn       equ 12          ;Length of crunched data      (*NOT YET SUPPORTED*)
prgdatctp       equ 14          ;Cruncher type (0=uncrunched) (*NOT YET SUPPORTED*)
prgdatnam       equ 15          ;Application name. The end of the string must be filled with 0.
prgdatidn       equ 48          ;"SymExe10" SymbOS executable file identification
prgdatcex       equ 56          ;additional memory for code area (will be reserved directly behind the loaded code area)
prgdatdex       equ 58          ;additional memory for data area (see above)
prgdattex       equ 60          ;additional memory for transfer area (see above)
prgdatres       equ 62          ;*reserved* (26 bytes)
prgdatver       equ 88          ;required OS version (1.0)
prgdatism       equ 90          ;Application icon (small version), 8x8 pixel, SymbOS graphic format
prgdatibg       equ 109         ;Application icon (big version), 24x24 pixel, SymbOS graphic format
prgdatlen       equ 256         ;length of header

prgpstdat       equ 6           ;start address of the data area
prgpsttra       equ 8           ;start address of the transfer area
prgpstspz       equ 10          ;additional sub process or timer IDs (4*1)
prgpstbnk       equ 14          ;64K ram bank (1-15), where the application is located
prgpstmem       equ 48          ;additional memory areas; 8 memory areas can be registered here, each entry consists of 5 bytes
                                ;00  1B  Ram bank number (1-8; if 0, the entry will be ignored)
                                ;01  1W  Address
                                ;03  1W  Length
prgpstnum       equ 88          ;Application ID
prgpstprz       equ 89          ;Main process ID

            dw App_BegData-App_BegCode  ;length of code area
            dw App_BegTrns-App_BegData  ;length of data area
            dw App_EndTrns-App_BegTrns  ;length of transfer area
prgdatadr   dw #1000                ;original origin                    POST address data area
prgtrnadr   dw relocate_count       ;number of relocator table entries  POST address transfer area
prgprztab   dw prgstk-App_BegTrns   ;stack length                       POST table processes
            dw 0                    ;crunched data length
App_BnkNum  db 0                    ;crunched data type                 POST bank number
            db "NetTstB":ds 17:db 0 ;name, fixed 24-byte field + terminator
            db 0                    ;flags
            dw 0                    ;16 colour icon offset
            ds 5                    ;*reserved*
prgmemtab   db "SymExe10"           ;SymbOS-EXE-identifier              POST table reserved memory areas
            dw 0                    ;additional code memory
            dw 0                    ;additional data memory
            dw 0                    ;additional transfer memory
            ds 26                   ;*reserved*
            db 0,2                  ;required OS version (2.0)
prgicnsml   db 2, 8, 8:ds  16
prgicnbig   db 6,24,24:ds 144


;*** SYMSHELL LIBRARY USAGE
;   SyShell_PARALL              ;Fetches parameters/switches from command line
;   SyShell_PARSHL              ;Parses SymShell info switch
use_SyShell_PARFLG      equ 1   ;Validates present switches
use_SyShell_CHRINP      equ 1   ;Reads a char from the input source
use_SyShell_STRINP      equ 1   ;Reads a string from the input source
use_SyShell_CHROUT      equ 1   ;Sends a char to the output destination
use_SyShell_STROUT      equ 1   ;Sends a string to the output destination
use_SyShell_PTHADD      equ 0   ;...
;   SyShell_EXIT                ;Informs SymShell about an exit event

;*** SYSTEM MANAGER LIBRARY USAGE
use_SySystem_PRGRUN     equ 0   ;Starts an application or opens a document
use_SySystem_PRGEND     equ 1   ;Stops an application and frees its resources
use_SySystem_PRGSRV     equ 1   ;Manages shared services or finds applications
use_SySystem_SYSWRN     equ 0   ;Opens an info, warning or confirm box
use_SySystem_SELOPN     equ 0   ;Opens the file selection dialogue
use_SySystem_HLPOPN	equ 0   ;HLP file handling

;*** NETWORK DAEMON LIBRARY USAGE
;   SyNet_NETINI                ;...
use_SyNet_NETEVT        equ 1   ;Network event check
use_SyNet_CFGGET        equ 0   ;Config get data
use_SyNet_CFGSET        equ 0   ;Config set data
use_SyNet_CFGSCK        equ 0   ;Config socket status
use_SyNet_TCPOPN        equ 1   ;Tcp open connection
use_SyNet_TCPCLO        equ 1   ;TCP close connecton
use_SyNet_TCPSTA        equ 1   ;TCP status of connection
use_SyNet_TCPRCV        equ 0   ;TCP receive from connection
use_SyNet_TCPSND        equ 1   ;TCP send to connection
use_SyNet_TCPSKP        equ 0   ;TCP skip received data
use_SyNet_TCPFLS        equ 0   ;TCP flush send buffer
use_SyNet_TCPDIS        equ 1   ;TCP disconnect connection
use_SyNet_TCPRLN        equ 0   ;TCP receive textline from connection
use_SyNet_UDPOPN        equ 0   ;UDP open
use_SyNet_UDPCLO        equ 0   ;UDP close
use_SyNet_UDPSTA        equ 0   ;UDP status
use_SyNet_UDPRCV        equ 0   ;UDP receive
use_SyNet_UDPSND        equ 0   ;UDP send
use_SyNet_UDPSKP        equ 0   ;UDP skip received data
use_SyNet_DNSRSV        equ 0   ;DNS resolve
use_SyNet_DNSVFY        equ 0   ;DNS verify

include "../build/symbos_lib-SymShell.asm"
include "../build/symbos_lib-SystemManager-test.asm"
include "../build/symbos_lib-NetworkDaemon.asm"
include "Cmd-NetTestB-UNAPI.asm"

App_EndTrns

relocate_table
relocate_end
