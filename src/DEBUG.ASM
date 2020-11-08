;   DEBUG.ASM Masm/JWasm assembler source for a clone of DEBUG.COM
;           Version 1.27, ??.02.2020.

;   To assemble, use:
;       jwasm -D?PM=0 -bin -Fo debug.com debug.asm
;
;   To create DEBUGX, the DPMI aware version of debug, use:
;       jwasm -D?PM=1 -bin -Fo debugx.com debug.asm

; ============================================================================
;
; Copyright (c) 1995-2003  Paul Vojta
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to
; deal in the Software without restriction, including without limitation the
; rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
; sell copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in
; all copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
; PAUL VOJTA BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
; IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
;
; ============================================================================
;
; Japheth: all extensions made by me are Public Domain. This does not
;          affect other copyrights.
;          This file is now best viewed with TAB size 4!
; ============================================================================
;   Revision history:
;       0.95e [11 January 2003]  Fixed a bug in the assember.
;       0.95f [10 September 2003]  Converted to NASM; fixed some syntax
;       incompatibilities.
;       0.98 [27 October 2003]  Added EMS commands and copyright conditions.
;
;       The changes which were done by my, japheth, are described in
;       HISTORY.TXT.
;
;   To do:
;       - support loading *.HEX files
;       - make C work with 32bit offsets in protected-mode
;       - add MMX instructions for A and U
;       - allow to modify floating point registers
;       - better syntax checks for A (so i.e. "mov ax,al" is rejected)

	option casemap:none
	option proc:private
;	option noljmp	;enable to see the short jump extensions

BS         equ 8
TAB        equ 9
LF         equ 10
CR         equ 13
TOLOWER    equ 20h
TOUPPER    equ 0dfh
TOUPPER_W  equ 0dfdfh
MNEMONOFS  equ 28	;offset in output line where mnemonics start (disassember)

if ?PM
VDD        equ 1	;try to load DEBXXVDD.DLL
NOEXTENDER equ 1	;don't assume DPMI host includes a DOS extender
WIN9XSUPP  equ 1	;avoid to hook DPMI entry when running in Win9x
DOSEMU     equ 1	;avoid to hook DPMI entry when running in DosEmu
DISPHOOK   equ 1	;display "DPMI entry hooked..."
DBGNAME    equ <"DEBUGX">
DBGNAME2   equ <"DebugX">
CATCHEXC06 equ 0	;catch exception 06h in protected-mode
CATCHEXC07 equ 0	;catch exception 07h in protected-mode
CATCHEXC0C equ 1	;catch exception 0Ch in protected-mode
MMXSUPP    equ 1	;support MMX specific commands
DXSUPP     equ 1	;support DX command
ifndef DXUNREAL
DXUNREAL   equ 0	;set to 1 if unreal-mode is to be used by DX cmd
endif
else
VDD        equ 0
NOEXTENDER equ 0
DBGNAME    equ <"DEBUG">
DBGNAME2   equ <"Debug">
MMXSUPP    equ 0	;support MMX specific commands
DXSUPP     equ 0
endif

DOSNAME    equ <"DOS">
MCB        equ 1	;support DM command
EMSCMD     equ 1	;support Xx commands
USESDA     equ 1	;use SDA to get/set PSP in real-mode
STACKSIZ   equ 200h	;debug's stack size

ifndef CATCHINT01
CATCHINT01 equ 1	;catch INT 01 (single-step)
endif
ifndef CATCHINT03
CATCHINT03 equ 1	;catch INT 03 (break)
endif
ifndef CATCHINT06
CATCHINT06 equ 0	;catch exception 06h in real-mode
endif
ifndef CATCHEXC06
CATCHEXC06 equ 0	;catch exception 06h in protected-mode
endif
ifndef CATCHINT07
CATCHINT07 equ 0	;catch exception 07h in real-mode
endif
ifndef CATCHEXC07
CATCHEXC07 equ 0	;catch exception 07h in protected-mode
endif
ifndef CATCHINT0C
CATCHINT0C equ 0	;catch exception 0Ch in real-mode
endif
ifndef CATCHEXC0C
CATCHEXC0C equ 0	;catch exception 0Ch in protected-mode
endif
ifndef CATCHINT0D
CATCHINT0D equ 0	;catch exception 0Dh in real-mode
endif
ifndef CATCHINT31
CATCHINT31 equ 0	;hook DPMI int 31h
endif
ifndef DRIVER
DRIVER     equ 0	;support to be loaded as device driver in CONFIG.SYS
endif

if ?PM or CATCHINT07
EXCCSIP    equ 1	;display CS:IP where exception occured
else
EXCCSIP    equ 0
endif

LINE_IN_LEN equ 257	;length of line_in (including header stuff)

;--- PSP offsets

if DRIVER eq 0
ALASAP	equ 02h	;Address of Last segment allocated to program
TPIV	equ 0ah	;Terminate Program Interrupt Vector (int 22h)
CCIV	equ 0eh	;Control C Interrupt Vector (int 23h)
CEIV	equ 12h	;Critical Error Interrupt Vector (int 24h)
PARENT	equ 16h	;segment of parent PSP
SPSAV	equ 2eh	;Save the stack pointer here
DTA		equ 80h	;Program arguments; also used to store file name (N cmd)
endif

;--- mne macro, used for the assembler mnemonics table

mne macro val2:REQ, dbytes:VARARG
ASMDATA segment
CURROFS = $
	ifnb <dbytes>
	 db dbytes
	endif
ASMDATA ends
	dw CURROFS - asmtab
MN_&val2 equ $ - mnlist
tmpstr catstr <!">,@SubStr(val2,1,@SizeStr(val2)-1),<!",!'>,@SubStr(val2,@SizeStr(val2)),<!'>,<+80h>
	db tmpstr
	endm

AGRP macro num,rfld
	exitm <240h + num*8 + rfld>
	endm

variant macro opcode:req, key:req, lockb, machine
ASMDATA segment
	ifnb <lockb>
	 db lockb
	endif
	ifnb <machine>
	 db machine
	endif
ainfo = (opcode) * ASMMOD + key
	db HIGH ainfo, LOW ainfo
ASMDATA ends
	endm

fpvariant macro opcode, key, addb, lockb, machine
	variant opcode, key, lockb, machine
ASMDATA segment
	db addb
ASMDATA ends
	endm

endvariant macro
ASMDATA segment
	db -1
ASMDATA ends
	endm

;--- opl macro, used to define operand types

opidx = 0
opl macro value:VARARG
	.radix 16t
if opidx lt 10h
_line textequ <OPLIST_0>,%opidx,< equ $ - oplists>
else
_line textequ <OPLIST_>,%opidx,< equ $ - oplists>
endif
_line
	ifnb <value>
	  db value
	endif
	db 0
	opidx = opidx + 1
	.radix 10t
	endm

OT macro num
	exitm <OPLIST_&num+OPTYPES_BASE>
	endm

;--- sizeprf is to make DEBUG's support for 32bit code as small as possible.
;--- for this to achieve a patch table is created in _IDATA which is filled
;--- by memory offsets where prefix bytes 66h or 67h are found.

sizeprf macro
curreip = $
_IDATA segment
	dw curreip
_IDATA ends
	db 66h
	endm

sizeprfX macro
if ?PM
	sizeprf
endif
	endm

if VDD
;--- standard BOPs for communication with DEBXXVDD on NT platforms
RegisterModule macro
	db 0C4h, 0C4h, 58h, 0
	endm
UnRegisterModule macro
	db 0C4h, 0C4h, 58h, 1
	endm
DispatchCall macro
	db 0C4h, 0C4h, 58h, 2
	endm
endif

	.8086

_TEXT segment dword public 'CODE'
if DRIVER
	dd -1
	dw 08000h					; driver flags : character dev
Strat  dw offset strategy		; offset to strategy routine
Intrp  dw offset driver_entry	; offset to interrupt handler
device_name db 'DEBUG$RR'		; device driver name

req_hdr struct
req_size db ?	;+0 number of bytes stored
unit_id  db ?	;+1 unit ID code
cmd 	 db ?	;+2 command code
status	 dw ?	;+3 status word
rsvd     db 8 dup(?);+5 reserved
req_hdr ends

request_ptr dd 0

strategy:
	mov word ptr cs:[request_ptr+0],bx
	mov word ptr cs:[request_ptr+2],es
	retf
interrupt:
	push ds
	push di
	lds di, cs:[request_ptr]	; load address of request header
	mov [di].req_hdr.status,8103h
	pop di
	pop ds
	ret
else

	org 100h
start:
	jmp initcode

endif
_TEXT ends


CONST segment readonly word public 'DATA'
CONST ends

ASMDATA segment word public 'DATA'
asmtab label byte
ASMDATA ends

_DATA segment dword public 'DATA'
_DATA ends

_ITEXT segment word public 'I_CODE'
_ITEXT ends

_IDATA segment word public 'I_DATA'
patches label word
_IDATA ends

if DRIVER
STACK segment word stack 'STACK'
	db 200h dup (?)
STACK ends
endif

DGROUP group _TEXT, CONST, ASMDATA, _DATA, _ITEXT, _IDATA

CONST segment

;--- cmds b,j,k,v,y and z don't exist yet

cmdlist	dw a_cmd,cmd_error,c_cmd,d_cmd
		dw e_cmd,f_cmd,g_cmd,h_cmd
		dw i_cmd,cmd_error,cmd_error,l_cmd
		dw m_cmd
if DRIVER
		dw cmd_error	;no N for the driver variant
else
		dw n_cmd
endif
		dw o_cmd,p_cmd
if DRIVER
		dw cmd_error	;no Q for the driver variant
else
		dw q_cmd
endif
		dw r_cmd,s_cmd,t_cmd
		dw u_cmd,cmd_error,w_cmd
if EMSCMD
		dw x_cmd
else
		dw cmd_error
endif
ENDCMD	equ <'x'>

if ?PM
dbg2324 dw i23pm, i24pm
endif

CONST ends

_DATA segment

top_sp	dw 0		;debugger's SP top ( also end of debug's MCB )
errret	dw 0		;return here if error
run_sp	dw 0		;debugger's SP when run() is executed
spadjust dw 40h 	;adjust sp by this amount for save
pspdbe	dw 0		;debuggee's program segment prefix
pspdbg	dw 0		;debugger's program segment prefix (always a segment)
run2324	dw 0,0,0,0	;debuggee's interrupt vectors 23 and 24 (both modes)
if ?PM
		dw 0,0
endif
if VDD
hVdd	dw -1		;handle of NT helper VDD
endif

sav2324	dw 0,0,0,0	;debugger's interrupt vectors 23 and 24 (real-mode only)
psp22	dw 0,0		;original terminate address in debugger's PSP
parent	dw 0		;original parent PSP in debugger's PSP (must be next)
if MCB
wMCB	dw 0		;start of MCB chain (always segment)
endif
pInDOS	dd 0		;far16 address of InDOS flag (real mode)
if ?PM
InDosSel dw 0		;selector value for pInDOS in protected-mode
endif
if USESDA
pSDA	dd 0		;far16 address of DOS swappable data area (real-mode)
if ?PM
SDASel	dw 0		;selector value for pSDA in protected-mode
endif
endif
hakstat	db 0		;whether we have hacked the vectors or not
machine	db 0		;cpu (0=8086,1,2,3=80386,...)
rmode	db 0		;flags for R command
RM_386REGS	equ 1	;bit 0: 1=386 register display
tmode	db 0		;bit 0: 1=ms-debug compatible trace mode
has_87	db 0		;if there is a math coprocessor present
if MMXSUPP
has_mmx	db 0
endif
bInDbg	db 1		;1=debugger is running
mach_87	db 0		;coprocessor (0=8087,1,2,3=80387,...)
notatty	db LF		;if standard input is from a file
stdoutf	db 0		;flags stdout device
switchar db 0		;switch character
swch1	db ' '		;switch character if it's a slash
driveno db 0
promptlen dw 0		;length of prompt
bufnext	dw line_in+2	;address of next available character
bufend	dw line_in+2	;address + 1 of last valid character

a_addr	dw 0,0,0	;address for next A command
d_addr	dw 0,0,0	;address for last D command; must follow a_addr
u_addr	dw 0,0,0	;address for last U command; must follow d_addr

if DXSUPP
x_addr	dd 0		;(phys) address for last DX command
endif
eqladdr	dw 0,0,0	;optional '=' argument in G, P and T command
;run_cs	dw 0		;save original CS when running in G
run_int	dw 0		;interrupt type that stopped the running
lastcmd	dw dmycmd
eqflag	db 0		;flag indicating presence of '=' argument
bInit	db 0		;0=ensure a valid opcode is at debuggee's CS:IP
fileext	db 0		;file extension (0 if no file name)

EXT_OTHER	equ 1
EXT_COM		equ 2
EXT_EXE		equ 4
EXT_HEX		equ 8

;--- usepacket:
;--- 0: packet is not used (int 25h/26h, cx!=FFFF)
;--- 1: packet is used (int 25h/26h, cx==FFFF)
;--- 2: packet is used (int 21h, ax=7305h, cx==FFFF)

usepacket db 0

PACKET struc
secno	dd ?	;sector number
numsecs	dw ?	;number of sectors to read
dstofs	dw ?	;ofs transfer address
dstseg	dw ?	;seg transfer address
PACKET ends

if ?PM
PACKET32 struc
secno	dd ?
numsecs	dw ?
dstofs	dd ?
dstseg	dw ?
PACKET32 ends
endif

if ?PM
packet PACKET32 <0,0,0,0>
else
packet PACKET <0,0,0,0>
endif

intsave label dword
		dd 0	;saved vector i00
if CATCHINT01
		dd 0	;saved vector i01
endif
if CATCHINT03
		dd 0	;saved vector i03
endif
if CATCHINT06
		dd 0	;saved vector i06
endif
if CATCHINT07
		dd 0	;saved vector i07
endif
if CATCHINT0C
oldi0C	dd 0	;saved vector i0C
endif
if CATCHINT0D
oldi0D	dd 0	;saved vector i0D
endif
		dd 0	;saved vector i22
if ?PM
oldi2f	dd 0
endif

;--- Parameter block for exec call.

if DRIVER eq 0
EXECS struc
environ dw ?	; +0 environment segment
cmdtail dd ?	; +2 address of command tail to copy
fcb1    dd ?	;+6 address of first FCB to copy
fcb2    dd ?	;+10 address of second FCB to copy
sssp    dd ?	;+14 initial SS:SP
csip    dd ?	;+18 initial CS:IP
EXECS ends

execblk	EXECS {0,0,5ch,6ch,0,0}
endif

REGS struct
rDI		dw ?,?	;+00 edi
rSI		dw ?,?	;+04 esi
rBP		dw ?,?	;+08 ebp
		dw ?,?	;+12 reserved
rBX		dw ?,?	;+16 ebx
rDX		dw ?,?	;+20 edx
rCX		dw ?,?	;+24 ecx
rAX		dw ?,?	;+28 eax

rDS		dw ?	;+32 ds
rES		dw ?	;+34 es
rSS		dw ?	;+36 ss
rCS		dw ?	;+38 cs
rFS		dw ?	;+40 fs
rGS		dw ?	;+42 gs

rSP		dw ?,?	;+44 esp
rIP		dw ?,?	;+48 eip
rFL		dw ?,?	;+52 eflags
if ?PM
msw		dw ?	;0000=real-mode, FFFF=protected-mode
endif
REGS ends

;--- Register save area.

	align 4		;--- must be DWORD aligned!

regs REGS <>

_DATA ends

CONST segment

;--- table of interrupt initialization

INTITEM struct
	db ?
	dw ?
INTITEM ends

inttab label INTITEM
	INTITEM <00h, intr00>
if CATCHINT01
	INTITEM <01h, intr01>
endif
if CATCHINT03
	INTITEM <03h, intr03>
endif
if CATCHINT06
	INTITEM <06h, intr06>
endif
if CATCHINT07
	INTITEM <07h, intr07>
endif
if CATCHINT0C
	INTITEM <0Ch, intr0C>
endif
if CATCHINT0D
	INTITEM <0Dh, intr0D>
endif
	INTITEM <22h, intr22>
NUMINTS = ( $ - inttab ) / sizeof INTITEM
if ?PM
	db 2Fh
NUMINTSX = NUMINTS+1
else
NUMINTSX = NUMINTS
endif

;--- register names for 'r'. One item is 2 bytes.
;--- regofs must follow regnames and order of items must match
;--- those in regnames.

regnames db 'AX','BX','CX','DX',
		'SP','BP','SI','DI','IP','FL',
		'DS','ES','SS','CS','FS','GS'
NUMREGNAMES equ ($ - regnames) / 2
regofs	dw regs.rAX, regs.rBX, regs.rCX, regs.rDX, 
		regs.rSP, regs.rBP, regs.rSI, regs.rDI, regs.rIP, regs.rFL,
		regs.rDS, regs.rES, regs.rSS, regs.rCS, regs.rFS, regs.rGS

;--- arrays flgbits, flgnams and flgnons must be consecutive
flgbits dw 800h,400h,200h,80h,40h,10h,4,1
flgnams db 'NV','UP','DI','PL','NZ','NA','PO','NC'
flgnons db 'OV','DN','EI','NG','ZR','AC','PE','CY'

;--- Instruction set information needed for the 'p' command.
;--- arrays ppbytes and ppinfo must be consecutive!

ppbytes	db 66h,67h,26h,2eh,36h,3eh,64h,65h,0f2h,0f3h	;prefixes
		db 0ach,0adh,0aah,0abh,0a4h,0a5h	;lods,stos,movs
		db 0a6h,0a7h,0aeh,0afh		;cmps,scas
		db 6ch,6dh,6eh,6fh			;ins,outs
		db 0cch,0cdh				;int instructions
		db 0e0h,0e1h,0e2h			;loop instructions
		db 0e8h						;call rel16/32
		db 09ah						;call far seg16:16/32
;		(This last one is done explicitly by the code.)
;		db 0ffh						;ff/2 or ff/3:  indirect call

;   Info for the above, respectively.
;   80h = prefix;
;   81h = address size prefix.
;   82h = operand size prefix;
;   If the high bit is not set, the next highest bit (40h) indicates that
;   the instruction size depends on whether there is an address size prefix,
;   and the remaining bits tell the number of additional bytes in the
;   instruction.

PP_ADRSIZ	equ 01h
PP_OPSIZ	equ 02h
PP_PREFIX	equ 80h
PP_VARSIZ	equ 40h

ppinfo	db 82h,81h,80h,80h,80h,80h,80h,80h,80h,80h	;prefixes
	db 0,0,0,0,0,0									;string instr
	db 0,0,0,0										;string instr
	db 0,0,0,0										;string instr
	db 0,1											;INT instr
	db 1,1,1										;LOOPx instr
	db 42h											;near CALL instr
	db 44h											;far CALL instr

PPLEN	equ $ - ppinfo

;--- Strings.

    db '!'      ;additional prompt if InDos flag is set
ifdef PROMPT
prompt1	db @CatStr(!',%PROMPT,!')
else
prompt1	db '-'		;main prompt
endif
prompt2	db ':'		;prompt for register value
if ?PM
	db '!'
prompt3	db '#'		;protected-mode prompt
endif

helpmsg db DOSNAME, ' ', DBGNAME2, ' v1.27 help screen',CR,LF
	db 'assemble',9,	'A [address]',CR,LF
	db 'compare',9,9,	'C range address',CR,LF
	db 'dump',9,9,		'D [range]',CR,LF
if ?PM
	db 'dump interrupt',9,'DI interrupt [count]',CR,LF
	db 'dump LDT',9,	'DL selector [count]',CR,LF
endif
if MCB
	db 'dump MCB chain',9,'DM',CR,LF
endif
if DXSUPP
	db 'dump ext memory',9,'DX [physical_address]',CR,LF
endif
	db 'enter',9,9,	'E address [list]',CR,LF
	db 'fill',9,9,		'F range list',CR,LF
	db 'go',9,9,		'G [=address] [breakpts]',CR,LF
	db 'hex add/sub',9,'H value1 value2',CR,LF
	db 'input',9,9,	'I[W|D] port',CR,LF
if DRIVER eq 0
	db 'load program',9,'L [address]',CR,LF
endif
	db 'load sectors',9,'L address drive sector count',CR,LF
	db 'move',9,9,		'M range address',CR,LF
	db '80x86 mode',9,	'M [x] (x=0..6)',CR,LF
	db 'set FPU mode',9,'MC [2|N] (2=287,N=no FPU)',CR,LF
if DRIVER eq 0
	db 'set name',9,	'N [[drive:][path]progname [arglist]]',CR,LF
endif
	db 'output',9,9,	'O[W|D] port value',CR,LF
	db 'proceed',9,9,	'P [=address] [count]',CR,LF
if DRIVER eq 0
	db 'quit',9,9,		'Q',CR,LF
endif
	db 'register',9,	'R [register [value]]',CR,LF
if ?PM
helpmsg2 label byte
endif
if MMXSUPP
	db 'MMX register',9,'RM',CR,LF
endif
	db 'FPU register',9,'RN',CR,LF
	db 'toggle 386 regs',9,'RX',CR,LF
	db 'search',9,9,	'S range list',CR,LF
if ?PM eq 0
helpmsg2 label byte
endif
	db 'trace',9,9,	'T [=address] [count]',CR,LF
	db 'trace mode',9,	'TM [0|1]',CR,LF
	db 'unassemble',9,	'U [range]',CR,LF
if DRIVER eq 0
	db 'write program',9,'W [address]',CR,LF
endif
	db 'write sectors',9,'W address drive sector count',CR,LF
if EMSCMD
	db 'expanded mem',9,'XA/XD/XM/XR/XS,X? for help'
endif
if ?PM
	db CR,LF,LF
	db "prompts: '-' = real/v86-mode; '#' = protected-mode"
endif
crlf db CR,LF
size_helpmsg2 equ $ - helpmsg2
	db '$'

presskey db '[more]'

errcarat db '^ Error'

dskerr0	db 'Write protect error',0
dskerr1	db 'Unknown unit error',0
dskerr2	db 'Drive not ready',0
dskerr3	db 'Unknown command',0
dskerr4	db 'Data error (CRC)',0
dskerr6	db 'Seek error',0
dskerr7	db 'Unknown media type',0
dskerr8	db 'Sector not found',0
dskerr9	db 'Unknown error',0
dskerra	db 'Write fault',0
dskerrb	db 'Read fault',0
dskerrc	db 'General failure',0

dskerrs db dskerr0-dskerr0,dskerr1-dskerr0
		db dskerr2-dskerr0,dskerr3-dskerr0
		db dskerr4-dskerr0,dskerr9-dskerr0
		db dskerr6-dskerr0,dskerr7-dskerr0
		db dskerr8-dskerr0,dskerr9-dskerr0
		db dskerra-dskerr0,dskerrb-dskerr0
		db dskerrc-dskerr0

reading	db ' read',0
writing	db ' writ',0
drive	db 'ing drive ',0
msg8088	db '8086/88',0
msgx86	db 'x86',0
no_copr	db ' without coprocessor',0
has_copr db ' with coprocessor',0
has_287	db ' with 287',0
regs386	db '386 regs o',0
tmodes	db 'trace mode is ',0
tmodes2	db ' - INTs are ',0
tmode1	db 'traced',0
tmode0	db 'processed',0
unused	db ' (unused)',0

needsmsg db '[needs x86]'		;<--- modified (7 and 9)
needsmath db '[needs math coprocessor]'
obsolete db '[obsolete]'

int0msg	db 'Divide error',CR,LF,'$'
int1msg	db 'Unexpected single-step interrupt',CR,LF,'$'
int3msg	db 'Unexpected breakpoint interrupt',CR,LF,'$'
if CATCHINT06 or CATCHEXC06
exc06msg db 'Invalid opcode fault',CR,LF,'$'
endif
if CATCHINT07 or CATCHEXC07
exc07msg db 'Coprocessor not present',CR,LF,'$'
endif
if EXCCSIP
excloc	db 'CS:IP=',0
endif

if ?PM
if CATCHEXC0C or CATCHINT0C
exc0Cmsg db 'Stack fault',CR,LF,'$'
endif
exc0Dmsg db 'General protection fault',CR,LF,'$'
exc0Emsg db 'Page fault.',CR,LF,'$'

nodosext db 'Command not supported in protected-mode without a DOS-Extender',CR,LF,'$'
nopmsupp db 'Command not supported in protected-mode',CR,LF,'$'
if DISPHOOK
dpmihook db 'DPMI entry hooked, new entry=',0
endif
nodesc	db 'resource not accessible in real-mode',0
gatewrong db 'gate not accessible',0
endif

cantwritebp db "Can't write breakpoint",0

progtrm	db CR,LF,'Program terminated normally ('
progexit db '____)',CR,LF,'$'
nowhexe	db 'EXE and HEX files cannot be written',CR,LF,'$'
nownull	db 'Cannot write: no file name given',CR,LF,'$'
wwmsg1	db 'Writing $'
wwmsg2	db ' bytes',CR,LF,'$'
diskful	db 'Disk full',CR,LF,'$'
openerr	db 'Error '
openerr1 db '____ opening file',CR,LF,'$'
doserr2	db 'File not found',CR,LF,'$'
doserr3	db 'Path not found',CR,LF,'$'
doserr5	db 'Access denied',CR,LF,'$'
doserr8	db 'Insufficient memory',CR,LF,'$'

if EMSCMD

;--- EMS error strings

;emmname	db	'EMMXXXX0'
emsnot	db 'EMS not installed',0
emserr1	db 'EMS internal error',0
emserr3	db 'Handle not found',0
emserr5	db 'No free handles',0
emserr7	db 'Total pages exceeded',0
emserr8	db 'Free pages exceeded',0
emserr9	db 'Parameter error',0
emserra	db 'Logical page out of range',0
emserrb	db 'Physical page out of range',0
emserrx	db 'EMS error '
emserrxa db '__',0

emserrs	dw emserr1,emserr1,0,emserr3,0,emserr5,0,emserr7,emserr8,emserr9
		dw emserra,emserrb

xhelpmsg db 'Expanded memory (EMS) commands:',CR,LF
	db '  Allocate	XA count',CR,LF
	db '  Deallocate	XD handle',CR,LF
	db '  Map memory	XM logical-page physical-page handle',CR,LF
	db '  Reallocate	XR handle count',CR,LF
	db '  Show status	XS',CR,LF
size_xhelpmsg equ $ - xhelpmsg

;--- strings used by XA, XD, XR and XM commands

xaans	db 'Handle created: ',0
xdans	db 'Handle deallocated: ',0
xrans	db 'Handle reallocated',0
xmans	db 'Logical page '
xmans_pos1 equ $ - xmans
		db '____ mapped to physical page '
xmans_pos2 equ $ - xmans
		db '__',0

;--- strings used by XS command

xsstr1	db 'Handle '
xsstr1a	db '____ has '
xsstr1b	db '____ pages allocated',CR,LF
size_xsstr1 equ $ - xsstr1

xsstr2	db 'phys. page '
xsstr2a	db '__ = segment '
xsstr2b	db '____  '
size_xsstr2 equ $ - xsstr2

xsstr3	db ' of a total ',0
xsstr3a	db ' EMS ',0
xsstrpg	db 'pag',0
xsstrhd	db 'handl',0
xsstr3b	db 'es have been allocated',0

xsnopgs	db 'no mappable pages',CR,LF,CR,LF,'$'

endif

;--- flags for instruction operands.
;--- First the sizes.

OP_ALL	equ 40h		;byte/word/dword operand (could be 30h but ...)
OP_1632	equ 50h		;word or dword operand
OP_8	equ 60h		;byte operand
OP_16	equ 70h		;word operand
OP_32	equ 80h		;dword operand
OP_64	equ 90h		;qword operand

OP_SIZE	equ OP_ALL		;the lowest of these

;--- These operand types need to be combined with a size flag..
;--- order must match items in asm_jmp1, bittab and dis_jmp1

OP_IMM		equ 0		;immediate
OP_RM		equ 2		;reg/mem
OP_M		equ 4		;mem (but not reg)
OP_R_MOD	equ 6		;register, determined from MOD R/M part
OP_MOFFS	equ 8		;memory offset; e.g., [1234]
OP_R		equ 10		;reg part of reg/mem byte
OP_R_ADD	equ 12		;register, determined from instruction byte
OP_AX		equ 14		;al or ax or eax

;--- These don't need a size.
;--- order must match items in asm_jmp1, bittab and dis_optab.
;--- additionally, order of OP_M64 - OP_FARMEM is used
;--- in table asm_siznum

;--- value 0 is used to terminate an operand list ( see macro opl )
OP_M64		equ 2		; 0 qword memory (obsolete?)
OP_MFLOAT	equ 4		; 1 float memory
OP_MDOUBLE	equ 6		; 2 double-precision floating memory
OP_M80		equ 8		; 3 tbyte memory
OP_MXX		equ 10		; 4 memory (size unknown)
OP_FARMEM	equ 12		; 5 memory far16/far32 pointer 
OP_FARIMM	equ 14		; 6 far16/far32 immediate
OP_REL8		equ 16		; 7 byte address relative to IP
OP_REL1632	equ 18		; 8 word or dword address relative to IP
OP_1CHK		equ 20		; 9 check for ST(1)
OP_STI		equ 22		;10 ST(I)
OP_CR		equ 24		;11 CRx
OP_DR		equ 26		;12 DRx
OP_TR		equ 28		;13 TRx
OP_SEGREG	equ 30		;14 segment register
OP_IMMS8	equ 32		;15 sign extended immediate byte
OP_IMM8		equ 34		;16 immediate byte (other args may be (d)word)
OP_MMX		equ 36		;17 MMx
OP_SHOSIZ	equ 38		;18 set flag to always show the size

OP_1		equ 40		;19 1 (simple "string" ops from here on)
OP_3		equ 42		;20 3
OP_DX		equ 44		;21 DX
OP_CL		equ 46		;22 CL
OP_ST		equ 48		;23 ST (top of coprocessor stack)
OP_CS		equ 50		;24 CS
OP_DS		equ 52		;25 DS
OP_ES		equ 54		;26 ES
OP_FS		equ 56		;27 FS
OP_GS		equ 58		;28 GS
OP_SS		equ 60		;29 SS

OP_STR equ OP_1		;first "string" op

;--- Instructions that have an implicit operand subject to a segment override
;--- (outsb/w, movsb/w, cmpsb/w, lodsb/w, xlat).

prfxtab	db 06eh,06fh, 0a4h,0a5h, 0a6h,0a7h, 0ach,0adh, 0d7h
P_LEN	equ $ - prfxtab

;--- Instructions that can be used with REP/REPE/REPNE.

replist	db 06ch,06eh,0a4h,0aah,0ach	;REP (INSB, OUTSB, MOVSB, STOSB, LODSB)
N_REPNC  equ $ - replist
		db 0a6h,0aeh				;REPE/REPNE (CMPSB, SCASB)
N_REPALL equ $ - replist

	include <debugtbl.inc>

opindex label byte
	.radix 16t
opidx = 0
	repeat ASMMOD
if opidx lt 10h
oi_name textequ <OPLIST_0>,%opidx
else
oi_name textequ <OPLIST_>,%opidx
endif
	db oi_name
opidx = opidx + 1
	endm
	.radix 10t

CONST ends

_TEXT segment

	assume ds:DGROUP

if EXCCSIP
_DATA segment
intexcip  dw 0	;IP if internal exception
intexccs  dw 0	;CS if internal exception
_DATA ends
endif

if ?PM

intcall proto stdcall :word, :word


_DATA segment
	align 4
dpmientry dd 0	;dpmi entry point returned by dpmi host
dpmiwatch dd 0	;address of dpmi initial switch to protected mode
dssel     dw 0	;debugger's segment DATA
cssel     dw 0	;debugger's segment CODE
dpmi_rm2pm dd 0	;raw mode switch real-mode to protected-mode
dpmi_pm2rm df 0	;raw mode switch protected-mode to real-mode
dpmi_size  dw 0	;size of raw mode save state buffer
dpmi_rmsav dd 0	;raw mode save state real-mode
dpmi_pmsav df 0	;raw mode save state protected-mode
scratchsel dw 0	;scratch selector used for various purposes
dpmi32    db 0	;00=16-bit client, else 32-bit client
bNoHook2F db 0	;1=int 2F, ax=1687h cannot be hooked (win3x/9x dos box, DosEmu?)
bCSAttr   db 0	;current code attribute (D bit).
bAddr32   db 0	;Address attribute. if 1, hiword(edx) is valid
if CATCHINT31
oldint31  df 0
endif
_DATA ends

	include <fptostr.inc>

;--- int 2F handler

debug2F:
	pushf
	cmp ax,1687h
dpmidisable:		;set [IP+1]=0 if hook 2F is to be disabled
	jz @F
	popf
	jmp cs:[oldi2f]
@@:
	call cs:[oldi2f]
	and ax,ax
	jnz @F
	mov word ptr cs:[dpmientry+0],di
	mov word ptr cs:[dpmientry+2],es
	mov di,offset mydpmientry
	push cs
	pop es
@@:
	iret

;--- this code is called
;--- 1. if int 2f, ax=1687h has been hooked ( winnt, hdpmi, ... )
;---    the debuggee will then call this proc directly to switch to protected-mode
;--- 2. if int 2f, ax=1687h has NOT been hooked ( win3x, win9x, dosemu )
;---    the debugger has to detect ( inside trace cmd ) that the dpmi entry
;---    address has been reached.

mydpmientry:
	mov cs:[dpmi32],al
	call cs:[dpmientry]	;call the REAL dpmi entry
	jc @F
	call installdpmi
@@:
	retf

	.286

if 0
inst db "switch to protected-mode",13,10,'$'
endif

;--- client entered protected mode.
;--- inp: [sp+4] = client real-mode CS
    
installdpmi proc
	pusha
if 0
	push ds
	push cs
	pop ds
	mov dx, offset inst
	mov ah,9
	int 21h
	pop ds
endif
	mov bp,sp		;[bp+16] = ret installdpmi, [bp+18]=ip, [bp+20]=cs
	push ds
	mov bx,cs
	mov ax,000Ah	;get a data descriptor for DEBUG's segment
	int 31h
	jc fataldpmierr
	mov ds,ax
	mov [cssel],cs
	mov [dssel],ds
	mov cx,2		;alloc 2 descriptors
	xor ax,ax
	int 31h
	jnc @F
fataldpmierr:
	mov ax,4CFFh
	int 21h
@@:
	mov [scratchsel],ax	;the first is used as scratch descriptor
	mov bx,ax
	xor cx,cx
if 1
	cmp [machine],3				;is at least a 80386?
	jb @F
else
	cmp [dpmi32],0		;is a 16-bit client?
	jz @F
endif
	dec cx			;set a limit of FFFFFFFFh
@@:
	or dx,-1
	mov ax,0008h
	int 31h
	add bx,8		;the second selector is client's CS
	xor cx,cx		;this limit is FFFF even for 32-bits
	mov ax,0008h
	int 31h
	mov dx,[bp+20]	;get client's CS
	call setrmaddr	;set base
	mov ax,cs
	lar cx,ax
	shr cx,8		;CS remains 16-bit
	mov ax,0009h
	int 31h
	mov [bp+20],bx	;set client's CS

	cld

	mov bx,word ptr [pInDOS+2]
	mov ax,2
	int 31h
	mov [InDosSel],ax
if USESDA
	mov bx,word ptr [pSDA+2]
	mov ax,2
	int 31h
	mov [SDASel],ax
endif
	mov si,offset convsegs
	mov cx,NUMSEGS
@@:
	lodsw
	mov di,ax
	mov bx,[di]
	mov ax,2
	int 31h
	jc fataldpmierr
	mov [di],ax
	loop @B

	sizeprf	;push edi
	push di
	xor bp,bp
	cmp dpmi32,0
	jz @F
	inc bp
	inc bp
@@:
	mov ax,0305h			;get raw-mode save state addresses
	int 31h
	mov word ptr [dpmi_rmsav+0],cx
	mov word ptr [dpmi_rmsav+2],bx
	sizeprf	;mov dword ptr [dpmi_pmsav],edi
	mov word ptr [dpmi_pmsav],di
	mov word ptr ds:[bp+dpmi_pmsav+2],si
	mov word ptr [dpmi_size],ax
	mov ax,0306h			;get raw-mode switch addresses
	int 31h
	mov word ptr [dpmi_rm2pm+0],cx
	mov word ptr [dpmi_rm2pm+2],bx
	sizeprf	;mov dword ptr [dpmi_pm2rm],edi
	mov word ptr [dpmi_pm2rm],di
	mov word ptr ds:[bp+dpmi_pm2rm+2],si
	sizeprf	;pop edi
	pop di

;--- hook several exceptions

	mov si,offset exctab
	sizeprf	;push edx
	push dx
	sizeprf	;xor edx,edx
	xor dx,dx
	mov dx,offset exc00
@@:
	lodsb
	mov bl,al
	mov cx,cs
	mov ax,0203h
	int 31h
	add dx,exc01-exc00
	cmp si,offset endexctab
	jb @B

if CATCHINT31
	mov bl,31h
	mov ax,0204h
	int 31h
	sizeprf	;mov dword ptr [oldint31],edx
	mov word ptr oldint31,dx
	mov word ptr ds:[bp+oldint31+2],cx
	sizeprf	;xor edx,edx
	xor dx,dx
	mov dx,offset myint31
	mov cx,cs
	mov al,05h
	int 31h
endif

	sizeprf	;pop edx
	pop dx

	mov bl,2Fh			;get int 2Fh real-mode vector
	mov ax,200h
	int 31h
	cmp cx,[pspdbg]		;did we hook it and are the last in chain?
	jnz int2fnotours
	mov dx,word ptr [oldi2f+0]
	xor cx,cx
	xchg cx,word ptr [oldi2f+2]	;then unhook
	mov ax,201h
	int 31h
int2fnotours:
	pop ds
	popa
	clc
	ret

CONST segment

convsegs label word
;	dw offset run_cs
;	dw offset pInDOS+2
;if USESDA
;	dw offset pSDA+2
;endif
	dw offset a_addr+4
	dw offset d_addr+4
NUMSEGS equ ($-convsegs)/2

exctab label byte
	db 0
	db 1
	db 3
if CATCHEXC06
	db 06h
endif
if CATCHEXC07
	db 07h
endif
if CATCHEXC0C
	db 0Ch
endif
	db 0Dh
	db 0Eh
endexctab label near

CONST ends

;--- stack frames DPMI exception handlers 16/32-bit

EXFR16 struc
	dw 8 dup (?)
	dw 2 dup (?)
	dw ?
rIP	dw ?
rCS	dw ?
rFL	dw ?
rSP	dw ?
rSS	dw ?
EXFR16 ends

EXFR32 struc
		dd 8 dup (?)
		dd 2 dup (?)
		dd ?
rEIP	dd ?
rCS		dw ?
		dw ?
rEFL	dd ?
rESP	dd ?
rSS		dw ?
		dw ?
EXFR32 ends

exc16_xx:
	pusha
	mov bp,sp
	push ds
	mov ds,cs:[dssel]
	mov ax,[bp].EXFR16.rIP
	mov bx,[bp].EXFR16.rCS
	mov cx,[bp].EXFR16.rFL
	mov dx,[bp].EXFR16.rSP
	mov si,[bp].EXFR16.rSS
	mov [bp].EXFR16.rCS, cs
	mov [bp].EXFR16.rSS, ds
	cmp [bInDbg],0				;did the exception occur inside DEBUG?
	jz isdebuggee16
if EXCCSIP
	mov intexcip, ax
	mov intexccs, bx
endif
	mov [bp].EXFR16.rIP,offset ue_intx
	mov ax,[top_sp]
	mov [bp].EXFR16.rSP, ax
	and byte ptr [bp].EXFR16.rFL+1, not 1	;reset TF
	pop ax
	jmp isdebugger16
isdebuggee16:
	mov [bp].EXFR16.rIP, offset intrtn2
	and byte ptr [bp].EXFR16.rFL+1, not 3	;reset IF + TF
	mov [bp].EXFR16.rSP, offset regs.rSS
	mov [regs.rIP],ax
	mov [regs.rCS],bx
	mov [regs.rFL],cx
	mov [regs.rSP],dx
	mov [regs.rSS],si
;	pop ax
;	mov [regs.rDS],ax
;	mov ds,ax
	pop ds
isdebugger16:
	popa
	retf

exc00:
	push ds
	push offset int0msg
	jmp exc_xx
exc01:
	push ds
	push offset int1msg
	jmp exc_xx
exc03:
	push ds
	push offset int3msg
	jmp exc_xx
if CATCHEXC06
exc06:
	push ds
	push offset exc06msg
	jmp exc_xx
endif
if CATCHEXC07
exc07:
	push ds
	push offset exc07msg
	jmp exc_xx
endif
if CATCHEXC0C
exc0c:
	push ds
	push offset exc0Cmsg
	jmp exc_xx
endif
exc0d:
	push ds
	push offset exc0Dmsg
	jmp exc_xx
exc0e:
	push ds
	push offset exc0Emsg
exc_xx:
	mov ds,cs:[dssel]
	pop [run_int]
	cmp [dpmi32],0
	pop ds
	jz exc16_xx

	.386

	pushad
	mov ebp,esp
	push ds
	mov ds,cs:[dssel]
	mov eax,[ebp].EXFR32.rEIP
	mov bx, [ebp].EXFR32.rCS
	mov ecx,[ebp].EXFR32.rEFL
	mov edx,[ebp].EXFR32.rESP
	mov si, [ebp].EXFR32.rSS
	mov [ebp].EXFR32.rCS, cs
	mov [ebp].EXFR32.rSS, ds
	cmp [bInDbg],0	;did the exception occur inside DEBUG?
	jz isdebuggee32
if EXCCSIP
	mov intexcip, ax
	mov intexccs, bx
endif
	mov [ebp].EXFR32.rEIP,offset ue_intx
	movzx eax,[top_sp]
	mov [ebp].EXFR32.rESP, eax
	and byte ptr [ebp].EXFR32.rEFL+1, not 1	;reset TF
	pop ax
	jmp isdebugger32
isdebuggee32:
	mov [ebp].EXFR32.rEIP, offset intrtn2
	and byte ptr  [ebp].EXFR32.rEFL+1, not 3;reset IF + TF
	mov [ebp].EXFR32.rESP, offset regs.rSS
	mov dword ptr [regs.rIP], eax
	mov [regs.rCS],bx
	mov [regs.rFL],cx
	mov dword ptr [regs.rSP],edx
	mov [regs.rSS],si
;	pop ax
;	mov [regs.rDS],ax
;	mov ds,ax
	pop ds
isdebugger32:
	popad
	db 66h
	retf

installdpmi endp

if CATCHINT31
myint31 proc
	cmp ax,0203h	;set exception vector?
	jz @F
notinterested:
	cmp cs:dpmi32,0
	jz $+3
	db 66h		;jmp fword ptr []
	jmp dword ptr cs:[oldint31]
@@:
	cmp bl,1
	jz @F
	cmp bl,3
	jz @F
	cmp bl,0Dh
	jz @F
	cmp bl,0Eh
	jz @F
	jmp notinterested
@@:
	cmp cs:dpmi32,0
	jz $+3
	db 66h		;iretd
	iret

myint31 endp
endif


i23pm:
	cmp cs:[dpmi32],0
	jz @F
	db 66h
	retf 4
@@:
	retf 2
i24pm:
	cmp cs:[dpmi32],0
	jz @F
	db 66h
@@:
	iret

	.8086

endif	;PM

;   intr22 - INT 22 (Program terminate) interrupt handler.
;   This is for DEBUG itself:  it's a catch-all for the various INT 23
;   and INT 24 calls that may occur unpredictably at any time.
;   What we do is pretend to be a command interpreter (which we are,
;   in a sense, just a different sort of command) by setting the PSP of
;   our parent equal to our own PSP so that DOS does not free our memory
;   when we quit.  Therefore control ends up here when Control-Break or
;   an Abort in Abort/Retry/Fail is selected.

intr22:
	cld			;reestablish things
	mov ax,cs
	mov ds,ax
	mov ss,ax

;--- fall through to cmdloop

;--- Begin main command loop.

cmdloop proc
	mov sp,[top_sp]	;restore stack (this must be first)
	mov [errret],offset cmdloop
	push ds
	pop es
if DRIVER eq 0
	call isdebuggeeloaded
	jnz @F
	call createdummytask	;if no task is active, create a dummy one
@@:
endif
	mov cx,1
	mov dx,offset prompt1
if ?PM
	call ispm
	jz @F
	mov dx,offset prompt3
@@:
endif
	call InDos
	jz @F
	dec dx          ;if inside DOS, display a '!' before the real prompt
	inc cx
@@:
	call getline	;prompted input
	cmp al,CR
	jnz @F
	mov dx, [lastcmd]
	dec si
	jmp cmd4
@@:
	cmp al,';'
	je cmdloop	;if comment
	cmp al,'?'
	je printhelp	;if request for help
	or al,TOLOWER
	sub al,'a'
	cmp al,ENDCMD - 'a'
	ja errorj1		;if not recognized
	cbw
	xchg bx,ax
	call skipcomma
	shl bx,1
	mov dx,[cmdlist+bx]
	mov [lastcmd],offset dmycmd
cmd4:
	mov di,offset line_out
	call dx
	jmp cmdloop		;back to the top

errorj1:
	jmp cmd_error

cmdloop endp


dmycmd:
	ret

printhelp:
	mov dx,offset helpmsg
	mov cx,offset helpmsg2 - offset helpmsg
	call stdout
	call waitkey
	mov dx,offset helpmsg2
	mov cx,size_helpmsg2
	call stdout
	jmp cmdloop		;done

waitkey proc
	cmp [notatty],0     ;stdin a file?
	jnz nowait
	test [stdoutf],80h	;stdout a file?
	jz nowait
	push es
	mov ax,40h		;0040h is a bimodal segment/selector
	mov es,ax
	cmp byte ptr es:[84h],30  ;rows >= 30?
	pop es
	jnc nowait
	mov dx,offset presskey
	mov cx,sizeof presskey
	call stdout
;	mov ah,8		;use DOS
;	int 21h
	mov ah,0		;v1.27: use BIOS
	int 16h
	mov al,CR
	call stdoutal
nowait:
	ret
waitkey endp

;--- A command - tiny assembler.

_DATA segment

asm_mn_flags	db 0	;flags for the mnemonic

AMF_D32		equ 1		;32bit opcode/data operand
AMF_WAIT	equ 2
AMF_A32		equ 4		;address operand is 32bit
AMF_SIB		equ 8		;there's a SIB in the arguments
AMF_MSEG	equ 10h		;if a seg prefix was given b4 mnemonic
AMF_FSGS	equ 20h		;if FS or GS was encountered

AMF_D16		equ 40h		;16bit opcode/data operand
AMF_ADDR	equ 80h		;address operand is given

;--- aa_saved_prefix and aa_seg_pre must be consecutive.
aa_saved_prefix	db 0	;WAIT or REP... prefix
aa_seg_pre	db 0		;segment prefix

mneminfo	dw 0		;address associated with the mnemonic
a_opcode	dw 0		;op code info for this variant
a_opcode2	dw 0		;copy of a_opcode for obs-instruction

AINSTR struct
rmaddr	dw ?		;address of operand giving the R/M byte
;--- regmem and sibbyte must be consecutive
regmem	db ?		;mod reg r/m part of instruction
sibbyte	db ?		;SIB byte
immaddr	dw ?		;address of operand giving the immed stf
xxaddr	dw ?		;address of additional stuff
;--- dismach and dmflags must be consecutive
dismach	db ?		;type of processor needed
dmflags	db ?		;flags for extra processor features

DM_COPR		equ 1	;math coprocessor
DM_MMX		equ 2	;MMX extensions

opcode_or	db ?	;extra bits in the op code
opsize		db ?	;size of this operation (2 or 4)
varflags	db ?	;flags for this variant

VAR_LOCKABLE	equ 1	;variant is lockable
VAR_MODRM		equ 2	;if there's a MOD R/M here
VAR_SIZ_GIVN	equ 4	;if a size was given
VAR_SIZ_FORCD	equ 8	;if only one size is permitted
VAR_SIZ_NEED	equ 10h	;if we need the size
VAR_D16			equ 20h	;if operand size is WORD
VAR_D32			equ 40h	;if operand size is DWORD

reqsize	db ?		;size that this arg should be
AINSTR ends

ai	AINSTR <?>

_DATA ends

CONST segment

;--- search for "obsolete" instructions
;--- dbe0: FENI
;--- dbe1: FDISI
;--- dbe4: FSETPM
;---  124: MOV TRx, reg
;---  126: MOV reg, TRx

a_obstab	dw 0dbe0h,0dbe1h,0dbe4h,124h,126h	;obs. instruction codes
obsmach		db 1,1,2,4,4	;max permissible machine for the above

modrmtab	db 11,0,13,0,15,0,14,0	;[bx], [bp], [di], [si]
			db 15,13,14,13,15,11,14,11	;[bp+di],[bp+si],[bx+di],[bx+si]

aam_args	db 'a',CR

;--- Equates for parsed arguments, stored in OPRND.flags

ARG_DEREF		equ 1	;non-immediate memory reference
ARG_MODRM		equ 2	;if we've computed the MOD R/M byte
ARG_JUSTREG		equ 4	;a solo register
ARG_WEIRDREG	equ 8	;if it's a segment register or CR, etc.
ARG_IMMED		equ 10h	;if it's just a number
ARG_FARADDR		equ 20h	;if it's of the form xxxx:yyyyyyyy

;--- For each operand type in the following table, the first byte is
;--- the bits, at least one of which must be present; the second is the
;--- bits all of which must be absent.
;--- the items in bittab must be ordered similiar to asm_jmp1 and dis_jmp1.

bittab label byte
	db ARG_IMMED			;OP_IMM
	db ARG_DEREF+ARG_JUSTREG;OP_RM
	db ARG_DEREF			;OP_M
	db ARG_JUSTREG			;OP_R_MOD
	db ARG_DEREF			;OP_MOFFS
	db ARG_JUSTREG			;OP_R
	db ARG_JUSTREG			;OP_R_ADD
	db ARG_JUSTREG			;OP_AX

	db ARG_DEREF			; 0 OP_M64
	db ARG_DEREF			; 1 OP_MFLOAT
	db ARG_DEREF			; 2 OP_MDOUBLE
	db ARG_DEREF			; 3 OP_M80
	db ARG_DEREF			; 4 OP_MXX
	db ARG_DEREF			; 5 OP_FARMEM
	db ARG_FARADDR			; 6 OP_FARIMM
	db ARG_IMMED			; 7 OP_REL8
	db ARG_IMMED			; 8 OP_REL1632
	db ARG_WEIRDREG			; 9 OP_1CHK
	db ARG_WEIRDREG			;10 OP_STI
	db ARG_WEIRDREG			;11 OP_CR
	db ARG_WEIRDREG			;12 OP_DR
	db ARG_WEIRDREG			;13 OP_TR
	db ARG_WEIRDREG			;14 OP_SEGREG
	db ARG_IMMED			;15 OP_IMMS8
	db ARG_IMMED			;16 OP_IMM8
	db ARG_WEIRDREG			;17 OP_MMX
	db 0ffh					;18 OP_SHOSIZ

	db ARG_IMMED			;OP_1
	db ARG_IMMED			;OP_3
	db ARG_JUSTREG			;OP_DX
	db ARG_JUSTREG			;OP_CL
	db ARG_WEIRDREG			;OP_ST
	db ARG_WEIRDREG			;OP_CS
	db ARG_WEIRDREG			;OP_DS
	db ARG_WEIRDREG			;OP_ES
	db ARG_WEIRDREG			;OP_FS
	db ARG_WEIRDREG			;OP_GS
	db ARG_WEIRDREG			;OP_SS

;--- special ops DX, CL, ST, CS, DS, ES, FS, GS, SS
;--- entry required if ao48 is set above

asm_regnum label byte
	db REG_DX, REG_CL, REG_ST, REG_CS, REG_DS, REG_ES, REG_FS, REG_GS, REG_SS

;--- size qualifier
;--- 1  BY=BYTE ptr
;--- 2  WO=WORD ptr
;--- 3  unused
;--- 4  DW=DWORD ptr
;--- 5  QW=QWORD ptr
;--- 6  FL=FLOAT ptr (REAL4)
;--- 7  DO=DOUBLE ptr (REAL8)
;--- 8  TB=TBYTE ptr (REAL10)
;--- 9  SH=SHORT 
;--- 10 LO=LONG
;--- 11 NE=NEAR ptr
;--- 12 FA=FAR ptr

SIZ_NONE	equ 0
SIZ_BYTE	equ 1
SIZ_WORD	equ 2
SIZ_DWORD	equ 4
SIZ_QWORD	equ 5
SIZ_FLOAT	equ 6
SIZ_DOUBLE	equ 7
SIZ_TBYTE	equ 8
SIZ_SHORT	equ 9
SIZ_LONG	equ 10
SIZ_NEAR	equ 11
SIZ_FAR		equ 12

sizetcnam	db 'BY','WO','WO','DW','QW','FL','DO','TB','SH','LO','NE','FA'

;--- sizes for OP_M64, OP_MFLOAT, OP_MDOUBLE, OP_M80, OP_MXX, OP_FARMEM

asm_siznum	db SIZ_QWORD, SIZ_FLOAT, SIZ_DOUBLE, SIZ_TBYTE
			db -1, SIZ_FAR			;-1 = none

CONST ends

;--- write byte in AL to BX/[E]DX, then increment [E]DX

writeasm proc
	call writemem
	sizeprfX	;inc edx
	inc dx
	ret
writeasm endp

;--- write CX bytes from DS:SI to BX:[E]DX

writeasmn proc
	jcxz nowrite
@@:
	lodsb
	call writeasm
	loop @B
nowrite:
	ret
writeasmn endp

a_cmd proc
	mov [errret],offset aa01
	cmp al,CR
	je aa01			;if end of line
	mov bx,[regs.rCS]	;default segment to use
aa00a:
	call getaddr	;get address into bx:(e)dx
	call chkeol		;expect end of line here
	sizeprfX		;mov [a_addr+0],edx
	mov [a_addr+0],dx	;save the address
	mov word ptr [a_addr+4],bx

;--- Begin loop over input lines.

aa01:
	mov sp,[top_sp]	;restore the stack (this implies no "ret")
	mov di,offset line_out
	mov ax,[a_addr+4]
	call hexword
	mov al,':'
	stosb
	mov [asm_mn_flags],0
	mov bp,offset hexword
if ?PM
	mov bx,[a_addr+4]
	call getselattr
	mov [bCSAttr],al
	jz @F
	mov bp,offset hexdword
;	mov [asm_mn_flags],AMF_D32
	db 66h	;mov eax,[a_addr]
@@:
endif
	mov ax,[a_addr+0]
	call bp
	mov al,' '
	stosb
	call getline00
	cmp al,CR
	je aa_exit	;if done
	cmp al,';'
	je aa01		;if comment
	mov word ptr [aa_saved_prefix],0 ;clear aa_saved_prefix and aa_seg_pre

;--- Get mnemonic and look it up.

aa02:
	mov di,offset line_out	;return here after LOCK/REP/SEG prefix
	push si			;save position of mnemonic
aa03:
	cmp al,'a'
	jb @F			;if not lower case letter
	cmp al,'z'
	ja @F
	and al,TOUPPER	;convert to upper case
@@:
	stosb
	lodsb
	cmp al,CR
	je @F			;if end of mnemonic
	cmp al,';'
	je @F
	cmp al,' '
	je @F
	cmp al,':'
	je @F
	cmp al,TAB
	jne aa03
@@:
	or byte ptr [di-1],80h	;set highest bit of last char of mnemonic
	call skipwh0	;skip to next field
	dec si
	push si			;save position in input line
;	mov al,0
;	stosb

;--- now search mnemonic in list

	mov si,offset mnlist
aa06:               ;<--- next mnemonic
	mov bx,si
	add si,2		;skip the 'asmtab' offset 
	mov cx,si
@@:
	lodsb			;skip to end of string
	and al,al
	jns @B			;if not end of string
	xchg cx,si
	push cx
	sub cx,si		;size of opcode in mnlist
	mov di,offset line_out
	repe cmpsb
	pop si
	je aa14			;if found it
	cmp si,offset end_mnlist
	jc aa06			;next mnemonic
	pop si			;skip position in input line
aa13a:
	pop si			;skip position of mnemonic
aa13b:
	jmp cmd_error	;complain
aa_exit:
	jmp cmdloop		;done with this command

;--- We found the mnemonic.

aa14:
	mov si,[bx]		;get the offset into asmtab
	add si,offset asmtab

;   Now si points to the spot in asmtab corresponding to this mnemonic.
;   The format of the assembler table is as follows.
;   First, there is optionally one of the following bytes:
;       ASM_DB      db mnemonic
;       ASM_DW      dw mnemonic
;       ASM_DD      dd mnemonic
;       ASM_WAIT    the mnemonic should start with a wait
;                   instruction.
;       ASM_D32     This is a 32 bit instruction variant.
;       ASM_D16     This is a 16 bit instruction variant.
;       ASM_AAX     Special for AAM and AAD instructions:
;                   put 0ah in for a default operand.
;       ASM_SEG     This is a segment prefix.
;       ASM_LOCKREP This is a LOCK or REP... prefix.
;
;   Then, in most cases, this is followed by one or more of the following
;   sequences, indicating an instruction variant.
;   ASM_LOCKABLE (optional) indicates that this instruction can
;                follow a LOCK prefix.
;   ASM_MACHx    (optional) indicates the first machine on which this
;                instruction appeared.
;   [word]       This is a 16-bit integer, most significant byte
;                first, giving ASMMOD * a + b, where b is an
;                index into the array opindex (indicating the
;                key, or type of operand list), and a is as
;                follows:
;                0-255     The (one-byte) instruction.
;                256-511   The lower 8 bits give the second byte of
;                          a two-byte instruction beginning with 0fh.
;                512-575   Bits 2-0 say which floating point instruction
;                          this is (0d8h-0dfh), and 5-3 give the /r
;                          field.
;                576-...   (a-576)/8 is the index in the array agroups
;                          (which gives the real value of a), and the
;                          low-order 3 bits gives the /r field.
;
;   [byte]       This gives the second byte of a floating
;                instruction if 0d8h <= a <= 0dfh.
;
;   Following these is an ASM_END byte.
;
;   Exceptions:
;       ASM_SEG and ASM_LOCKREP are followed by just one byte, the
;       prefix byte.
;       ASM_DB, ASM_DW, and ASM_DD don't need to be followed by
;       anything.

ASM_END		equ 0ffh
ASM_DB		equ 0feh
ASM_DW		equ 0fdh
ASM_DD		equ 0fch
ASM_ORG		equ 0fbh
ASM_WAIT	equ 0fah
ASM_D32		equ 0f9h
ASM_D16		equ 0f8h
ASM_AAX		equ 0f7h
ASM_SEG		equ 0f6h
ASM_LOCKREP	equ 0f5h
ASM_LOCKABLE equ 0f4h
ASM_MACH6	equ 0f3h
ASM_MACH5	equ 0f2h
ASM_MACH4	equ 0f1h
ASM_MACH3	equ 0f0h
ASM_MACH2	equ 0efh
ASM_MACH1	equ 0eeh
ASM_MACH0	equ 0edh

	cmp byte ptr [si],ASM_LOCKREP	;check for mnemonic flag byte
	jb aa15						;if none
	lodsb						;get the prefix
	sub al,ASM_LOCKREP			;convert to 0-9
	je aa18						;if LOCK or REP...
	cbw
	dec ax
	jz aa17						;if segment prefix (ASM_SEG)
	dec ax
	jz aa16						;if aad or aam (ASM_AAX)
	dec ax
	jz aa15_1					;if ASM_D16
	cmp al,3
	jae aa20					;if ASM_ORG or ASM_DD or ASM_DW or ASM_DB
	or [asm_mn_flags],al		;save AMF_D32 or AMF_WAIT (1 or 2)
aa15:
	jmp ab01					;now process the arguments
aa15_1:
	or [asm_mn_flags],AMF_D16
	inc si						;skip the ASM_D32 byte
	jmp ab01					;now process the arguments

aa16:
	jmp ab00

;--- segment prefix

aa17:
	lodsb			;get prefix value
	mov [aa_seg_pre],al
	mov cl,al
	or [asm_mn_flags],AMF_MSEG
	pop si			;get position in input line
	pop ax			;skip
	lodsb
	cmp al,':'
	jne aa13b
	call skipwhite
	cmp al,CR
	je @F
	cmp al,';'
	jne aa13b
@@:
	mov di,offset line_out
	mov al,cl
	stosb
	jmp aa27		;back for more

;--- LOCK or REP prefix

aa18:
	lodsb			;get prefix value
	xchg al,[aa_saved_prefix]
	cmp al,0
	jnz aa13a		;if there already was a saved prefix
	pop si
	pop ax
	lodsb
	cmp al,CR
	je @F			;if end of line
	cmp al,';'
	je @F			;if end of line (comment)
	jmp aa02		;back for more
@@:
	mov al,[aa_saved_prefix]	;just a prefix, nothing else
	mov di,offset line_out
	stosb
	jmp aa27

;--- Pseudo ops (org or db/dw/dd).

aa20:
	cmp word ptr [aa_saved_prefix],0
	jnz aa13a		;if there was a prefix or a segment: error
	pop si			;get position in input line
	sub al,3		;AX=0 if org, 1 if dd, 2 if dw, 3 if db.
	jnz aa20m		;if not ORG

;--- Process ORG pseudo op.

	call skipwhite
	cmp al,CR
	je @F				;if nothing
	mov bx,[a_addr+4]	;default segment
	jmp aa00a			;go to top
@@:
	jmp aa01			;get next line

;--- Data instructions (DB/DW/DD).

aa20m:
	mov di,offset line_out	;put the bytes here when we get them
	xchg ax,bx				;mov bx,ax
	shl bx,1
	mov bp,[bx+aadbsto-2]	;get address of storage routine
	call skipwhite
	cmp al,CR
	je aa27				;if end of line

aa21:					;<--- loop
	cmp al,'"'
	je aa22				;if string
	cmp al,"'"
	je aa22				;if string
	call aageti			;get a numerical value into dx:bx, size into cl
	cmp cl,cs:[bp-1]	;compare with size
	jg aa24				;if overflow
	xchg ax,bx
	call bp				;store value in AL/AX/DX:AX
	cmp di,offset real_end
	ja aa24				;if output line overflow
	xchg ax,bx
	jmp aa26			;done with this one

aa22:
	mov ah,al
aa23:
	lodsb
	cmp al,CR
	je aa24			;if end of line
	cmp al,ah
	je aa25			;if end of string
	stosb
	cmp di,offset real_end
	jbe aa23		;if output line not overflowing
aa24:
	jmp aa13b		;error
aa25:
	lodsb
aa26:
	call skipcomm0
	cmp al,CR
	jne aa21		;if not end of line

;--- End of line.  Copy it to debuggee's memory

aa27:
	mov si,offset line_out
	mov bx,[a_addr+4]
	sizeprfX	;mov edx, [a_addr+0]
	mov dx,[a_addr+0]
	mov cx,di
	sub cx,si
	call writeasmn
	sizeprfX	;mov [a_addr+0],edx
	mov [a_addr+0],dx
	jmp aa01

CONST segment
;--- table for routine to store a number ( index dd=1,dw=2,db=3 )
aadbsto dw sto_dd,sto_dw,sto_db
CONST ends

;--- Routines to store a byte/word/dword.

	db 4            ;size to store
sto_dd:
	stosw			;store a dword value
	xchg ax,dx
	stosw
	xchg ax,dx
	ret
	db 2            ;size to store
sto_dw:
	stosw			;store a word value
	ret
	db 1            ;size to store
sto_db:
	stosb			;store a byte value
	ret

;   Here we process the AAD and AAM instructions.  They are special
;   in that they may take a one-byte argument, or none (in which case
;   the argument defaults to 0ah = ten).

ab00:
	mov [mneminfo],si	;save this address
	pop si
	lodsb
	cmp al,CR
	je ab00a		;if end of line
	cmp al,';'
	jne ab01b		;if not end of line
ab00a:
	mov si,offset aam_args	;fake a 0ah argument
	jmp ab01a

;--- Process normal instructions.

;   First we parse each argument into a 12-byte data block (OPRND), stored
;   consecutively at line_out, line_out+12, etc.
;   This is stored as follows.

;   [di]    Flags (ARG_DEREF, etc.)
;   [di+1]  Unused
;   [di+2]  Size argument, if any (1=byte, 2=word, 3=(unused), 4=dword,
;       5=qword, 6=float, 7=double, 8=tbyte, 9=short, 10=long, 11=near,
;       12=far), see SIZ_xxx and sizetcnam
;   [di+3]  Size of MOD R/M displacement
;   [di+4]  First register, or MOD R/M byte, or num of additional bytes
;   [di+5]  Second register or index register or SIB byte
;   [di+6]  Index factor
;   [di+7]  Sizes of numbers are or-ed here
;   [di+8]  (dword) number

;   For arguments of the form xxxx:yyyyyyyy, xxxx is stored in <num2>,
;   and yyyyyyyy in <num>.  The number of bytes in yyyyyyyy is stored in
;   opaddr, 2 is stored in <numadd>, and di is stored in xxaddr.

OPRND struc
flags	db ?	;+0
		db ?   
sizearg	db ?	;+2
sizedis	db ?	;+3
union
reg1	db ?	;+4
numadd	db ?	;+4 (additional bytes, stored at num2 (up to 4)
ends
union
struct
reg2	db ?	;+5
index	db ?	;+6
ends
num2	dw ?	;+5
ends
orednum	db ?	;+7
num		dd ?	;+8
OPRND ends

ab01:
	mov [mneminfo],si	;save this address
	pop si				;get position in line
ab01a:
	lodsb
ab01b:
	mov di,offset line_out

;--- Begin loop over operands.

ab02:               ;<--- next operand
	cmp al,CR
	je ab03			;if end of line
	cmp al,';'
	jne ab04		;if not end of line
ab03:
	jmp ab99		;to next phase

ab04:
	push di			;clear out the current OPRND storage area
	mov cx,sizeof OPRND / 2
	xor ax,ax
	rep stosw
	pop di

;--- Small loop over "BYTE PTR" and segment prefixes.

ab05:
	dec si
	mov ax,[si]
	and ax,TOUPPER_W
	cmp [di].OPRND.sizearg,SIZ_NONE
	jne ab07		;if already have a size qualifier ("BYTE PTR",...)
	push di
	mov di,offset sizetcnam
	mov cx,sizeof sizetcnam / 2
	repne scasw
	pop di
	jne ab07		;if not found
	or cx,cx
	jnz @F			;if not 'FA'
	mov al,[si+2]
	and al,TOUPPER
	cmp al,'R'
	jne ab09		;if not 'FAR' (could be hexadecimal)
@@:
	sub cl,sizeof sizetcnam / 2
	neg cl			;convert to 1, ..., 12
	mov [di].OPRND.sizearg,cl
	call skipalpha	;go to next token
	mov ah,[si]
	and ax,TOUPPER_W
	cmp ax,'TP'
	jne ab05		;if not 'PTR'
	call skipalpha	;go to next token
	jmp ab05

ab07:
	cmp [aa_seg_pre],0
	jne ab09		;if we already have a segment prefix
	push di
	mov di,offset segrgnam
	mov cx,N_SEGREGS
	repne scasw
	pop di
	jne ab09		;if not found
	push si			;save si in case there's no colon
	lodsw
	call skipwhite
	cmp al,':'
	jne ab08		;if not followed by ':'
	pop ax			;discard saved si
	call skipwhite	;skip it
	mov bx,offset prefixlist + 5
	sub bx,cx
	mov al,[bx]		;look up the prefix byte
	mov [aa_seg_pre],al	;save it away
	jmp ab05
ab08:
	pop si

;--- Begin parsing main part of argument.

;--- first check registers

ab09:
	push di			;check for solo registers
	mov di,offset rgnam816
	mov cx,N_ALLREGS;8+16bit regs, segment regs, special regs
	call aagetreg
	pop di
	jc ab14			;if not a register
	or [di].OPRND.flags, ARG_JUSTREG
	mov [di].OPRND.reg1,bl	;save register number
	cmp bl,24		;0-23 = AL-DH, AX-DI, EAX-EDI
	jae @F			;if it's not a normal register
	xchg ax,bx		;mov al,bl
	mov cl,3
	shr al,cl		;al = size:  0 -> byte, 1 -> word, 2 -> dword
	add al,-2
	adc al,3		;convert to 1, 2, 4 (respectively)
	jmp ab13
@@:
	xor [di].OPRND.flags, ARG_JUSTREG + ARG_WEIRDREG
	mov al,SIZ_WORD	;register size
	cmp bl,REG_ST	;24-29=segment registers
	ja ab11			;if it's MM, CR, DR or TR
	je @F			;if it's ST
	cmp bl,28
	jb ab13			;if it's a normal segment register (DS,ES,SS,CS)
	or [asm_mn_flags],AMF_FSGS	;flag it
	jmp ab13
@@:
	cmp byte ptr [si],'('
	jne ab12		;if just plain ST
	lodsb
	lodsb
	sub al,'0'
	cmp al,7
	ja ab10			;if not 0..7
	mov [di].OPRND.reg2,al	;save the number
	lodsb
	cmp al,')'
	je ab12			;if not error
ab10:
	jmp aa13b		;error

;--- other registers 31-34 (MM, CR, DR, TR)

ab11:
	lodsb
	sub al,'0'
	cmp al,7
	ja ab10			;if error
	mov [di].OPRND.reg2,al	;save the number
	mov al,SIZ_DWORD;register size
	cmp bl,REG_MM
	jne ab13		;if not MM register
	or [di].OPRND.flags, ARG_JUSTREG
	mov al,SIZ_QWORD
	jmp ab13
ab12:
	mov al,0		;size for ST regs
ab13:
	cmp al,[di].OPRND.sizearg	;compare with stated size
	je @F			;if same
	xchg al,[di].OPRND.sizearg
	cmp al,0
	jne ab10		;if wrong size given - error
@@:
	jmp ab44		;done with this operand

;--- It's not a register reference.  Try for a number.

ab14:
	lodsb
	call aaifnum
	jc ab17			;it's not a number
	call aageti		;get the number
	mov [di].OPRND.orednum,cl
	mov word ptr [di].OPRND.num+0,bx
	mov word ptr [di].OPRND.num+2,dx
	call skipwh0
	cmp cl,2
	jg ab17			;if we can't have a colon here
	cmp al,':'
	jne ab17		;if not xxxx:yyyy
	call skipwhite
	call aageti
	mov cx,word ptr [di].OPRND.num+0
	mov [di].OPRND.num2,cx
	mov word ptr [di].OPRND.num+0,bx
	mov word ptr [di].OPRND.num+2,dx
	or [di].OPRND.flags, ARG_FARADDR
	jmp ab43		;done with this operand

;--- Check for [...].

ab15:
	jmp ab30		;do post-processing

ab16:
	call skipwhite
ab17:
	cmp al,'['		;begin loop over sets of []
	jne ab15		;if not [
	or [di].OPRND.flags, ARG_DEREF ;set the flag
ab18:
	call skipwhite
ab19:
	cmp al,']'		;begin loop within []
	je ab16			;if done

;--- Check for a register (within []).

	dec si
	push di
	mov di,offset rgnam16
	mov cx,N_REGS16
	call aagetreg
	pop di
	jc ab25			;if not a register
	cmp bl,16
	jae @F			;if 32-bit register
	add bl,8		;adjust 0..7 to 8..15
	jmp ab21
@@:
	cmp [di].OPRND.reg2, 0
	jnz ab21		;if we already have an index
	call skipwhite
	dec si
	cmp al,'*'
	jne ab21		;if not followed by '*'
	inc si
	mov [di].OPRND.reg2,bl	;save index register
	call skipwhite
	call aageti
	call aaconvindex
	jmp ab28		;ready for next part

ab21:
	cmp [di].OPRND.reg1,0
	jne @F			;if there's already a register
	mov [di].OPRND.reg1,bl
	jmp ab23
@@:
	cmp [di].OPRND.reg2, 0
	jne ab24		;if too many registers
	mov [di].OPRND.reg2,bl
ab23:
	call skipwhite
	jmp ab28		;ready for next part
ab24:
	jmp aa13b		;error

;--- Try for a number (within []).

ab25:
	lodsb
ab26:
	call aageti		;get a number (or flag an error)
	call skipwh0
	cmp al,'*'
	je ab27			;if it's an index factor
	or [di].OPRND.orednum,cl
	add word ptr [di].OPRND.num+0,bx
	adc word ptr [di].OPRND.num+2,dx
	jmp ab28		;next part ...

ab27:
	call aaconvindex
	call skipwhite
	dec si
	push di
	mov di,offset rgnam16
	xor cx,cx
	call aagetreg
	pop di
	jc ab24			;if error
	cmp [di].OPRND.reg2, 0
	jne ab24		;if there is already a register
	mov [di].OPRND.reg2, bl
	call skipwhite

;--- Ready for the next term within [].

ab28:
	cmp al,'-'
	je ab26			;if a (negative) number is next
	cmp al,'+'
	jne @F			;if no next term (presumably)
	jmp ab18
@@:
	jmp ab19		;back for more

;--- Post-processing for complicated arguments.

ab30:
	cmp word ptr [di].OPRND.reg1,0	;check both reg1+reg2
	jnz ab32		;if registers were given ( ==> create MOD R/M)
	cmp [di].OPRND.orednum,0
	jz ab31			;if nothing was given ( ==> error)
	cmp [di].OPRND.flags,0
	jnz ab30b		;if it was not immediate
	or [di].OPRND.flags,ARG_IMMED
ab30a:
	jmp ab43		;done with this argument
ab30b:
	or [asm_mn_flags],AMF_ADDR
	mov al,2		;size of the displacement
	test [di].OPRND.orednum,4
	jz @F			;if not 32-bit displacement
	inc ax
	inc ax
	or [asm_mn_flags],AMF_A32	;32-bit addressing
@@:
	mov [di].OPRND.sizedis,al	;save displacement size
	jmp ab30a		;done with this argument
ab31:
	jmp aa13b		;flag an error

;   Create the MOD R/M byte.
;   (For disp-only or register, this will be done later as needed.)

ab32:
	or [di].OPRND.flags, ARG_MODRM
	mov al,[di].OPRND.reg1
	or al,[di].OPRND.reg2
	test al,16
	jnz ab34		;if 32-bit addressing
	test [di].OPRND.orednum,4
	jnz ab34		;if 32-bit addressing
;	or [asm_mn_flags], AMF_ADDR | AMF_A32
	or [asm_mn_flags], AMF_ADDR
	mov ax,word ptr [di].OPRND.reg1	;get reg1+reg2
	cmp al,ah
	ja @F			;make sure al >= ah
	xchg al,ah
@@:
	push di
	mov di,offset modrmtab
	mov cx,8
	repne scasw
	pop di
	jne ab31		;if not among the possibilities
	mov bx,206h		;max disp = 2 bytes; 6 ==> (non-existent) [bp]
	jmp ab39		;done (just about)

;--- 32-bit addressing

ab34:
	or [asm_mn_flags],AMF_A32 + AMF_ADDR
	mov al,[di].OPRND.reg1
	or al,[di].OPRND.index
	jnz @F			;if we can't optimize [EXX*1] to [EXX]
	mov ax,word ptr [di].OPRND.reg1	;get reg1+reg2
	xchg al,ah
	mov word ptr [di].OPRND.reg1,ax
@@:
	mov bx,405h		;max disp = 4 bytes; 5 ==> (non-existent) [bp]
	cmp [di].OPRND.reg2,0
	jne @F			;if there's a SIB
	mov cl,[di].OPRND.reg1
	cmp cl,16
	jl ab31			;if wrong register type
	and cl,7
	cmp cl,4		;check for ESP
	jne ab39		;if not, then we're done (otherwise do SIB)
@@:
	or [asm_mn_flags],AMF_SIB	;form SIB
	mov ch,[di].OPRND.index		;get SS bits
	mov cl,3
	shl ch,cl				;shift them halfway into place
	mov al,[di].OPRND.reg2	;index register
	cmp al,20
	je ab31			;if ESP ( ==> error)
	cmp al,0
	jne @F			;if not zero
	mov al,20		;set it for index byte 4
@@:
	cmp al,16
	jl ab31			;if wrong register type
	and al,7
	or ch,al		;put it into the SIB
	shl ch,cl		;shift it into place
	inc cx			;R/M for SIB = 4
	mov al,[di].OPRND.reg1	;now get the low 3 bits
	cmp al,0
	jne @F			;if there was a first register
	or ch,5
	jmp ab42		;MOD = 0, disp is 4 bytes
@@:
	cmp al,16
	jl ab45			;if wrong register type
	and al,7		;first register
	or ch,al		;put it into the SIB
	cmp al,5
	je ab40			;if it's EBP, then we don't recognize disp=0
					;otherwise bl will be set to 0

;--- Find the size of the displacement.

ab39:
	cmp cl,bl
	je ab40			;if it's [(E)BP], then disp=0 is still 1 byte
	mov bl,0		;allow 0-byte disp

ab40:
	push cx
	mov al,byte ptr [di].OPRND.num+0
	mov cl,7
	sar al,cl
	pop cx
	mov ah,byte ptr [di].OPRND.num+1
	cmp al,ah
	jne @F			;if it's bigger than 1 byte
	cmp ax,word ptr [di].OPRND.num+2
	jne @F			;ditto
	mov bh,0		;no displacement
	or bl,byte ptr [di].OPRND.num+0
	jz ab42			;if disp = 0 and it's not (E)BP
	inc bh			;disp = 1 byte
	or cl,40h		;set MOD = 1
	jmp ab42		;done
@@:
	or cl,80h		;set MOD = 2
ab42:
	mov [di].OPRND.sizedis,bh	;store displacement size
	mov word ptr [di].OPRND.reg1, cx	;store MOD R/M and maybe SIB

;--- Finish up with the operand.

ab43:
	dec si
ab44:
	call skipwhite
	add di,sizeof OPRND
	cmp al,CR
	je ab99			;if end of line
	cmp al,';'
	je ab99			;if comment (ditto)
	cmp al,','
	jne ab45		;if not comma ( ==> error)
	cmp di,offset line_out+ 3 * sizeof OPRND
	jae ab45		;if too many operands
	call skipwhite
	jmp ab02

ab45:
	jmp aa13b		;error jump

ab99:
	mov [di].OPRND.flags,-1;end of parsing phase
	push si			;save the location of the end of the string

;   For the next phase, we match the parsed arguments with the set of
;   permissible argument lists for the opcode.  The first match wins.
;   Therefore the argument lists should be ordered such that the
;   cheaper ones come first.

;   There is a tricky issue regarding sizes of memory references.
;   Here are the rules:
;      1.   If a memory reference is given with a size, then it's OK.
;      2.   If a memory reference is given without a size, but some
;       other argument is a register (which implies a size),
;       then the memory reference inherits that size.
;           Exceptions: OP_CL does not imply a size
;                   OP_SHOSIZ
;      3.   If 1 and 2 do not apply, but this is the last possible argument
;       list, and if the argument list requires a particular size, then
;       that size is used.
;      4.   In all other cases, flag an error.

ac01:				;<--- next possible argument list
	xor ax,ax
	mov di,offset ai
	mov cx,sizeof ai/2
	rep stosw
	mov si,[mneminfo]	;address of the argument variant

;--- Sort out initial bytes.  At this point:
;--- si = address of argument variant

ac02:               ;<--- next byte of argument variant
	lodsb
	sub al,ASM_MACH0
	jb ac05			;if no more special bytes
	cmp al,ASM_LOCKABLE - ASM_MACH0
	je @F			;if ASM_LOCKABLE
	ja ac04			;if ASM_END ( ==> error)
	mov [ai.dismach],al;save machine type
	jmp ac02		;back for next byte
@@:
	or [ai.varflags],VAR_LOCKABLE
	jmp ac02		;back for next byte

ac04:
	jmp aa13a		;error

;--- Get and unpack the word.

ac05:
	dec si
	lodsw
	xchg al,ah			;put into little-endian order
	xor dx,dx
	mov bx,ASMMOD
	div bx				;ax = a_opcode; dx = index into opindex
	mov [a_opcode],ax	;save ax
	mov [a_opcode2],ax	;save the second copy
	cmp ax,0dfh
	ja @F				;if not coprocessor instruction
	cmp al,0d8h
	jb @F				;ditto
	or [ai.dmflags],DM_COPR;flag it as an x87 instruction
	mov ah,al			;ah = low order byte of opcode
	lodsb				;get extra byte
	mov [ai.regmem],al		;save it in regmem
	mov [a_opcode2],ax	;save this for obsolete-instruction detection
	or [ai.varflags],VAR_MODRM	;flag its presence
@@:
	mov [mneminfo],si	;save si back again
	mov si,dx
	mov bl,[opindex+si]
	lea si,[oplists+bx]		;si = the address of our operand list
	mov di,offset line_out	;di = array of OPRNDs

;--- Begin loop over operands.

ac06:               ;<--- next operand
	lodsb			;get next operand byte
	cmp al,0
	je ac10			;if end of list
	cmp [di].OPRND.flags,-1
	je ac01			;if too few operands were given
	cmp al,OP_SIZE
	jb @F			;if no size needed
;	mov ah,0
;	mov cl,4
;	shl ax,cl		;move bits 4-7 (size) to ah (OP_1632=5,OP_8=6,OP_16=7,...)
;	shr al,cl		;move bits 0-3 back
	db 0d4h,10h		;=aam 10h (AX=00XY -> AX=0X0Y)
	mov [ai.reqsize],ah	;save size away
	jmp ac08
@@:					;AL = OP_M64 - ...
	add al,ASM_OPOFF - OP_M64	;adjust for the start entries im asm_jmp1
ac08:
	cbw
	xchg ax,bx		;now bx contains the offset
	mov cx,[asm_jmp1+bx] ;subroutine address
	shr bx,1
	mov al,[bittab+bx]
	test al,[di].OPRND.flags
	jz ac09			;if no required bits are present
	call cx			;call its specific routine
	cmp word ptr [si-1],(OP_1632+OP_R)*256+(OP_1632+OP_R_MOD)
	je ac06			;(hack) for IMUL instruction
	add di,sizeof OPRND	;next operand
	jmp ac06		;back for more

ac09:
	jmp ac01		;back to next possibility

;--- End of operand list.

ac10:
	cmp [di].OPRND.flags,-1
	jne ac09		;if too many operands were given

;--- Final check on sizes

	mov al,[ai.varflags]
	test al,VAR_SIZ_NEED
	jz ac12			;if no size needed
	test al,VAR_SIZ_GIVN
	jnz ac12		;if a size was given
	test al,VAR_SIZ_FORCD
	jz ac09			;if the size was not forced ( ==> reject)
	mov si,[mneminfo]
	cmp byte ptr [si],ASM_END
	je ac12			;if this is the last one
ac11:
	jmp aa13a		;it was not ==> error (not a retry)

;--- Check other prefixes.

ac12:
	mov al,[aa_saved_prefix]
	cmp al,0
	jz ac14			;if no saved prefixes to check
	cmp al,0f0h
	jne @F			;if it's a rep prefix
	test [ai.varflags],VAR_LOCKABLE
	jz ac11			;if this variant is not lockable - error
	jmp ac14		;done
@@:
	mov ax,[a_opcode]	;check if opcode is OK for rep{,z,nz}
	and al,not 1		;clear low order bit (MOVSW -> MOVSB)
	cmp ax,0ffh
	ja ac11				;if it's not a 1 byte instruction - error
	mov di,offset replist	;list of instructions that go with rep
	mov cx,N_REPALL			;scan all (REP + REPxx)
	repne scasb
	jnz ac11			;if it's not among them - error

ac14:
	test [asm_mn_flags],AMF_MSEG
	jz @F				;if no segment prefix before mnemonic
	mov ax,[a_opcode]	;check if opcode allows this
	cmp ax,0ffh
	ja ac11				;if it's not a 1 byte instruction - error
	mov di,offset prfxtab
	mov cx,P_LEN
	repne scasb
	jnz ac11			;if it's not in the list - error
@@:
	mov bx,[ai.immaddr]
	or bx,bx
	jz ac16			;if no immediate data
	mov al,[ai.opsize]
	neg al
	shl al,1
	test al,[bx+7]
	jnz ac11		;if the immediate data was too big - error

;   Put the instruction together
;   (maybe is this why they call it an assembler)

;   First, the prefixes (including preceding WAIT instruction)

ac16:
	sizeprfX	;mov edx,[a_addr]
	mov dx,[a_addr+0]
	mov bx,[a_addr+4]
	test [asm_mn_flags],AMF_WAIT
	jz @F			;if no wait instruction beforehand
	mov al,9bh
	call writeasm
@@:
	mov al,[aa_saved_prefix]
	cmp al,0
	jz @F			;if no LOCK or REP prefix
	call writeasm
@@:

;--- a 67h address size prefix is needed
;--- 1. for CS32: if AMF_ADDR=1 and AMF_A32=1
;--- 2. for CS16: if AMF_ADDR=1 and AMF_A32=0

	mov al,[asm_mn_flags]
	test al,AMF_ADDR
	jz @F
	and al,AMF_A32
if ?PM
	mov ah,[bCSAttr]
	and ah,40h
	or al,ah
endif
	and al,AMF_A32 + 40h
	jz @F
	cmp al,AMF_A32 + 40h
	jz @F
	mov al,67h
	call writeasm
@@:

;--- a 66h data size prefix is needed
;--- for CS16: if VAR_D32 == 1 or AMF_D32 == 1
;--- for CS32: if VAR_D16 == 1 or AMF_D16 == 1

	mov ah,[asm_mn_flags]
	mov al,[ai.varflags]
if ?PM
	test [bCSAttr],40h
	jz @F
	test al, VAR_D16
	jnz ac20_1
	test ah, AMF_D16
	jnz ac20_1
	jmp ac21
@@:
endif
	test al,VAR_D32
	jnz ac20_1
	test ah,AMF_D32
	jz ac21
ac20_1:
	mov al,66h
	call writeasm		;store operand-size prefix
ac21:
	mov al,[aa_seg_pre]
	cmp al,0
	jz @F			;if no segment prefix
	call writeasm
	cmp al,64h
	jb @F			;if not 64 or 65 (FS or GS)
	or [asm_mn_flags],AMF_FSGS	;flag it
@@:

;--- Now emit the instruction itself.

	mov ax,[a_opcode]
	mov di,ax
	sub di,240h
	jae @F			;if 576-...
	cmp ax,200h
	jb ac24			;if regular instruction
	or [ai.dmflags],DM_COPR	;flag it as an x87 instruction
	and al,038h		;get register part
	or [ai.regmem],al
	xchg ax,di		;mov ax,di (the low bits of di are good)
	and al,7
	or al,0d8h
	jmp ac25		;on to decoding the instruction
@@:
	mov cl,3		;one instruction of a group
	shr di,cl
	and al,7
	shl al,cl
	or [ai.regmem],al
	shl di,1
	mov ax,[agroups+di]	;get actual opcode

ac24:
	cmp ah,0
	jz ac25			;if no 0fh first
	push ax			;store a 0fh
	mov al,0fh
	call writeasm
	pop ax

ac25:
	or al,[ai.opcode_or]	;put additional bits into the op code
	call writeasm		;store the op code itself

;--- Now store the extra stuff that comes with the instruction.

	mov ax,word ptr [ai.regmem]
	test [ai.varflags],VAR_MODRM
	jz @F			;if no mod reg/mem
	push ax
	call writeasm
	pop ax
	test [asm_mn_flags],AMF_SIB
	jz @F			;if no SIB
	mov al,ah
	call writeasm	;store the MOD R/M and SIB, too
@@:

	mov di,[ai.rmaddr]
	or di,di
	jz @F			;if no offset associated with the R/M
	mov cl,[di].OPRND.sizedis
	mov ch,0
	lea si,[di].OPRND.num	;store the R/M offset (or memory offset)
	call writeasmn
@@:

;--- Now store immediate data

	mov di,[ai.immaddr]
	or di,di
	jz @F			;if no immediate data
	mov al,[ai.opsize]
	cbw
	xchg ax,cx		;mov cx,ax
	lea si,[di].OPRND.num
	call writeasmn
@@:

;--- Now store additional bytes (needed for, e.g., enter instruction)
;--- also for FAR memory address

	mov di,[ai.xxaddr]
	or di,di
	jz @F			;if no additional data
	lea si,[di].OPRND.numadd	;number of bytes (2 for FAR, size of segment)
	lodsb
	cbw
	xchg ax,cx		;mov cx,ax
	call writeasmn
@@:

;--- Done emitting. Update asm address offset.

	sizeprfX	;mov [a_addr],edx
	mov [a_addr],dx

;--- Compute machine type.

	cmp [ai.dismach],3
	jae ac31		;if we already know a 386 is needed
	test [asm_mn_flags], AMF_D32 or AMF_A32 or AMF_FSGS
	jnz ac30		;if 386
	test [ai.varflags],VAR_D32
	jz ac31			;if not 386
ac30:
	mov [ai.dismach],3
ac31:
	mov di,offset a_obstab	;obsolete instruction table
	mov cx,[a_opcode2]
	call showmach		;get machine message into si, length into cx
	jcxz ac33			;if no message

ac32:
	mov di,offset line_out
	rep movsb		;copy the line to line_out
	call putsline

ac33:
	jmp aa01		;back for the next input line

if 0
;--- This is debugging code.  It assumes that the original value
;--- of a_addr is on the top of the stack.

	pop si		;get orig. a_addr
	mov ax,[a_addr+4]
	mov [u_addr+0],si
	mov [u_addr+4],ax
	mov bx,[a_addr]
	sub bx,si
	mov di,offset line_out
	mov cx,10
	mov al,' '
	rep stosb
	mov ds,[a_addr+4]
@@:
	lodsb
	call hexbyte	;display the bytes generated
	dec bx
	jnz @B
	push ss
	pop ds
	call putsline
	call disasm1	;disassemble the new instruction
	jmp aa01		;back to next input line
endif

CONST segment

	align 2

;--- Jump table for operand types.
;--- order of entries in asm_jmp1 must match 
;--- the one in dis_jmp1 / dis_optab.

asm_jmp1 label word
	dw aop_imm,aop_rm,aop_m,aop_r_mod	;OP_IMM, OP_RM, OP_M, OP_R_MOD
	dw aop_moffs,aop_r,aop_r_add,aop_ax	;OP_MOFFS, OP_R, OP_R_ADD, OP_AX
ASM_OPOFF equ $ - asm_jmp1
;--- order must match the one in dis_optab
	dw ao17,ao17,ao17		;OP_M64, OP_MFLOAT, OP_MDOUBLE
	dw ao17,ao17,ao17		;OP_M80, OP_MXX, OP_FARMEM
	dw aop_farimm,aop_rel8,aop_rel1632;OP_FARIMM, OP_REL8, OP_REL1632
	dw ao29,aop_sti,aop_cr	;OP_1CHK, OP_STI, OP_CR
	dw ao34,ao35,ao39		;OP_DR, OP_TR, OP_SEGREG
	dw ao41,ao42,aop_mmx	;OP_IMMS8, OP_IMM8, OP_MMX
	dw ao44,ao46,ao47		;OP_SHOSIZ, OP_1, OP_3
	dw ao48,ao48,ao48		;OP_DX, OP_CL, OP_ST
	dw ao48,ao48,ao48		;OP_CS, OP_DS, OP_ES
	dw ao48,ao48,ao48		;OP_FS, OP_GS, OP_SS

CONST ends

;   Routines to check for specific operand types.
;   Upon success, the routine returns.
;   Upon failure, it pops the return address and jumps to ac01.
;   The routines must preserve si and di.

;--- OP_RM, OP_M, OP_R_MOD:  form MOD R/M byte.

aop_rm:
aop_m:
aop_r_mod:
	call ao90		;form reg/mem byte
	jmp ao07		;go to the size check

;--- OP_R:  register.

aop_r:
	mov al,[di].OPRND.reg1	;register number
	and al,7
	mov cl,3
	shl al,cl		;shift it into place
	or [ai.regmem],al	;put it into the reg/mem byte
	jmp ao07		;go to the size check

;--- OP_R_ADD:  register, added to the instruction.

aop_r_add:
	mov al,[di].OPRND.reg1
	and al,7
	mov [ai.opcode_or],al	;put it there
	jmp ao07		;go to the size check

;--- OP_IMM:  immediate data.

aop_imm:
	mov [ai.immaddr],di	;save the location of this
	jmp ao07		;go to the size check

;--- OP_MOFFS:  just the memory offset

aop_moffs:
	test [di].OPRND.flags,ARG_MODRM
	jnz ao11		;if MOD R/M byte ( ==> reject)
	mov [ai.rmaddr],di	;save the operand pointer
	jmp ao07		;go to the size check

;--- OP_AX:  check for AL/AX/EAX

aop_ax:
	test [di].OPRND.reg1,7
	jnz ao11		;if wrong register
	;jmp ao07		;go to the size check

;--- Size check

ao07:               ;<--- entry for OP_RM, OP_M, OP_R_MOD, OP_R, OP_R_ADD...
	or [ai.varflags],VAR_SIZ_NEED
	mov al,[ai.reqsize]
	sub al,5		;OP_1632 >> 4
	jl ao12			;if OP_ALL
	jz ao13			;if OP_1632
;--- OP_8=1, OP_16=2, OP_32=3, OP_64=4
	add al,-3
	adc al,3		;convert 3 --> 4 and 4 --> 5
ao08:               ;<--- entry for OP_M64 ... OP_FARMEM
	or [ai.varflags],VAR_SIZ_FORCD + VAR_SIZ_NEED
ao08_1:
	mov bl,[di].OPRND.sizearg
	or bl,bl
	jz @F			;if no size given
	or [ai.varflags],VAR_SIZ_GIVN
	cmp al,bl
	jne ao11		;if sizes conflict
@@:
	cmp al,[ai.opsize]
	je @F			;if sizes agree
	xchg al,[ai.opsize]
	cmp al,0
	jnz ao11		;if sizes disagree
	or [ai.varflags],VAR_SIZ_GIVN	;v1.18 added!!!
@@:
	ret

ao11:
	jmp ao50		;reject

;--- OP_ALL - Allow all sizes.

ao12:
	mov al,[di].OPRND.sizearg
	cmp al,SIZ_BYTE
	je ao15			;if byte
	jb ao14			;if unknown
	or [ai.opcode_or],1;set bit in instruction
	jmp ao14		;if size is 16 or 32

;--- OP_1632 - word or dword.

ao13:
	mov al,[di].OPRND.sizearg
ao14:
	cmp al,SIZ_NONE
	je ao16			;if still unknown
	cmp al,SIZ_WORD
	jne @F			;if word
	or [ai.varflags],VAR_D16
	jmp ao15
@@:
	cmp al,SIZ_DWORD
	jne ao11		;if not dword
	or [ai.varflags],VAR_D32
ao15:
	mov [ai.opsize],al
	or [ai.varflags],VAR_SIZ_GIVN
ao16:
	ret

;   OP_M64 - 64-bit memory reference.
;   OP_MFLOAT - single-precision floating point memory reference.
;   OP_MDOUBLE - double-precision floating point memory reference.
;   OP_M80 - 80-bit memory reference.
;   OP_MXX - memory reference, size unknown.
;   OP_FARMEM - far memory pointer

;--- bx contains byte index for bittab
ao17:
	call ao90		;form reg/mem byte
	mov al,[asm_siznum+bx-ASM_OPOFF/2]
	jmp ao08		;check size

;--- OP_FARIMM - far address contained in instruction

aop_farimm:
	mov al,2
if ?PM
	test [bCSAttr],40h
	jnz @F
endif
	cmp word ptr [di].OPRND.num+2,0
	jz ao22			;if 16 bit address
@@:
	or [ai.varflags],VAR_D32
	mov al,4
ao22:
	mov [di].OPRND.numadd,2	;2 additional bytes (segment part)
	mov [ai.immaddr],di
	mov [ai.opsize],al			;2/4, size of offset
ao22_1:
	mov [ai.xxaddr],di
	ret

;--- OP_REL8 - relative address
;--- Jcc, LOOPx, JxCXZ

aop_rel8:
	mov al,SIZ_SHORT
	call aasizchk	;check the size
	mov cx,2		;size of instruction
	mov al,[asm_mn_flags]

	test al,AMF_D32 or AMF_D16
	jz ao23_1		;if not JxCXZ, LOOPx
	test al,AMF_D32
	jz @F
	or al,AMF_A32	; JxCXZ and LOOPx need a 67h, not a 66h prefix
@@:
	and al,not (AMF_D32 or AMF_D16)
	or al, AMF_ADDR
	mov [asm_mn_flags],al
if ?PM
	mov ah,[bCSAttr]
	and ah,40h
else
	mov ah,0
endif
	and al,AMF_A32
	or al,ah
	jz ao23_1
	cmp al,AMF_A32+40h
	jz ao23_1
	inc cx        ;instruction size = 3
ao23_1:
	mov bx,[a_addr+0]
	add bx,cx
	mov cx,[a_addr+2];v1.22: handle HiWord(EIP) properly
	adc cx,0
	mov ax,word ptr [di].OPRND.num+0
	mov dx,word ptr [di].OPRND.num+2
;--- CX:BX holds E/IP (=src), DX:AX holds dst
	sub ax,bx
	sbb dx,cx
	mov byte ptr [di].OPRND.num2,al
	mov cl,7        ;range must be ffffff80 <= x <= 0000007f
	sar al,cl       ;1xxxxxxxb -> FF, 0xxxxxxxb -> 00
	cmp al,ah
	jne ao_err1		;if too big
	cmp ax,dx
	jne ao_err1		;if too big
	mov [di].OPRND.numadd,1	;save the length
	jmp ao22_1		;save it away

;--- OP_REL1632:  relative jump/call to a longer address.
;--- size of instruction is
;--- a) CS 16-bit:
;---  3 (xx xxxx, jmp/call) or
;---  4 (0F xx xxxx)
;---  6 (66 xx xxxxxxxx)
;---  7 (66 0F xx xxxxxxxx)
;---
;--- b) CS 32-bit:
;---  5 (xx xxxxxxxx, jmp/call) or
;---  6 (0F xx xxxxxxxx)

aop_rel1632:
	mov bx,[a_addr+0]
	mov cx,3
	mov dx,word ptr [di].OPRND.num+2
	mov al,[di].OPRND.sizearg
	cmp [a_opcode],100h	;is a 0F xx opcode?
	jb @F
	inc cx
@@:
	cmp al,SIZ_NONE
	je @F			;if no size given
	cmp al,SIZ_DWORD
	je ao27			;if size "dword"
	cmp al,SIZ_LONG
	jne ao_err1		;if not size "long"
@@:
if ?PM
	test [bCSAttr],40h
	jnz ao27
endif
	or dx,dx
	jnz ao_err1		;if operand is too big
	mov al,2        ;displacement size 2
	jmp ao28
ao27:
	mov al,4        ;displacement size 4
	or [ai.varflags],VAR_D32
	add cx,3		;add 3 to instr size (+2 for displ, +1 for 66h)
if ?PM
	test [bCSAttr],40h
	jz @F
	dec cx			;no 66h prefix byte in 32-bit code
@@:
endif
ao28:
	add bx,cx
	mov cx,[a_addr+2]
	adc cx,0
	mov [di].OPRND.numadd,al	;store size of displacement (2 or 4)
	mov ax,word ptr [di].OPRND.num+0
	sub ax,bx		;compute DX:AX - CX:BX
	sbb dx,cx
	mov [di].OPRND.num2,ax
	mov [di].OPRND.num2+2,dx
	mov [ai.xxaddr],di
	ret
ao_err1:
	jmp ao50		;reject

;--- OP_1CHK - The assembler can ignore this one.

ao29:
	pop ax			;discard return address
	jmp ac06		;next operand

;--- OP_STI - ST(I).

aop_sti:
	mov al,REG_ST	;code for ST
	mov bl,[di].OPRND.reg2
	jmp ao38		;to common code

;--- OP_MMX [previously was OP_ECX (used for LOOPx)]

aop_mmx:
	mov al,REG_MM
	jmp ao37		;to common code

;--- OP_CR

aop_cr:
	mov al,[di].OPRND.reg2	;get the index
	cmp al,4
	ja ao_err1		;if too big
	jne @F			;if not CR4
	mov [ai.dismach],5	;CR4 is new to the 586
@@:
	cmp al,1
	jne @F
	cmp [di+sizeof OPRND].OPRND.flags,-1
	jne ao_err1		;if another arg (can't mov CR1,xx)
@@:
	mov al,REG_CR	;code for CR
	jmp ao37		;to common code

;--- OP_DR

ao34:
	mov al,REG_DR	;code for DR
	jmp ao37		;to common code

;--- OP_TR

ao35:
	mov al,[di].OPRND.reg2	;get the index
	cmp al,3
	jb ao_err1		;if too small
	cmp al,6
	jae @F
	mov [ai.dismach],4	;TR3-5 are new to the 486
@@:
	mov al,REG_TR	;code for TR

;--- Common code for these weird registers.

ao37:
	mov bl,[di].OPRND.reg2
	mov cl,3
	shl bl,cl
ao38:
	or [ai.regmem],bl
	or [ai.varflags],VAR_MODRM
	cmp al,[di].OPRND.reg1	;check for the right numbered register
	je ao40			;if yes, then return
ao38a:
	jmp ao50		;reject

;--- OP_SEGREG

ao39:
	mov al,[di].OPRND.reg1
	sub al,24
	cmp al,6
	jae ao38a		;if not a segment register
	mov cl,3
	shl al,cl
	or [ai.regmem],al
;--- v1.26: don't force size for MOV sreg,mxx / MOV mxx, sreg
	or [ai.varflags], VAR_SIZ_GIVN
ao40:
	ret

;--- OP_IMMS8 - Sign-extended immediate byte (PUSH xx)

ao41:
	and [ai.varflags],not VAR_SIZ_NEED	;added for v1.09. Ok?
	mov ax,word ptr [di].OPRND.num+0
	mov cl,7
	sar al,cl
	jmp ao43		;common code

;--- OP_IMM8 - Immediate byte

ao42:
	mov ax,word ptr [di].OPRND.num+0
	mov al,0
ao43:
	cmp al,ah
	jne ao50		;if too big
	cmp ax,word ptr [di].OPRND.num+2
	jne ao50		;if too big
	mov al,SIZ_BYTE
	call aasizchk	;check that size == 0 or 1
	mov ah,byte ptr [di].OPRND.num+0
	mov word ptr [di].OPRND.numadd,ax	;store length (0/1) + the byte
	mov [ai.xxaddr],di
ao43r:
	ret

;--- OP_SHOSIZ - force the user to declare the size of the next operand

ao44:
	test [ai.varflags],VAR_SIZ_NEED
	jz ao45			;if no testing needs to be done
	test [ai.varflags],VAR_SIZ_GIVN
	jz ao50			;if size was given ( ==> reject)
ao45:
	and [ai.varflags],not VAR_SIZ_GIVN	;clear the flag
	cmp byte ptr [si],OP_IMM8
	je ao45a		;if OP_IMM8 is next, then don't set VAR_SIZ_NEED
	or [ai.varflags],VAR_SIZ_NEED
ao45a:
	mov byte ptr [ai.opsize],0
	pop ax			;discard return address
	jmp ac06		;next operand

;--- OP_1

ao46:
	cmp word ptr [di+7],101h	;check both size and value
	jmp ao49		;test it later

;--- OP_3

ao47:
	cmp word ptr [di+7],301h	;check both size and value
	jmp ao49		;test it later

;--- OP_DX, OP_CL, OP_ST, OP_ES, ..., OP_GS
;--- bx contains index for bittab

ao48:
	mov al,[asm_regnum+bx-(ASM_OPOFF + OP_DX - OP_M64)/2]
	cbw
	cmp ax,word ptr [di].OPRND.reg1

ao49:
	je ao51

;--- Reject this operand list.

ao50:
	pop ax			;discard return address
	jmp ac01		;go back to try the next alternative

ao51:
	ret

;--- AASIZCHK - Check that the size given is 0 or AL.

aasizchk:
	cmp [di].OPRND.sizearg,SIZ_NONE
	je ao51
	cmp [di].OPRND.sizearg,al
	je ao51
	pop ax		;discard return address
	jmp ao50

a_cmd endp

;--- Do reg/mem processing.
;--- in: DI->OPRND
;--- Uses AX

ao90 proc
	test [di].OPRND.flags, ARG_JUSTREG
	jnz ao92		;if just register
	test [di].OPRND.flags, ARG_MODRM
	jz @F			;if no precomputed MOD R/M byte
	mov ax,word ptr [di].OPRND.reg1	;get the precomputed bytes
	jmp ao93		;done
@@:
	mov al,6		;convert plain displacement to MOD R/M
	test [asm_mn_flags],AMF_A32
	jz ao93			;if 16 bit addressing
	dec ax
	jmp ao93		;done

ao92:
	mov al,[di].OPRND.reg1	;convert register to MOD R/M
if 1
	cmp al,REG_MM
	jnz @F
	mov al,[di].OPRND.reg2
@@:
endif
	and al,7		;get low 3 bits
	or al,0c0h

ao93:
	or word ptr [ai.regmem],ax	;store the MOD R/M and SIB
	or [ai.varflags],VAR_MODRM	;flag its presence
	mov [ai.rmaddr],di			;save a pointer
	ret						;done
ao90 endp

;   AAIFNUM - Determine if there's a number next.
;   Entry   AL First character of number
;           SI Address of next character of number
;   Exit    CY Clear if there's a number, set otherwise.
;   Uses    None.

aaifnum proc
	cmp al,'-'
	je aai2			;if minus sign (carry is clear)
	push ax
	sub al,'0'
	cmp al,10
	pop ax
	jb aai1			;if a digit
	push ax
	and al,TOUPPER
	sub al,'A'
	cmp al,6
	pop ax
aai1:
	cmc				;carry clear <==> it's a number
aai2:
	ret
aaifnum endp

;   AAGETI - Get a number from the input line.
;   Entry   AL First character of number
;           SI Address of next character of number
;   Exit    DX:BX Resulting number
;           CL 1 if it's a byte ptr, 2 if a word, 4 if a dword
;           AL Next character not in number
;           SI Address of next character after that
;   Uses    AH, CH

aageti proc
	cmp al,'-'
	je aag1			;if negative
	call aag4		;get the bare number
	mov cx,1		;set up cx
	or dx,dx
	jnz aag2		;if dword
	or bh,bh
	jnz aag3		;if word
	ret				;it's a byte

aag1:
	lodsb
	call aag4		;get the bare number
	mov cx,bx
	or cx,dx
	mov cx,1
	jz aag1a		;if -0
	not dx		;negate the answer
	neg bx
	cmc
	adc dx,0
	test dh,80h
	jz aag7			;if error
	cmp dx,-1
	jne aag2		;if dword
	test bh,80h
	jz aag2			;if dword
	cmp bh,-1
	jne aag3		;if word
	test bl,80h
	jz aag3			;if word
aag1a:
	ret				;it's a byte

aag2:
	inc cx		;return:  it's a dword
	inc cx
aag3:
	inc cx		;return:  it's a word
	ret

aag4:
	xor bx,bx		;get the basic integer
	xor dx,dx
	call getnyb
	jc aag7			;if not a hex digit
aag5:
	or bl,al		;add it to the number
	lodsb
	call getnyb
	jc aag1a		;if done
	test dh,0f0h
	jnz aag7		;if overflow
	mov cx,4
aag6:
	shl bx,1		;shift it by 4
	rcl dx,1
	loop aag6
	jmp aag5

aag7:
	jmp cmd_error	;error

aageti endp

;	AACONVINDEX - Convert results from AAGETI and store index value
;	Entry   DX:BX,CL As in exit from AAGETI
;	        DI Points to information record for this arg
;	Exit    SS bits stored in [di].OPRND.index
;	Uses    DL

aaconvindex proc
	cmp cl,1
	jne aacv1		;if the number is too large
	cmp bl,1
	je aacv2		;if 1
	inc dx
	cmp bl,2
	je aacv2		;if 2
	inc dx
	cmp bl,4
	je aacv2		;if 4
	inc dx
	cmp bl,8
	je aacv2		;if 8
aacv1:
	jmp cmd_error	;error

aacv2:
	mov [di].OPRND.index,dl	;save the value
	ret
aaconvindex endp

;   AAGETREG - Get register for the assembler.
;   Entry   DI Start of register table
;           CX Length of register table ( or 0 )
;           SI Address of first character in register name
;   Exit    NC if a register was found
;           SI Updated if a register was found
;           BX Register number, defined as in the table below.
;   Uses    AX, CX, DI

;   Exit value of BX:
;       DI = rgnam816, CX = 27  DI = rgnam16, CX = 8
;       ----------------------  --------------------
;       0  ..  7:  AL .. BH     0  ..  7:  AX .. DI
;       8  .. 15:  AX .. DI     16 .. 23:  EAX..EDI
;       16 .. 23:  EAX..EDI
;       24 .. 29:  ES .. GS
;       30 .. 34:  ST .. TR

aagetreg proc
	mov ax,[si]
	and ax,TOUPPER_W	;convert to upper case
	cmp al,'E'			;check for EAX, etc.
	jne aagr1			;if not
	push ax
	mov al,ah
	mov ah,[si+2]
	and ah,TOUPPER
	push di
	mov di,offset rgnam16
	push cx
	mov cx,N_REGS16
	repne scasw
	mov bx,cx
	pop cx
	pop di
	pop ax
	jne aagr1		;if no match
	inc si
	not bx
	add bl,8+16		;adjust BX
	jmp aagr2		;finish up

aagr1:
	mov bx,cx		;(if cx = 0, this is always reached with
	repne scasw		; ZF clear)
	jne aagr3		;if no match
	sub bx,cx
	dec bx
	cmp bl,16
	jb aagr2		;if AL .. BH or AX .. DI
	add bl,8
aagr2:
	inc si			;skip the register name
	inc si
	clc
	ret
aagr3:
	stc				;not found
	ret
aagetreg endp

;--- C command - compare bytes.

c_cmd proc
	call parsecm		;parse arguments (sets DS:e/si, ES:e/di, e/cx)
if ?PM
	cmp cs:[bAddr32],0
	jz $+3
	db 66h	;inc ecx
endif
	inc cx
cc1:			;<--- continue compare
	push ds
	push es
	push ss		;ds=DGROUP
	pop ds
	call dohack	;set debuggee's int 23/24
	pop es
	pop ds

if ?PM
	cmp cs:[bAddr32],0
	jz $+3
	db 67h	;repe cmpsb ds:[esi],es:[edi]
endif
	repe cmpsb
	lahf
if ?PM
	cmp cs:[bAddr32],0
	jz $+3
	db 67h	;mov dl,[esi-1]
endif
	mov dl,[si-1]	;save the possibly errant characters
if ?PM
	jz $+3
	db 67h	;mov dh,es:[edi-1]
endif
	mov dh,es:[di-1]
	push ds
	push es
	push ss
	pop ds
	call unhack	;set debugger's int 23/24
	pop es
	pop ds
	sahf
	jne @F
	jmp cc2		;if we're done
@@:
	push cx
	push es
	push ss
	pop es
	sizeprfX	;mov ebx,edi
	mov bx,di	;save [E]DI
	mov di,offset line_out
	mov ax,ds
	call hexword
	mov al,':'
	stosb
if ?PM
	mov bp,offset hexword
	sizeprf		;dec esi
	dec si
	sizeprf		;mov eax, esi
	mov ax,si
	sizeprf		;inc esi
	inc si
	cmp cs:[bAddr32],0
	jz @F
	mov bp,offset hexdword
@@:
	call bp
else
	lea ax,[si-1]
	call hexword
endif
	mov ax,'  '
	stosw
	mov al,dl
	call hexbyte
	mov ax,'  '
	stosw
	mov al,dh
	call hexbyte
	mov ax,'  '
	stosw
	pop ax
	push ax
	call hexword
	mov al,':'
	stosb
if ?PM
	sizeprf		;dec ebx
	dec bx
	sizeprf		;mov eax, ebx
	mov ax,bx
	sizeprf		;inc ebx
	inc bx
	call bp
else
	lea ax,[bx-1]
	call hexword
endif
	push ds
	push ss
	pop ds
	push bx
	call putsline
	pop di
	pop ds
	pop es
	pop cx
if ?PM
	cmp cs:[bAddr32],0
	jz $+3
	db 67h	;jecxz cc2
endif
	jcxz cc2
	jmp cc1		;if not done yet
cc2:
	push ss		;restore segment registers
	pop ds
	push ss
	pop es
	ret
c_cmd endp

if ?PM

CONST segment
descbase db ' base=???????? limit=???????? attr=????',0
CONST ends

descout proc
	.286
	call skipwhite
	call getword	;get word into DX
	mov bx,dx
	call skipcomm0
	mov dx,1
	cmp al,CR
	jz @F
	call getword
	call chkeol
	and dx,dx
	jnz @F
	inc dx
@@:
	mov si,dx		;save count
	call ispm
	jnz nextdesc
	mov si,offset nodesc
	call copystring
	jmp putsline
desc_done:
	ret
nextdesc:
	dec si
	js desc_done
	mov di,offset line_out
	mov ax,bx
	call hexword
	push si
	push di
	mov si,offset descbase
	call copystring
	pop di
	pop si
;	lar ax,bx
;	jnz skipdesc	;tell that this descriptor is invalid
	mov ax,6
	int 31h
	jc @F
	add di, 6
	mov ax,cx
	call hexword
	mov ax,dx
	call hexword
@@:
	sizeprf		;lsl eax,ebx
	lsl ax,bx
	jnz desc_out
	sizeprf		;lar edx,ebx
	lar dx,bx
	sizeprf		;shr edx,8
	shr dx,8
	mov di,offset line_out+25
	cmp [machine],3
	jb @F
	call hexdword
	jmp desc_o2
@@:
	call hexword
	mov ax,"  "
	stosw
	stosw
desc_o2:
	mov di,offset line_out+25+14
	mov ax,dx
	call hexword
desc_out:
	mov di,offset line_out+25+14+4
	push bx
	call putsline
	pop bx
	add bx,8
	jmp nextdesc
descout endp

;--- DI command

gateout proc
	call skipwhite
	call getbyte	;get byte into DL
	mov bx,dx
	call skipcomm0
	mov dx,1
	cmp al,CR
	jz @F
	call getbyte	;get byte into DL
	call chkeol
	and dx,dx
	jnz @F
	inc dx			;ensure that count is > 0
@@:
	call prephack
	mov si,dx		;save count
gateout_00: 		;<--- next int/exc
	call dohack		;set debuggee's int 23/24
	mov di,offset line_out
	mov al,bl
	call hexbyte
	mov al,' '
	stosb
	call ispm
	jz gaterm
	.286
	mov ax,204h
	cmp bl,20h
	adc bh,1
gateout_01:
	int 31h
	jc gatefailed
	mov ax,cx
	call hexword
	mov al,':'
	stosb
	cmp [dpmi32],0
	jz gate16
	.386
	shld eax,edx,16
	call hexword
	.8086
gate16:
	mov ax,dx
	call hexword
	mov al,' '
	stosb
	mov ax,0202h
	dec bh
	jnz gateout_01
gate_exit:
	call unhack	;set debugger's int 23/24
	push bx
	call putsline
	pop bx
	inc bx
	dec si
	jnz gateout_00
	ret
gaterm:
	mov cl,2
	push bx
	shl bx,cl
	push ds
	xor ax,ax
	mov ds,ax
	mov ax,[bx+2]
	mov dx,[bx+0]
	pop ds
	pop bx
	call hexword
	mov al,':'
	stosb
	mov bh,1
	jmp gate16
gatefailed:
	mov di,offset line_out
	mov si,offset gatewrong
	call copystring
	mov si,1
	jmp gate_exit
gateout endp
endif

	.8086

if MCB
mcbout proc
;	mov di,offset line_out
	mov ax,"SP"
	stosw
	mov ax,":P"
	stosw
	mov ax,[pspdbe]
	call hexword
	call putsline	;destroys cx,dx,bx

	mov si,[wMCB]
nextmcb:
	mov di,offset line_out
	push ds
	call setds2si
	mov ch,ds:[0000]
	mov bx,ds:[0001]	;owner psp
	mov dx,ds:[0003]
	mov ax,si
	call hexword	;segment address of MCB
	mov al,' '
	stosb
	mov al,ch
	call hexbyte	;'M' or 'Z'
	mov al,' '
	stosb
	mov ax,bx
	call hexword	;MCB owner
	mov al,' '
	stosb
	mov ax,dx
	call hexword	;MCB size in paragraphs
	mov al,' '
	stosb
	and bx,bx
	jz mcbisfree
	push si
	push cx
	push dx
	mov si,8
	mov cx,2 
	cmp bx,si		;is it a "system" MCB?
	jz nextmcbchar
	dec bx
	call setds2bx	;destroys cx if in pm
	mov cx,8
nextmcbchar:		;copy "name" of owner MCB
	lodsb
	stosb
	and al,al
	loopnz nextmcbchar
	pop dx
	pop cx
	pop si
mcbisfree:
	pop ds
	add si,dx
	jc mcbout_done
	inc si
	push cx
	call putsline	;destroys cx,dx,bx
	pop cx
	cmp ch,'Z'
	jz nextmcb
	cmp ch,'M'
	jz nextmcb
mcbout_done:
	ret

setds2si:
	mov bx,si
setds2bx:
if ?PM
	call ispm
	jz sd2s_ex
	mov dx,bx
	call setrmsegm
sd2s_ex:
endif
	mov ds,bx
	ret
mcbout endp
endif

;--- DX command. Display extended memory
;--- works for 80386+ only.

if DXSUPP

if DXUNREAL

    align 4
gdt label qword
	dw -1,0,9200h,0CFh	; 32-bit flat data descriptor
	dw -1,0,9200h,0		; 16-bit data descriptor
GDTR label fword
	dw 3*8-1
	dd 0

SEL_FLAT equ 8
SEL_DATA16 equ 16

	.386p
;--- set/reset unreal mode
setdspm:
	mov ax,cs
	movzx eax,ax
	shl eax,4
	add eax,offset gdt-8
	mov dword ptr cs:[GDTR+2],eax
	lgdt cs:[GDTR]
	mov eax,cr0
	inc ax
	mov cr0,eax
	jmp @F
@@:
	mov ds,cx
	dec ax
	mov cr0,eax
	jmp @F
@@:
	ret

	.386
;--- exception 0D: no need to check if it's a real exception,
;--- since interrupts were disabled.
int0d:
	push ds
	push eax
	push cx
	mov cx,SEL_FLAT
	call setdspm
	pop cx
	pop eax
	mov al,0
	pop ds
	iret
endif

	.386

extmem proc
	mov dx,word ptr [x_addr+0]
	mov bx,word ptr [x_addr+2]
	call skipwhite
	cmp al,CR
	jz @F
	call getdword	;get linear address into bx:dx
	call chkeol		;expect end of line here
@@:
	mov [lastcmd],offset extmem
	push bx
	push dx
	pop ebp

if DXUNREAL
;--- the dx cmd, when using int 15h,ah=87, has the
;--- side effect that unreal-mode most likely is disabled
;--- after the call. Setting DXUNREAL=1 avoids that,
;--- but has the disadvantange that DX won't work in v86-mode!

	smsw ax			; don't use ispm, since that won't detect v86! 
	test al,1
	jnz extmem_exit
	push ds
	push cs
	push offset int0d
	pop ebx
	xor ecx,ecx
	mov ds,cx
	mov esi,ebp
	mov al,1
	mov cl,20h
	mov edi,offset line_out+128
	cli
	xchg ebx,ds:[0dh*4]
	db 67h
	rep movsd
	xchg ebx,ds:[0dh*4]
	dec al    ;has an exception occured?
	jz @F     ;if no, don't reset unreal mode!
	mov cx,SEL_DATA16
	call setdspm
@@:
	sti
	pop ds
else
	mov di,offset line_out	;create a GDT for Int 15h, ah=87h
	xor ax,ax
	mov cx,24	;init 6 descriptors (48 bytes)
	rep stosw
	sub di,4*8
	mov ax,007Fh;limit of source (128 bytes)
	stosw
	mov ax,dx   ;base[0-15] of source
	stosw
	mov al,bl   ;base[16-23] of source
	stosb
	mov ax,0093h
	stosw
	mov al,bh   ;base[24-31] of source
	stosb
	mov ax,007Fh;limit of dest
	stosw
	lea eax,[line_out+128]
	movzx ebx,[pspdbg]
	shl ebx,4
	add eax,ebx
	stosw       ;base[0-15] of dest
	shr eax,16
	stosb       ;base[16-23] of dest
	mov bl,ah
	mov ax,0093h
	stosw
	mov al,bl
	stosb       ;base[24-31] of dest
	call ispm
	mov si,offset line_out ;ds:si -> GDT
	mov cx,0040h	;number of word to copy
	mov ah,87h
	jz @F
	invoke intcall, 15h, cs:[pspdbg]
	jmp i15ok
@@:
	int 15h
i15ok:
	jc extmem_exit
endif
	mov si,offset line_out+128
	mov ch,8h
nextline:
	mov di,offset line_out
	mov eax,ebp
	call hexdword
	mov ax,"  "
	stosw
	lea bx,[di+3*16]
	mov cl,10h
nextbyte:
	lodsb
	mov ah,al
	cmp al,20h
	jnc @F
	mov ah,'.'
@@:
	mov [bx],ah
	inc bx
	call hexbyte
	mov al,' '
	stosb
	dec cl
	jnz nextbyte
	mov byte ptr [di-(8*3+1)],'-'	;display a '-' after 8 bytes
	mov di,bx
	push cx
	call putsline
	pop cx
	add ebp,10h
	dec ch
	jnz nextline
	mov [x_addr],ebp
extmem_exit:
	ret
	.8086
extmem endp

endif

;--- D command - hex/ascii dump.

d_cmd proc
	cmp al,CR
	jne dd1		;if an argument was given
lastddd:
	mov bx,[d_addr+4]
	sizeprfX	;mov edx,[d_addr]
	mov dx,[d_addr]	;compute range of 80h or until end of segment
	sizeprfX	;mov esi,edx
	mov si,dx
	add dx,7fh
	jnc dd2		;if no overflow
	mov dx,0ffffh
	jmp dd2

dd1:
if ?PM
	mov ah,[si-2]		;test for 2-letter cmds (DI, DL, DM, DX)
	and ah,TOUPPER
	cmp ah,'D'
	jnz dd1_1
	or al,TOLOWER
	cmp al,'l'
	jnz @F
	jmp  descout
@@:
	cmp al,'i'
	jnz @F
	jmp  gateout
@@:
endif
if DXSUPP
	cmp al,'x'
	jnz @F
	cmp [machine],3
	jb @F
	jmp extmem
@@:
endif
if MCB
	cmp al,'m'
	jnz @F
	jmp mcbout
@@:
endif
dd1_1:
	mov cx,80h		;default length
	mov bx,[regs.rDS]
	call getrangeX	;get address range into bx:(e)dx
	call chkeol		;expect end of line here

	mov [d_addr+4],bx	;save segment (offset is saved later)
	sizeprfX	;mov esi,edx
	mov si,dx
	mov dx,cx		;dx = end address
    
	jmp dd2_1

;--- Parsing is done.  Print first line.

dd2:
if 0;PM
	call ispm
	jz dd2_1
	.286
	verr bx
	jz dd2_1
	mov bx,[regs.rDS]
	mov [d_addr+4],bx
	.8086
endif
dd2_1:
	mov [lastcmd],offset lastddd
	mov ax,[d_addr+4]
	call hexword
	mov al,':'
	stosb
	mov ax,si
if ?PM
	xor bp,bp
	push ax
	call getselattr		;sets Z flag
	pop ax
	jz @F
	inc bp
	.386
	shld eax,esi,16		;AX=HiWord(esi)
	.8086
	call hexword
	mov ax,si
@@:
endif

	and al,0f0h
	push ax
	call hexword
	mov ax,'  '
	stosw
	pop ax
	lea bx,[di+3*16]
;	mov byte ptr [bx-1],' '
	call prephack		;set up for faking int vectors 23 and 24

;--- blank the start of the line if offset isn't para aligned

dd3:
	cmp ax,si			;skip to position in line
	je dd4				;if we're there yet
	push ax
	mov ax,'  '
	stosw
	stosb
	mov es:[bx],al
	inc bx
	pop ax
	inc ax
	jmp dd3

;--- Begin main loop over lines of output.

dd4:
	mov cx,si
	or cl,0fh
	cmp cx,dx		;compare with end address
	jb @F			;if we write to the end of the line
	mov cx,dx
@@:
	sub cx,si
	inc cx			;cx = number of bytes to print this line
	call dohack		;set debuggee's int 23/24
	mov ds,[d_addr+4]
dd6:
if ?PM
	and bp,bp
	jz $+3
	db 67h			;lods [esi] 
endif
	lodsb
	push ax
	call hexbyte
	mov al,' '
	stosb
	pop ax
	cmp al,' '
	jb dd7		;if control character
	cmp al,'~'
	jbe dd8		;if printable
dd7:
	mov al,'.'
dd8:
	mov es:[bx],al
	inc bx
	loop dd6

dd9:
	test si,0fh		;space out till end of line
	jz dd10
	mov ax,'  '
	stosw
	stosb
	inc si
	jmp dd9

dd10:
	push ss		;restore ds
	pop ds
	sizeprfX	;mov [d_addr],esi
	mov [d_addr],si
	mov byte ptr [di-25],'-'
	call unhack	;set debugger's int 23/24
	mov di,bx
	push dx
	call putsline
	pop dx
	dec si
	cmp si,dx
	jae dd11		;if we're done
	inc si
if 0
	mov di,offset line_out+5	;set up for next time
	mov ax,si
	call hexword
	inc di
	inc di
	lea bx,[di+50]
	jmp dd4
else
	mov di,offset line_out
	mov bx,[d_addr+4]
	jmp dd2
endif
dd11:
	inc dx		;set up the address for the next 'D' command.
	mov [d_addr],dx
	ret
d_cmd endp

errorj4:
	jmp cmd_error

;--- E command - edit memory.

e_cmd proc
	call prephack
	mov bx,[regs.rDS]
	call getaddr	;get address into bx:(e)dx
	call skipcomm0
	cmp al,CR
	je ee1			;if prompt mode
	push dx			;save destination offset
	call getstr		;get data bytes
	mov cx,di
	mov dx,offset line_out
	sub cx,dx		;length of byte string
	pop di
	mov ax,cx
	dec ax
	add ax,di
	jc errorj4		;if it wraps around
	call dohack		;set debuggee's int 23/24
	mov si,dx
	mov es,bx
if ?PM
	cmp [bAddr32],0
	jz @F
	.386
	mov dx,di		;dx was destroyed
	mov edi,edx
	movzx esi,si
	movzx ecx,cx
	db 67h		;rep movsb [edi], [esi]
	.8086
@@:
endif
	rep movsb

;--- Restore ds + es and undo the interrupt vector hack.
;--- This code is also used by the 'm' command.

ee0a::
	push ss			;restore ds
	pop ds
	push ss			;restore es
	pop es
	mov di,offset run2324	;debuggee's int 23/24 values
	call prehak1	;copy things back
	call unhack		;set debugger's int 23/24
	ret

;--- Prompt mode.

ee1:

;--- Begin loop over lines.

ee2:				;<--- next line
	mov ax,bx		;print out segment and offset
	call hexword
	mov al,':'
	stosb
	mov bp,offset hexword
if ?PM
	cmp [bAddr32],0
	jz @F
	mov bp,offset hexdword
	db 66h	;mov eax,edx
@@:
endif
	mov ax,dx
	call bp

;--- Begin loop over bytes.

ee3:				;<--- next byte
	mov ax,'  '		;print old value of byte
	stosw
	call dohack		;set debuggee's int 23/24
	push bx
	call readmem	;read mem at BX:(E)DX
	pop bx
	call unhack		;set debugger's int 23/24
	call hexbyte
	mov al,'.'
	stosb
	push bx
	push dx
	call puts
	pop dx
	pop bx
	mov si,offset line_out+16	;address of buffer for characters
	xor cx,cx		;number of characters so far

ee4:
	cmp [notatty],0
	jz ee9			;if it's a tty
	push si
	mov di,offset line_in+2
	mov si,[bufnext]
ee5:
	cmp si,[bufend]
	jb ee6			;if there's a character already
	call fillbuf
	mov al,CR
	jc ee8			;if eof
ee6:
	cmp [notatty],CR
	jne ee7			;if no need to compress CR/LF
	cmp byte ptr [si],LF
	jne ee7			;if not a line feed
	inc si			;skip it
	inc [notatty]	;avoid repeating this
	jmp ee5			;next character

ee7:
	lodsb			;get the character
	mov [notatty],al
ee8:
	mov [bufnext],si
	pop si
	jmp ee10

ee9:
	call InDos      ;v1.27: use BIOS if InDOS
	jnz @F
	mov ah,8		;console input without echo
	int 21h
	jmp ee10
@@:
	mov ah,0h
	int 16h

ee10:
	cmp al,' '
	je ee13			;if done with this byte
	cmp al,CR
	je ee13			;ditto
	cmp al,BS
	je ee11			;if backspace
	cmp al,'-'
	je ee112		;if '-'
	cmp cx,2		;otherwise, it should be a hex character
	jae ee4			;if we have a full byte already
	mov [si],al
	call getnyb
	jc ee4			;if it's not a hex character
	inc cx
	lodsb			;get the character back
	jmp ee12
ee112:
	call stdoutal
	dec dx			;decrement offset part
	mov di,offset line_out
	jmp ee15
ee11:
	jcxz ee4		;if nothing to backspace over
	dec cx
	dec si
	call fullbsout
	jmp ee4
ee12:
	call stdoutal
	jmp ee4			;back for more

;--- We have a byte (if CX != 0).

ee13:
	jcxz ee14		;if no change for this byte
	mov [si],al		;terminate the string
	sub si,cx		;point to beginning
	push cx
	push dx
	lodsb
	call getbyte	;convert byte to binary (DL)
	mov al,dl
	pop dx
	pop cx
	call dohack		;set debuggee's int 23/24
	call writemem	;write AL at BX:(E)DX
	mov di,offset run2324	;debuggee's int 23/24
	call prehak1	;copy things back
	call unhack		;set debugger's int 23/24

;--- End the loop over bytes.

ee14:
	inc dx			;increment offset
	mov di,offset line_out
	cmp al,CR
	je ee16			;if done
	test dl,7
	jz ee15			;if new line
	not cx
	add cx,4		;compute 3 - cx
	mov al,' '
	rep stosb		;store that many spaces
	jmp ee3			;back for more

ee15:
	mov ax,LF * 256 + CR;terminate this line
	stosw
	jmp ee2			;back for a new line

ee16:
	jmp putsline	;call putsline and return
e_cmd endp

;--- F command - fill memory

f_cmd proc
	xor cx,cx		;get address range (no default length)
	mov bx,[regs.rDS]
	call getrange	;get address range into bx:(e)dx/(e)cx
if ?PM
	cmp [bAddr32],0
	jz @F
	.386
	sub ecx,edx
	inc ecx
	push ecx
	push edx
	.8086
	jmp ff_01
@@:
endif
	sub cx,dx
	inc cx		;cx = number of bytes
	push cx		;save it
	push dx		;save start address
ff_01:
	call skipcomm0
	call getstr		;get string of bytes
	mov cx,di
	sub cx,offset line_out
if ?PM
	cmp [bAddr32],0
	jz ff_1
	.386
	pop edi
	mov es,bx
	cmp ecx,1
	je ff3_32
	pop eax
	cdq
	div ecx
	or eax,eax
	jz ff2_32
ff1_32:
	mov esi,offset line_out
	push ecx
	rep movsb es:[edi], ds:[esi]
	pop ecx
	dec eax
	jnz ff1_32
ff2_32:
	mov ecx,edx
	jecxz ff_exit		;if no partial copies
	mov si,offset line_out
	rep movsb es:[edi], ds:[esi]
	jmp ff_exit		;done (almost)
ff3_32:
	pop ecx
	mov al,byte ptr [line_out]
	rep stosb es:[edi]
	jmp ff_exit
	.8086
ff_1:
endif
	pop di
	mov es,bx
	cmp cx,1
	je ff3		;a common optimization
	pop ax		;get size
	xor dx,dx	;now size in DX:AX
	cmp ax,1
	adc dx,0	;convert 0000:0000 to 0001:0000
	div cx		;compute number of whole repetitions
	or ax,ax
	jz ff2		;if less than one whole rep
ff1:
	mov si,offset line_out
	push cx
	rep movsb
	pop cx
	dec ax
	jnz ff1		;if more to go
ff2:
	mov cx,dx
	jcxz ff_exit;if no partial copies
	mov si,offset line_out
	rep movsb
	jmp ff_exit	;done (almost)
ff3:
	pop cx
	mov al,byte ptr [line_out]
	stosb		;cx=0 -> 64 kB
	dec cx
	rep stosb
ff_exit:
	push ss		;restore es
	pop es
	ret
f_cmd endp

;--- breakpoints are stored in line_out, with this format
;--- WORD cnt
;--- array:
;--- DWORD/WORD offset of bp
;--- WORD segment of bp
;--- BYTE old value

resetbps:
	mov di,offset resetbp1
setbps proc
	mov si,offset line_out
	lodsw
	xchg cx, ax		;mov cx,ax
@@:
	jcxz @F
	sizeprfX		;lodsd
	lodsw
	sizeprfX		;xchg edx,eax
	xchg dx,ax		;mov dx,ax
	lodsw
	xchg bx,ax		;mov bx,ax
	call di			;call setbp1/resetbp1
	inc si
	loop @B 		;next bp
@@:
	ret
setbp1::
	mov al,0CCh
	call writemem
	mov [si],ah		;save the current contents
	retn
resetbp1::
	mov al,[si]
	cmp al,0CCh
	jz @F
	call writemem
@@:
	retn

setbps endp

if ?PM

;--- with DEBUGX: when a mode switch did occur in the debuggee,
;--- the segment parts of the breakpoint addresses are no
;--- longer valid in the new mode. To enable the debugger to reset the
;--- breakpoints, it has to switch temporarily to the previous mode.
;--- in: DX=old value of regs.msw

resetbpsEx proc

	cmp dx,[regs.msw]
	jz resetbps			; mode didn't change, use normal reset routine
	cmp [run_int],offset progtrm	;skip reseting bps if debuggee terminated
	jz @F
	cmp byte ptr [line_out],0	;any breakpoints defined?
	jz @F
	mov cx,[dpmi_size]	; don't call save state if buffer size is zero.
	jcxz do_switch		; this avoids a CWSDPMI bug
	sub sp, cx
	mov al,0			; al=0 is "save state"
	call sr_state
	call do_switch
	mov al,1			; al=1 is "restore state"
	call sr_state
	add sp,[dpmi_size]
@@:
	ret
do_switch:
	call switchmode 	; switch to old mode
	call resetbps
	jmp  switchmode 	; switch back to new mode

switchmode::
;--- raw switch:
;--- si:e/di: new cs:e/ip
;--- dx:e/bx: new ss:e/sp
;--- ax:      new ds
;--- cx:      new es
	sizeprf		;xor ebx,ebx
	xor bx,bx	;clears hiword EBX if cpu >= 386
	mov bx,sp
	sizeprf		;xor edi,edi
	xor di,di	;clears hiword EDI if cpu >= 386
	mov di,back_after_switch
	call ispm
	jnz is_pm
	mov ax,[dssel]	;switch rm -> pm
	mov si,[cssel]
	mov dx,ax
	mov cx,ax
	jmp [dpmi_rm2pm]
is_pm:
	mov ax,[pspdbg]	;switch pm -> rm
	mov si,ax
	mov dx,ax
	mov cx,ax
	cmp dpmi32,0
	jz @F
	db 66h		;jmp fword ptr [dpmi_pm2rm]
@@:
	jmp dword ptr [dpmi_pm2rm]
back_after_switch:
	xor [regs.msw],-1
	retn

sr_state::
	sizeprf		;xor edi,edi
	xor di,di	;clears hiword EDI if cpu >= 386
	mov di,sp
	add di,2	;the save space starts at [sp+2]
	call ispm
	jnz is_pm2
	call [dpmi_rmsav]
	retn
is_pm2:
	cmp dpmi32,0
	jz @F
	db 66h		;call fword ptr [dpmi_pmsav]
@@:
	call dword ptr [dpmi_pmsav]
	retn

resetbpsEx endp

endif

;--- G command - go.

g_cmd proc
	xchg ax,bx		;mov bx,ax
	mov ax,[regs.rCS]	;save original CS
;	mov [run_cs],ax
	mov [eqladdr+4],ax
	xchg ax,bx		;mov ax,bx
	call parseql	;get optional <=addr> argument

;--- Parse the rest of the line for breakpoints

	mov di,offset line_out
	xor ax,ax
	stosw
@@:
	dec si
	call skipcomma
	cmp al,CR		;end of line?
	je @F
	mov bx,[eqladdr+4]	;default segment
	call getaddr	;get address into bx:(e)dx
	sizeprfX		;xchg eax,edx
	xchg ax,dx		;mov ax,dx
	sizeprfX		;stosd
	stosw
	xchg ax,bx		;mov ax,bx
	stosw
	inc di
	inc byte ptr line_out	;use [line_out+0] to count bps
	jmp @B			;next bp
@@:

;--- Store breakpoint bytes in the given locations.

	mov di,offset setbp1
	call setbps
if ?PM
	push [regs.msw]	;save old MSW
endif
	call run		;run the program
if ?PM
	call getcsattr
	mov [bCSAttr],al
endif
	mov cx,-1
	call getcseipbyte	;get byte at [cs:eip-1], set E/BX to E/IP-1
if ?PM
	pop dx			;get old MSW
endif

;--- Restore breakpoint bytes.

;--- it's questionable if this should be done when
;--- the debuggee has terminated [run_int] == progtrm.
;--- for protected-mode, if the DPMI host has been terminated as well
;--- it will most likely crash when a raw-mode switch is to be done.

	push ax
if ?PM
	call resetbpsEx		;reset BPs, switch tmp. to previous mode
else
	call resetbps
endif
	pop ax

;--- Finish up.  Check if it was one of _our_ breakpoints.

	cmp al,0CCh
	jnz gg_exit
	cmp [run_int],offset int3msg
	jne gg_exit		;if not CC interrupt
	mov cx,-1
	call getcseipbyte	;will set E/BX to E/IP-1
	cmp al,0CCh
	jz gg_exit

;--- it WAS one of our BPs! Decrement E/IP!

	sizeprfX		;mov [regs.rIP],ebx
	mov [regs.rIP],bx
	call dumpregs
	ret
gg_exit:
	jmp ue_int		;print messages and quit.

g_cmd endp

;--- H command - hex addition and subtraction.

h_cmd proc
	call getdword	;get dword in BX:DX
	push bx
	push dx
	call skipcomm0
	call getdword
	call chkeol		;expect end of line here
	pop cx
	pop ax			;first value in AX:CX, second in BX:DX
if 0
	mov si,ax
	or si,bx
	jnz hh32		;32bit values
	mov ax,cx
	add ax,dx
	push cx
	call hexword
	pop cx
	mov ax,'  '
	stosw
	mov ax,cx
	sub ax,dx
	call hexword
	call putsline
	ret
endif
hh32:
	mov si,ax
	mov bp,cx			;first value in SI:BP now
	mov ax,cx
	add ax,dx
	push ax
	mov ax,si
	adc ax,bx
	jz @F
	call hexword
@@:
	pop ax
	call hexword
	mov ax,'  '
	stosw
	mov ax,bp
	sub ax,dx
	push ax
	mov ax,si
	sbb ax,bx
	jz @F
	or si,bx
	jz @F
	call hexword
@@:
	pop ax
	call hexword
	call putsline
	ret
h_cmd endp

;--- I command - input from I/O port.

i_cmd proc
	mov bl,0
	mov ah,al
	and ah,TOUPPER
	cmp ah,'W'
	je ii_1
	cmp [machine],3
	jb ii_2
	cmp ah,'D'
	jne ii_2
if 1
	mov ah,[si-2]		;distiguish 'id' and 'i d'
	and ah,TOUPPER
	cmp ah,'I'
	jnz ii_2
endif
	inc bx
ii_1:
	inc bx
	call skipwhite
ii_2:
	call getword		;get word into DX
	call chkeol			;expect end of line here
	cmp bl,1
	jz ii_3
	cmp bl,2
	jz ii_4
	in al,dx
	call hexbyte
	jmp ii_5
ii_3:
	in ax,dx
	call hexword
	jmp ii_5
ii_4:
	.386
	in eax,dx
	.8086
	call hexdword
ii_5:
	call putsline
	ret
i_cmd endp

if ?PM
LoadSDA:
	call ispm
	mov si,word ptr [pSDA+0]
	mov ds,[SDASel]
	jnz @F
	mov ds,word ptr cs:[pSDA+2]
@@:
	ret

ispm proc
	cmp cs:[regs.msw],0 	;returns: Z=real-mode, NZ=prot-mode
	ret
ispm endp
endif

setpspdbg:		;<--- activate debugger's PSP
if DRIVER
	ret
else
	mov bx,cs	;if format is changed to MZ, this must be changed as well!
endif
setpsp proc
	mov ah,50h
if ?PM
	call ispm
	jz setpsp_rm
if NOEXTENDER
	.286
	push cx
	push dx
	push bx
	push ax
	mov ax,6
	int 31h
	pop ax
	shl cx,12
	shr dx,4
	or dx,cx
	mov bx,dx
	call doscallx
	pop bx
	pop dx
	pop cx
	ret
	.8086
else
	jmp doscall_rm
endif
setpsp_rm:
endif

if USESDA
if ?PM
	cmp word ptr [pSDA+2],0
	jz doscall_rm
endif
	push ds
	push si
if ?PM
	call LoadSDA
else
	lds si,[pSDA]
endif
	mov [si+10h],bx
	pop si
	pop ds
	ret
else
	jmp doscall_rm
endif

setpsp endp

getpsp proc
	mov ah,51h
if ?PM
	call ispm
	jz getpsp_rm
if NOEXTENDER
	call doscallx
	mov ax,2
	int 31h
	mov bx,ax
	ret
else
	jmp doscall_rm
endif
getpsp_rm:
endif

if USESDA
if ?PM
	cmp word ptr [pSDA+2],0
	jz doscall_rm
endif
	push ds
	push si
if ?PM
	call LoadSDA
else
	lds si,[pSDA]
endif
	mov bx,[si+10h]
	pop si
	pop ds
	ret
else
	jmp doscall_rm
endif
getpsp endp

doscall:
if NOEXTENDER
	call ispm
	jz doscall_rm
	.286
doscallx:
	invoke intcall, 21h, cs:[pspdbg]
	ret
	.8086
endif
doscall_rm:
	int 21h
	ret

if ?PM

RMCS struc		;the DPMI "real-mode call structure"
rDI		dw ?,?	;+0
rSI		dw ?,?	;+4
rBP		dw ?,?	;+8
		dw ?,?	;+12
rBX 	dw ?,?	;+16
rDX 	dw ?,?	;+20
rCX		dw ?,?	;+24
rAX		dw ?,?	;+28
rFlags	dw ?	;+32
rES 	dw ?	;+34
rDS 	dw ?	;+36
rFS 	dw ?	;+38
rGS 	dw ?	;+40
rIP 	dw ?	;+42
rCS 	dw ?	;+44
rSP 	dw ?	;+46
rSS 	dw ?	;+48
RMCS ends

	.286

intcall proc stdcall uses es intno:word, dataseg:word

local rmcs:RMCS

	push ss
	pop es
	mov rmcs.rDI,di
	mov rmcs.rSI,si
	mov rmcs.rBX,bx
	mov rmcs.rDX,dx
	mov rmcs.rCX,cx
	mov rmcs.rAX,ax
	mov ax,[bp+0]
	mov rmcs.rBP,ax
	xor cx,cx
	mov rmcs.rFlags,cx
	mov rmcs.rSP,cx
	mov rmcs.rSS,cx
	mov ax,dataseg
	mov rmcs.rES,ax
	mov rmcs.rDS,ax
	sizeprf	;lea edi,rmcs
	lea di,rmcs
	mov bx,intno
	mov ax,0300h
	int 31h
	mov ah,byte ptr rmcs.rFlags
	lahf
	mov di,rmcs.rDI
	mov si,rmcs.rSI
	mov bx,rmcs.rBX
	mov dx,rmcs.rDX
	mov cx,rmcs.rCX
	mov ax,rmcs.rAX
	ret
intcall endp
	.8086
endif

if ?PM

;--- this proc is called in pmode only
;--- DS is unknown!

isextenderavailable proc
	.286
	push ds
	push es
	pusha
	push ss
	pop ds
	sizeprf		;lea esi, szMSDOS
	lea si, szMSDOS	;must be LEA, don't change to "mov si,offset szMSDOS"!
	mov ax,168ah
	int 2Fh
	cmp al,1
	cmc
	popa
	pop es
	pop ds
	ret
	.8086

CONST segment
szMSDOS	db "MS-DOS",0
CONST ends

isextenderavailable endp

nodosextinst:
	push ss
	pop ds
	mov dx,offset nodosext
	jmp int21ah9
endif

if DRIVER eq 0
isdebuggeeloaded:
	mov ax,[pspdbe]
	cmp ax,[pspdbg]
	ret
endif

;--- ensure a debuggee is loaded
;--- set SI:DI to CS:IP, preserve AX, BX, DX

ensuredebuggeeloaded proc
if DRIVER eq 0
	push ax
	call isdebuggeeloaded
	jnz @F
	push bx
	push dx
	call createdummytask
	mov si,[regs.rCS]
	mov di,[regs.rIP]
	pop dx
	pop bx
@@:
	pop ax
endif
	ret
ensuredebuggeeloaded endp

;--- L command - read a program, or disk sectors, from disk.

l_cmd proc
	call parselw	;parse it, addr in bx:(e)dx
	jz ll1			;if request to read program
if NOEXTENDER
	call ispm
	jz @F
	call isextenderavailable
	jc nodosextinst
@@:
endif
	cmp cs:[usepacket],2
	jb ll0_1
	mov dl,al		;A=0,B=1,C=2,...
	xor si,si		;read drive
if VDD
	mov ax,[hVdd]
	cmp ax,-1
	jnz callvddread
endif
	inc dl			;A=1,B=2,C=3,...
	mov ax,7305h	;DS:(E)BX -> packet
	stc
	int 21h			;use int 21h here, not doscall!
	jmp ll0_2
if VDD
callvddread:
	mov cx,5
	add cl,[dpmi32]
	DispatchCall
	jmp ll0_2
endif
ll0_1:
	int 25h
ll0_2:
	mov dx,offset reading
	jmp ww1

;--- For .com or .exe files, we can only load at cs:100.  Check that first.

ll1:
if DRIVER eq 0
	test [fileext], EXT_COM or EXT_EXE
	jz loadfile		;if not .com or .exe file
	cmp bx,[regs.rCS]
	jne ll2			;if segment is wrong
	cmp dx,100h
	je loadfile		;if address is OK (or not given)
ll2:
endif
	jmp cmd_error	;can only load .com or .exe at cs:100

l_cmd endp

if DRIVER eq 0

;--- load (any) file (if not .EXE or .COM, load at BX:DX)
;--- open file and get length

loadfile proc
	mov si,bx		;save destination address, segment
	mov di,dx		;and offset
	mov ax,3d00h	;open file for reading
	mov dx,DTA
	call doscall
	jnc @F			;if no error
	jmp io_error	;print error message
@@:
	xchg ax,bx		;mov bx,ax
	mov ax,4202h	;lseek EOF
	xor cx,cx
	xor dx,dx
	int 21h

;   Split off file types
;   At this point:
;       bx      file handle
;       dx:ax   file length
;       si:di   load address (CS:100h for .EXE or .COM)

	test [fileext],EXT_COM or EXT_EXE
	jnz loadpgm		;if .com or .exe file

if ?PM
;--- dont load a file in protected mode,
;--- the read loop makes some segment register arithmetic
	call ispm
	jz @F
	mov dx,offset nopmsupp
	call int21ah9
	jmp ll12
@@:
endif

;--- Load it ourselves.
;--- For non-.com/.exe files, we just do a read, and set BX:CX to the
;--- number of bytes read.

	call ensuredebuggeeloaded	;make sure a debuggee is loaded
	mov es,[pspdbe]

;--- Check the size against available space.

	push si
	push bx

	cmp si,es:[ALASAP]
	pushf
	neg si
	popf
	jae ll6				;if loading past end of mem, allow through ffff
	add si,es:[ALASAP]	;si = number of paragraphs available
ll6:
	mov cx,4
	xor bx,bx
ll7:
	shl si,1
	rcl bx,1
	loop ll7
	sub si,di
	sbb bx,cx  		;bx:si = number of words left
	jb ll9			;if already we're out of space
	cmp bx,dx
	jne @F
	cmp si,ax
@@:
	jae ll10		;if not out of space
ll9:
	pop bx			;out of space
	pop si
	mov dx,offset doserr8	;not enough memory
	call int21ah9	;print string
	jmp ll12

ll10:
	pop bx
	pop si

;--- Store length in registers

;--- seems a bit unwise to modify registers if a debuggee is running 
;--- but MS DEBUG does it as well

if 0
	mov cx,[regs.rCS]
	cmp cx,[pspdbe]
	jnz noregmodify
	cmp [regs.rIP],100h
	jnz noregmodify
endif
	mov [regs.rBX],dx
	mov [regs.rCX],ax
noregmodify:    

;--- Rewind the file

	mov ax,4200h	;lseek
	xor cx,cx
	xor dx,dx
	int 21h

	mov dx,0fh
	and dx,di
	mov cl,4
	shr di,cl
	add si,di		;si:dx is the address to read to

;--- Begin loop over chunks to read

ll11:
	mov ah,3fh		;read from file into DS:(E)DX
	mov cx,0fe00h	;read up to this many bytes
	mov ds,si
	int 21h
    
	add si,0fe0h	;wont work in protected-mode!
	cmp ax,cx
	je ll11			;if end of file reached

;--- Close the file and finish up.

ll12:
	mov ah,3eh		;close file
	int 21h
	push ss			;restore ds
	pop ds
	ret				;done

loadfile endp

setespefl proc
	sizeprf		;pushfd
	pushf
	sizeprf		;pop dword ptr [regs.rFL]
	pop [regs.rFL]
	sizeprf		;mov dword ptr [regs.rSP],esp
	mov [regs.rSP],sp	;low 16bit of ESP will be overwritten
	ret
setespefl endp

loadpgm proc

;--- file is .EXE or .COM
;--- Close the file

	push ax
	mov ah,3eh		;close file
	int 21h
	pop bx			;dx:bx is the file length

if 1

;--- adjust .exe size by 200h (who knows why)

	test [fileext],EXT_EXE
	jz @F		;if not .exe
	sub bx,200h
	sbb dx,0
@@:
endif

	push bx
	push dx

;--- cancel current process (unless there is none)
;--- this will also put cpu back in real-mode!!!

	call isdebuggeeloaded
	jz @F
	call freemem
@@:

;--- Clear registers

	mov di, offset regs
	mov cx, sizeof regs / 2
	xor ax, ax
	rep stosw

	pop word ptr [regs.rBX]
	pop word ptr [regs.rCX]

;--- Fix up interrupt vectors in PSP

	mov si,CCIV		;address of original INT 23 and 24 (in PSP)
	mov di,offset run2324
	movsw
	movsw
	movsw
	movsw

;--- Actual program loading.  Use the DOS interrupt.

	mov ax,4b01h	;load program
	mov dx,DTA		;offset of file to load
	mov bx,offset execblk	;parameter block
	int 21h			;load it
	jnc @F
	jmp io_error	;if error
@@:
	call setespefl

;--- we calculate the stack space used by previous dos call (ax=4b01)
;--- and use the result (in spadjust) to adjust the field PSP:[2Eh]
;--- in the debugger's PSP whenever the debuggee is to be executed ("run").
	mov ax,sp
	sub ax,ds:[SPSAV]
	cmp ax,80h
	jb @F			;if in range
	mov ax,80h
@@:
	mov [spadjust],ax

;--- use the values for CS:IP SS:SP returned by the loader

	les si,dword ptr [execblk.sssp]
	lodsw es:[si]	;recover ax
	mov [regs.rAX],ax
	mov [regs.rSP],si
	mov [regs.rSS],es
	les si,dword ptr [execblk.csip]
	mov [regs.rIP],si
	mov [regs.rCS],es
	mov [bInit],0
	push ss
	pop es
	clc

;--- get the debuggee's PSP and store it in debuggee's DS,ES

	call getpsp
	xchg ax,bx		;mov ax,bx
	mov [pspdbe],ax
	mov di,offset regs.rDS
	stosw
	stosw			;regs.rES

	call setpspdbg	;switch back to debugger's PSP

;--- Finish up.  Set termination address.

	mov ax,2522h	;set interrupt vector 22
	mov dx,offset int22
	int 21h
	mov ds,[pspdbe]
;	mov word ptr ds:[TPIV+0],offset int22
	mov word ptr ds:[TPIV+0],dx
	mov word ptr ds:[TPIV+2],cs
	push ss
	pop ds

;--- Set up initial addresses for 'a', 'd', and 'u' commands.

setup_adu::
	mov di,offset a_addr
	mov si,offset regs.rIP
	push di
	movsw
	movsw
	mov ax,[regs.rCS]
	stosw
	pop si
	mov cx,3*2
	rep movsw
	ret

loadpgm endp

endif

;--- M command - move/copy memory.

;--- first check if there is more than 1 argument
;--- 0 or 1 arguments are handled by the 'M [cpu]' code
;--- also check if command is MC, MC2 or MNC

m_cmd proc
	cmp al,CR
	jz mach
	mov ah,[si-2]
	or ah,TOLOWER
	cmp ah,'m'
	jz mach
	push si
	call getdword
	cmp al,CR
	jz @F
	call skipwhite
@@:
	pop si
	cmp al,CR
	je mach				; jump if 1 argument only
	dec si
	lodsb
	call parsecm		;parse arguments (DS:(E)SI, ES:(E)DI, (E)CX)
	push cx
if ?PM
	call ispm
	jz @F
;--- TODO: do overlapping check in protected-mode
	clc
	jmp m3
@@:
endif
	mov cl,4
	shr dx,cl
	add dx,bx		;upper 16 bits of destination
	mov ax,si
	shr ax,cl
	mov bx,ds
	add ax,bx
	cmp ax,dx
	jne m3		;if we know which is larger
	mov ax,si
	and al,0fh
	mov bx,di
	and bl,0fh
	cmp al,bl
m3:
	pop cx
	lahf
	push ds
	push es
	push ss		;ds := cs
	pop ds
	call dohack	;set debuggee's int 23/24
	pop es
	pop ds
if ?PM
	cmp cs:[bAddr32],0
	jz m3_1
	.386
	sahf
	jae @F
	add esi,ecx
	add edi,ecx
	std
@@:
	rep movsb es:[edi], ds:[esi]
	movsb es:[edi], ds:[esi]
	cld
	jmp ee0a
	.8086
m3_1:
endif
	sahf
	jae @F			;if forward copy is OK
	add si,cx
	add di,cx
	std
@@:
	rep movsb		;do the move
	movsb			;one more byte
	cld				;restore flag
	jmp ee0a		;restore ds and es and undo the int pointer hack
m_cmd endp

;--- 'm'achine command:  set machine type.

mach proc
	or al,TOLOWER
	cmp al,'c'
	jz mc
	dec si
	call skipwhite
	cmp al,CR
	je ma1				;if just an 'm' (query machine type)
	call getbyte
	mov al,dl
	cmp al,6
	ja errorj3			;dl must be 0-6
	mov [machine],al	;set machine type
	mov [mach_87],al	;coprocessor type, too
	cmp al,3
	jnc @F
	and [rmode],not RM_386REGS	;reset 386 register display
@@:
	ret

;--- Display machine type.

ma1:
	mov si,offset msg8088
	mov al,[machine]
	cmp al,0
	je @F		;if 8088
	mov si,offset msgx86
	add al,'0'
	mov [si],al
@@:
	call copystring    ;si->di
	mov si,offset no_copr
	cmp [has_87],0
	je @F		;if no coprocessor
	mov si,offset has_copr
	mov al,[mach_87]
	cmp al,[machine]
	je @F		;if has coprocessor same as processor
	mov si,offset has_287
@@:
	call copystring	;si->di
	jmp putsline	;call puts and quit
mach endp

errorj3:
	jmp cmd_error

;--- 'mc' command:  set coprocessor.
;--- optional arguments:
;--- N: no coprocessor
;--- 2: 80287 with 80386

mc proc
	call skipwhite	;get next nonblank character
	mov ah,[machine]
	cmp al,CR
	jz set_mpc
	or al,TOLOWER
	push ax
	lodsb
	call chkeol
	pop ax
	cmp al,'n'
	jne @F			;if something else
	mov [has_87],0	;clear coprocessor flag
	ret				;done
@@:
	cmp al,'2'
	jne errorj3		;if not '2'
	cmp [machine],3
	jnz errorj3		;if not a 386
	mov ah,2
set_mpc:
	mov [has_87],1	;set coprocessor flag
	mov [mach_87],ah
	ret
mc endp

;--- N command - change the name of the program being debugged.

CONST segment
exts label byte
	db ".HEX",EXT_HEX
	db ".EXE",EXT_EXE
	db ".COM",EXT_COM
CONST ends

if DRIVER eq 0

n_cmd proc
	mov di,DTA		;destination address

;--- Copy and canonicalize file name.

nn1:
	cmp al,CR
	je nn3		;if end of line
	call ifsep	;check for separators space, TAB, comma, ;, =
	je nn3		;if end of file name
	cmp al,[swch1]
	je nn3		;if '/' (and '/' is the switch character)
	cmp al,'a'
	jb @F		;if not lower case
	cmp al,'z'
	ja @F		;ditto
	and al,TOUPPER	;convert to upper case
@@:
	stosb
	lodsb
	jmp nn1		;back for more

nn3:
	mov al,0		;null terminate the file name string
	stosb
	mov word ptr [execblk.cmdtail],di	;save start of command tail

;--- Determine file extension

	push di
	push si
	cmp di,DTA+1
	je nn3d			;if no file name at all
	cmp di,DTA+5
	jb nn3c			;if no extension (name too short)
	lea dx,[di-5]
	mov bx,offset exts	;check for .EXE, .COM and .HEX
	mov cx,3
@@:
	push cx
	mov si,bx
	mov di,dx
	add bx,5
	mov cl,4
	repz cmpsb
	mov al,[si]
	pop cx
	jz nn3d
	loop @B
nn3c:
	mov al,EXT_OTHER
nn3d:
	mov [fileext],al
	pop si

;--- Finish the N command

	mov di,offset line_out
	push di
	dec si
@@:
	lodsb			;copy the remainder to line_out
	stosb
	cmp al,CR
	jne @B
	pop si

;--- Set up FCBs.

	mov di,5ch
	call DoFCB		;do first FCB
	mov byte ptr [regs.rAX+0],al
	mov di,6ch
	call DoFCB		;second FCB
	mov byte ptr [regs.rAX+1],al

;--- Copy command tail.

	mov si,offset line_out
	pop di
	push di
	inc di
@@:
	lodsb
	stosb
	cmp al,CR
	jne @B		;if not end of string
	pop ax		;recover old DI
	xchg ax,di
	sub ax,di	;compute length of tail
	dec ax
	dec ax
	stosb
	ret
n_cmd endp

endif

;--- Subroutine to process an FCB.
;--- di->FCB

DoFCB proc
@@:
	lodsb
	cmp al,CR
	je nn7		;if end
	call ifsep
	je @B		;if separator
	cmp al,[switchar]
	je nn10		;if switch character
nn7:
	dec si
	mov ax,2901h;parse filename
	call doscall
	push ax		;save AL
@@:
	lodsb		;skip till separator
	cmp al,CR
	je @F		;if end
	call ifsep
	je @F		;if separator character
	cmp al,[swch1]
	jne @B		;if not switchar (sort of)
@@:
	dec si
	pop ax		;recover AL
	cmp al,1
	jne @F		;if not 1
	dec ax
@@:
	ret

;--- Handle a switch (differently).

nn10:
	lodsb
	cmp al,CR
	je nn7		;if end of string
	call ifsep
	je nn10		;if another separator
	mov al,0
	stosb
	dec si
	lodsb
	cmp al,'a'
	jb @F		;if not a lower case letter
	cmp al,'z'
	ja @F
	and al,TOUPPER	;convert to upper case
@@:
	stosb
	mov ax,'  '
	stosw
	stosw
	stosw
	stosw
	stosw
	xor ax,ax
	stosw
	stosw
	stosw
	stosw
	ret			;return with AL=0
DoFCB endp

;--- O command - output to I/O port.

o_cmd proc
	mov bl,0
	mov ah,al
	and ah,TOUPPER
	cmp ah,'W'
	je oo_1
	cmp [machine],3
	jb oo_2
	cmp ah,'D'
	jne oo_2
if 1
	mov ah,[si-2]		;distiguish 'od' and 'o d'
	and ah,TOUPPER
	cmp ah,'O'
	jnz oo_2
endif
	inc bx
oo_1:
	inc bx
	call skipwhite
oo_2:
	call getword
	push dx
	call skipcomm0
	cmp bl,1
	jz oo_4
	cmp bl,2
	jz oo_5
	call getbyte	;dl=byte
	call chkeol		;expect end of line here
	xchg ax,dx		;al = byte
	pop dx			;recover port number
	out dx,al
	ret
oo_4:
	call getword	;dx=word
	call chkeol		;expect end of line here
	xchg ax,dx		;ax = word
	pop dx
	out dx,ax
	ret
oo_5:
	.386
	call getdword	;bx:dx=dword
	call chkeol		;expect end of line here
	push bx
	push dx
	pop eax
	pop dx
	out dx,eax
	ret
	.8086
o_cmd endp

;--- ensure segment in BX is writeable
;--- out: Carry=1 if segment not writeable
;--- might clear HiWord(EDI)

if ?PM

verifysegm proc
	call ispm
	jz is_rm
	.286
	push ax
	push di
	push bp
	mov bp,sp
	sub sp,8
	mov di,sp
	sizeprf				;lea edi,[di] (synonym for movzx edi,di)
	lea di,[di]
	mov ax,000Bh		;get descriptor
	int 31h
	jc @F
	test byte ptr [di+5],8	;code segment?
	jz @F
	and byte ptr [di+5],0F3h;reset CODE+conforming attr
	or byte ptr [di+5],2	;set writable
	mov bx,[scratchsel]
	mov ax,000Ch
	int 31h
@@:
	leave
	pop di
	pop ax
	ret
is_rm:
	ret
	.8086
verifysegm endp

setrmsegm:
	.286
	mov bx,cs:[scratchsel]
setrmaddr:		;<--- set selector in BX to segment address in DX
	mov cx,dx
	shl dx,4
	shr cx,12
	mov ax,7
	int 31h
	ret
	.8086

;--- out: AL= HiByte of attributes of current CS
;--- out: ZF=1 if descriptor is 16bit
;--- called by P, T, U
;--- modifies EAX, BX

getcsattr proc
	mov bx,[regs.rCS]
getselattr::	;<--- any selector in BX
	mov al,00
	cmp [machine],3
	jb @F
	call ispm
	jz @F
	.386
	lar eax,ebx
	shr eax,16
	.8086
@@:
	test al,40h
	ret
getcsattr endp

endif ;PM

;--- read [EIP+x] value 
;--- in: CX=x 
;--- [regs.rCS]=CS
;--- [regh_(e)ip]=EIP
;--- out: AL=[CS:(E)IP]
;--- [E]BX=[E]IP+x 
;--- called by T and G

getcseipbyte proc
	push es
	mov es,[regs.rCS]
	sizeprfX		;mov ebx,[regs.rIP]
	mov bx,[regs.rIP]
if ?PM
	test [bCSAttr],40h
	jz @F
	.386
	movsx ecx,cx
	add ebx,ecx
	mov al,es:[ebx]
	pop es
	ret
	.8086
@@:
endif
	add bx,cx
	mov al,es:[bx]
	pop es
	ret
getcseipbyte endp

;--- set [EIP+x] value 
;--- in: CX=x 
;--- AL=byte to write
;--- [regs.rCS]=CS
;--- [regs.rIP]=EIP
;--- modifies [E]BX

setcseipbyte proc
	push es
	mov bx,[regs.rCS]
if ?PM
	call verifysegm
	jc scib_1
endif
	mov es,bx
	sizeprfX
	mov bx, [regs.rIP]
if ?PM
	test [bCSAttr],40h
	jz is_ip16
	.386
	movsx ecx,cx
	mov es:[ebx+ecx],al
scib_1:
	pop es
	ret
	.8086
is_ip16:
endif
	add bx,cx
	mov es:[bx],al
	pop es
	ret
setcseipbyte endp

;--- write a byte (AL) at BX:E/DX
;--- OUT: AH=old value at that location
;--- C if byte couldn't be written

writemem proc
	push ds
if ?PM
	call ispm
	jz weip16
	call verifysegm	;make bx a writeable segment
	jc done
	push ax
	call getselattr
	pop ax
	jz weip16
	.386
	mov ds,bx
	mov ah,[edx]
	mov [edx],al
	cmp al,[edx]
	jmp done
	.8086
weip16:
endif
	mov ds,bx
	push bx
	mov bx,dx
	mov ah,[bx]
	mov [bx],al
	cmp al,[bx]
	pop bx
done:
	pop ds
	jnz @F
	ret
@@:
	stc
	ret
writemem endp

;--- read byte at BX:EDX into AL

readmem proc
if ?PM
	call getselattr
endif
	push ds
	mov ds,bx
	sizeprfX	;mov ebx,edx
	mov bx,dx
if ?PM
	jz $+3
	db 67h		;mov al,[ebx]
endif
	mov al,[bx]
	pop ds
	ret
readmem endp

;--- check if an unexpected int 3 has occured
;--- CS:(E)IP in regs.rCS:regs.rIP
;--- in: DX=0, out: DX=msg
;--- called by P, T

IsUnexpInt3 proc
	mov cx,-1
	call getcseipbyte
	cmp al,0CCh
	jz isunexp_exit
	mov dx,offset int3msg
if ?PM
	test [bCSAttr],40h
	jz $+3
	db 66h	;mov [regs.rIP],ebx
endif
	mov [regs.rIP],bx
isunexp_exit:
	ret
IsUnexpInt3 endp

;--- P command - proceed (i.e., skip over call/int/loop/string instruction).

p_cmd proc
	call parse_pt	;process arguments

;--- Do it <CX=count> times.  First check the type of instruction.

pp1:
	push cx			;save cx
	mov dx,15		;DL = number of bytes to go; DH = prefix flags.
if ?PM
	call getcsattr
	mov [bCSAttr],al
	jz @F
	mov dh,PP_ADRSIZ + PP_OPSIZ
	db 66h		;mov esi,[regs.rIP]
@@:
endif
	mov si,[regs.rIP]
pp2:
	call getnextb	;AL=[cs:(e)ip], eip++
	mov di,offset ppbytes
	mov cx,PPLEN
	repne scasb
	jne pp5			;if not one of these
	mov al,[di+PPLEN-1]	;get corresponding byte in ppinfo
	test al,PP_PREFIX
	jz @F			;if not a prefix
	xor dh,al		;update the flags
	dec dl
	jnz pp2			;if not out of bytes
	jmp pp12		;more than 15 prefixes will cause a GPF
@@:
	test al,40h
	jz @F		;if no size dependency
	and al,3fh
	and dh,PP_OPSIZ	;for CALL, operand size 2->4, 4->6
	add al,dh
@@:
	cbw
	call addeip	;add ax to instruction pointer in (E)SI
	jmp pp11	;we have a skippable instruction here

pp5:
	cmp al,0ffh	;indirect call?
	jz @F
	jmp pp12	;just an ordinary instruction
@@:
	call getnextb	;get MOD REG R/M byte
	and al,not 8	;clear lowest bit of REG field (/3 --> /2)
	xor al,10h	;/2 --> /0
	test al,38h
	jz @F
	jmp pp12	;if not ff/2 or ff/3
@@:
	cmp al,0c0h
	jae pp11	;if just a register
	test dh,PP_ADRSIZ
	jnz pp6		;if 32 bit addressing
	cmp al,6
	je pp9		;if just plain disp16
	cmp al,40h
	jb pp11		;if indirect register
	cmp al,80h
	jb pp10		;if disp8[reg(s)]
	jmp pp9		;it's disp16[reg(s)]

pp6:
	cmp al,5
	je pp8		;if just plain disp32
	xor al,4
	test al,7
	jnz @F		;if no SIB byte
	call inceip
@@:
	cmp al,40h
	jb pp11		;if indirect register
	cmp al,80h
	jb pp10		;if disp8[reg(s)]
				;otherwise, it's disp32[reg(s)]
pp8:
	call inceip
	call inceip
pp9:
	call inceip
pp10:
	call inceip

pp11:
	mov bx,[regs.rCS]
	jmp pp11x_1
pp14:
	jmp pp1			;back for more

;--- Special instruction.  Set a breakpoint and run until we hit it.
;--- BX:(E)SI == address where a breakpoint is to be set.

process1::		;<--- used by T if an INT is to be processed
	mov cx,1
	push cx
pp11x_1:		;BX=CS
	mov di,offset line_out	;use the same breakpoint structure as in G
	sizeprfX	;mov edx,esi
	mov dx,si
	mov al,0cch
	call writemem
	mov al,ah
	jnc @F
	mov si,offset cantwritebp
	call copystring
	call putsline
	jmp cmdloop
@@:
	push ax
	mov ax,1	;bp cnt
	stosw
	sizeprfX	;xchg eax,esi
	xchg ax,si
	sizeprfX	;stosd
	stosw
	mov ax,bx
	stosw
	pop ax
	stosb
if ?PM
	push [regs.msw]
endif
	call run		;this might change mode and/or terminate the debuggee!
if ?PM
	call getcsattr	;set variable bCSAttr
	mov [bCSAttr],al
	pop dx
	call resetbpsEx
else
	call resetbps
endif

	xor dx,dx		;set flag
	cmp [run_int],offset int3msg
	jne pp13		;if not CC interrupt
	call IsUnexpInt3;test byte at regs.rCS:regs.rIP-1 if CCh
	jmp pp13

;--- Ordinary instruction.  Just do a trace.

pp12:
	or byte ptr [regs.rFL+1],1	;set single-step mode
	call run
	mov dx,offset int1msg

;--- Common part to finish up.

pp13:
	cmp [run_int],dx
	jne pp15		;if some other interrupt
	call dumpregs
	pop cx
	loop pp14		;back for more
	ret

pp15:
	jmp ue_int		;print message about unexpected interrupt and quit

inceip:
if ?PM
	test [bCSAttr],40h
	jz $+3
	db 66h		;inc esi
endif
	inc si
	ret

addeip:
if ?PM
	test [bCSAttr],40h
	jz @F
	.386
	movzx eax,ax
	.8086
	db 66h		;add esi,eax
@@:
endif
	add si,ax
	ret

;--- getnextb - Get next byte in instruction stream.
;--- [e]si = eip

getnextb:
	push ds
	mov ds,[regs.rCS]
if ?PM
	test cs:[bCSAttr],40h
	jz $+3
	db 67h		;lodsb [esi]
endif
	lodsb
	pop ds
	ret

p_cmd endp

if DRIVER eq 0

;--- Q command - quit.

q_cmd proc

if ?PM
	mov byte ptr [dpmidisable+1],0	;disble DPMI hook
	inc [bNoHook2F]					;avoid a new hook while terminating
endif

;--- cancel child's process if any
;--- this will drop to real-mode if debuggee is in pmode

	call freemem

if VDD
	mov ax,[hVdd]
	cmp ax,-1
	jz @F
	UnRegisterModule
@@:
endif

;--- Restore interrupt vectors.

	mov di,offset intsave
	mov si,offset inttab
	mov cx,NUMINTSX
nextint:
	lodsb
	mov bl,al
	add si,2	;skip rest of INTITEM
	xchg si,di
	lodsw
	mov dx,ax
	lodsw
	xchg si,di
	cmp bl,22h
	jz norestore
	and ax,ax
	jz norestore
	push ds
	mov ds,ax
	mov al,bl
	mov ah,25h
	int 21h
	pop ds
norestore:
	loop nextint

;--- Restore termination address.

	mov si,offset psp22	;restore termination address
	mov di,TPIV
	movsw
	movsw
	mov di,PARENT		;restore PSP of parent
	movsw

;--- Really done.

;--- int 20h sets error code to 0.
;--- might be better to use int 21h, ax=4Cxxh
;--- and load the error code returned by the debuggee
;--- into AL.

	int 20h			;won't work if format == MZ!
	jmp cmdloop		;returned? then something is terribly wrong.

q_cmd endp

endif

if MMXSUPP
rmmx proc
	cmp [has_mmx],1
	jnz @F
	jmp dumpregsMMX
@@:
	ret
rmmx endp
endif

;--- RX command: toggle mode of R command (16 - 32 bit registers)

rx proc
	call skipwhite
	cmp al,CR
	je @F
	jmp rr_err
@@:
	cmp [machine],3
	jb rx_exit
;	mov di,offset line_out
	mov si,offset regs386
	call copystring	;si->di
	xor [rmode],RM_386REGS
	mov ax," n"	;"on"
	jnz @F
	mov ax,"ff"	;"off"
@@:
	stosw
	mov al,0
	stosb
	call putsline
rx_exit:
	ret
rx endp

;--- RN command: display FPU status

rn proc
	call skipwhite
	cmp al,CR
	je @F
	jmp rr_err
@@:
	cmp [has_87],0
	jz @F
	call dumpregsFPU
@@:
	ret
rn endp

;--- R command - manipulate registers.

r_cmd proc
	cmp al,CR
	jne @F		;if there's an argument
	jmp dumpregs
@@:
	and al,TOUPPER
	cmp al,'X'
	je rx
if MMXSUPP
	cmp al,'M'
	je rmmx
endif
	cmp al,'N'
	je rn

;--- an additional register parameter was given

	dec si
	lodsw
	and ax,TOUPPER_W
	mov di,offset regnames
	mov cx,NUMREGNAMES
	repne scasw
	mov bx,di
	mov di,offset line_out
	jne rr2			;if not found in standard register names
	cmp byte ptr [si],20h	;avoid "ES" to be found for "ESI" or "ESP"
	ja rr2
	stosw			;print register name
	mov al,' '
	stosb
	mov bx,[bx+NUMREGNAMES*2-2]
	call skipcomma	;skip white spaces
	cmp al,CR
	jne rr1a		;if not end of line
	push bx			;save bx for later
	mov ax,[bx]
	call hexword
	call getline0	;prompt for new value
	pop bx
	cmp al,CR
	je rr1b			;if no change required
rr1a:
	call getword
	call chkeol		;expect end of line here
	mov [bx],dx		;save new value
rr1b:
	ret

;--- is it the F(lags) register?

rr2:
	cmp al,'F'
	jne rr6			;if not 'f'
	dec si
	lodsb
	cmp al,CR
	je rr2b			;if end of line
	cmp al,' '
	je rr2a			;if white space
	cmp al,TAB
	je rr2a			;ditto
	cmp al,','
	je rr2a
	jmp errorj9		;if not, then it's an error
rr2a:
	call skipcomm0
	cmp al,CR
	jne rr3			;if not end of line
rr2b:
	call dmpflags
	call getline0	;get input line (using line_out as prompt)
rr3:
	cmp al,CR
	je rr1b			;return if done
	dec si
	lodsw
	and ax,TOUPPER_W;here's the mnemonic
	mov di,offset flgnams
	mov cx,16
	repne scasw
	jne rr6			;if no match
	cmp di,offset flgnons
	ja rr4			;if we're clearing
	mov ax,[di-16-2]
	not ax
	and [regs.rFL],ax
	jmp rr5

rr4:
	mov ax,[di-32-2]
	or [regs.rFL],ax

rr5:
	call skipcomma
	jmp rr3			;check if more

;--- it is neither 16bit register nor the F(lags) register.
;--- check for valid 32bit register name!

rr6:
	cmp [machine],3
	jb rr_err
	cmp al,'E'
	jnz rr_err
	lodsb
	and al,TOUPPER
	cmp al,'S'		;avoid EDS,ECS,ESS,... to be accepted!
	jz rr_err
	xchg al,ah
	mov cx,NUMREGNAMES
	mov di,offset regnames
	repne scasw
	jne rr_err

;--- it is a valid 32bit register name

	mov bx,di
	mov di,offset line_out
	mov byte ptr [di],'E'
	inc di
	stosw
	mov al,' '
	stosb
	mov bx,[bx+NUMREGNAMES*2-2]
	call skipcomma	;skip white spaces
	cmp al,CR
	jne rr1aX   	;if not end of line
	push bx
	.386
	mov eax,[bx+0]
	.8086
	call hexdword
	call getline0	;prompt for new value
	pop bx
	cmp al,CR
	je rr1bX		;if no change required
rr1aX:
	push bx
	call getdword
	mov cx,bx
	pop bx
	call chkeol		;expect end of line here
	mov [bx+0],dx	;save new value
	mov [bx+2],cx	;save new value
rr1bX:
	ret

r_cmd endp

rr_err:
	dec si		;back up one before flagging an error
errorj9:
	jmp cmd_error

;--- S command - search for a string of bytes.

s_cmd proc
	mov bx,[regs.rDS]	;get search range
	xor cx,cx
	call getrangeX	;get address range into BX:(E)DX..BX:(E)CX
	call skipcomm0
	push cx
	push dx
	call getstr		;get string of bytes
	pop dx
	pop cx
	sub cx,dx		;cx = number of bytes in search range minus one
	sub di,offset line_out	;di = number of bytes to look for
	dec di			;     minus one
	sub cx,di		;number of possible positions of string minus 1
	jb errorj9		;if none
	call prephack	;set up for the interrupt vector hack
;	inc cx			;cx = number of possible positions of string
	xchg dx,di		;set DI to offset
	call dohack		;set debuggee's int 23/24
sss1:				;<---- search next occurance
	mov es,bx		;set the segment
	mov si,offset line_out	;si = address of search string
	lodsb			;first character in al
	repne scasb		;look for first byte
	je sss1_1
	scasb			;count in CX was cnt-1
	jne sss3		;if we're done
sss1_1:
	push cx
	push di
	mov cx,dx
	repe cmpsb
	pop di
	jne sss2		;if not equal
	call unhack		;set debugger's int 23/24
	push dx
	xchg si,di		;write address right after search string
	mov ax,bx
	call hexword	;4 (segment)
	mov al,':'
	stosb			;+1=5
	lea ax,[si-1]
	call hexword	;+4=9 (offset)
	mov ax,LF * 256 + CR
	stosw			;+2=11
	mov cx,11
	lea dx,[di-11]
	call stdout		;write to stdout
	pop dx
	mov di,si
	call dohack		;set debuggee's int 23/24
sss2:
	pop cx
	inc cx
	loop sss1		;go back for more
sss3:
	jmp unhack		;set debugger's int 23/24
s_cmd endp

ttmode proc
	call skipcomma
	cmp al,CR
	jz ismodeget
	call getword
	cmp dx,1
	jna @F
	jmp cmd_error
@@:
	call chkeol		;expect end of line here
	mov [tmode],dl
;	ret
ismodeget:
;	mov di,offset line_out	;DI is initialized with this value
	mov si,offset tmodes
	call copystring	;si->di
	mov al,[tmode]
	test al,1
	pushf
	add al,'0'
	stosb
	mov si,offset tmodes2
	call copystring	;si->di
	mov si,offset tmode0
	popf
	jz @F
	mov si,offset tmode1
@@:
	call copystring	;si->di
	call putsline
	ret

ttmode endp

;--- T command - Trace.

t_cmd proc
	mov ah,al
	and ah,TOUPPER
	cmp ah,'M'
	jz ttmode	;jump if it's the TM command
tt0:
	mov [lastcmd], offset tt0
	call parse_pt	;process arguments
tt1:
	push cx
	call trace1
	pop cx
	loop tt1
	ret

t_cmd endp

;--- trace one instruction

trace1 proc
if ?PM
	call getcsattr
	mov [bCSAttr],al
endif
if ?PM
	mov bx,[regs.rIP]
	mov ax,[regs.rCS]
	cmp bx,word ptr [dpmiwatch+0]	;catch the initial switch to protected mode
	jnz trace1_1
	cmp ax,word ptr [dpmiwatch+2]
	jnz trace1_1
	cmp [bNoHook2F],0	;current CS:IP is dpmi entry
	jz @F
	;if int 2fh is *not* hooked ( win3x, win9x, dosemu )
	mov [regs.rIP],offset mydpmientry
	mov [regs.rCS],cs
@@:
	push ss
	pop es		;run code until RETF
	push ds
	mov bx,[regs.rSP]
	mov ds,[regs.rSS]
	mov si,[bx+0]
	mov bx,[bx+2]
	pop ds
	call process1
	ret
trace1_1:
endif
	xor cx,cx
	call getcseipbyte
	cmp al,0CDh
	jnz isstdtrace
	inc cx
	call getcseipbyte
	cmp al,3
	jz isstdtrace
	test byte ptr [tmode], 1	;TM=1?
	jz trace_int
	cmp al,1
	jnz step_int
isstdtrace:
	or byte ptr [regs.rFL+1],1h	;set single-step mode
	xor cx,cx
	call getcseipbyte
	push ax
	call run
	pop ax
	cmp al,9Ch				;was opcode "PUSHF"?
	jnz @F
	call clear_tf_onstack
@@:
	cmp [run_int],offset int1msg
	je tt1_1
	jmp ue_int		;if some other interrupt
tt1_1:
	call dumpregs
	ret

; an INT is to be processed (TM is 0)
; to avoid the nasty x86 bug which makes IRET
; cause a debug exception 1 instruction too late
; a breakpoint is set behind the INT

; if the int will terminate the debuggee (int 21h, ah=4Ch)
; it is important that the breakpoint won't be restored!

trace_int:
	mov cx,2
	call iswriteablecseip	;is current CS:IP in ROM?
	jc isstdtrace			;then do standard trace
	mov bx,[regs.rCS]
if ?PM
	test [bCSAttr],40h
	jz $+3
	db 66h	;mov esi,dword ptr [regs.rIP]
endif
	mov si,[regs.rIP]
if ?PM
	jz $+3
	db 66h	;add esi,2
endif
	add si,2
	call process1		;set BP at BX:(E)SI and run debuggee
	ret

;--- current instruction is INT, TM is 1, single-step into the interrupt
;--- AL=int#

step_int:
	mov bl,al
if ?PM
	call ispm
	jnz step_int_pm
endif
	mov bh,0
	push ds
	xor ax,ax
	mov ds,ax
	shl bx,1		;stay 8086 compatible in real-mode!
	shl bx,1
	cli
	lds si,[bx+0]
	mov al,[si]
	xor byte ptr [si],0FFh
	cmp al,[si]
	mov [si],al
	sti
	jz isrom
	mov bx,ds
	pop ds
	call process1
	ret
isrom:
	mov  ax,ds
	pop  ds
	xchg si,[regs.rIP]
	xchg ax,[regs.rCS]
	mov  cx,[regs.rFL]
	push ds
	mov  bx,[regs.rSP]
	mov  ds,[regs.rSS]		;emulate an INT
	sub  bx,6
	inc  si 				;skip INT xx
	inc  si
	mov  [bx+0],si
	mov  [bx+2],ax
	mov  [bx+4],cx
	pop  ds
	mov  [regs.rSP],bx
	and  byte ptr [regs.rFL+1],0FCh  ;clear IF + TF
	jmp  tt1_1
if ?PM
step_int_pm:
	mov  ax,204h
	int  31h			;get vector in CX:(E)DX
	mov  bx,cx
	test bl,4			;is it a LDT selector?
	jnz  @F
	jmp  isstdtrace
@@:
	sizeprf		;mov  esi,edx
	mov  si,dx
	call process1
	ret

endif

trace1 endp

;--- test if memory at CS:E/IP can be written to
;--- return C if not
;--- IN: CX=offset for (E)IP

iswriteablecseip proc
	call getcseipbyte	;get byte ptr at CS:EIP+CX
	mov ah,al
	xor al,0FFh
	call setcseipbyte
	jc notwriteable
	call getcseipbyte
	cmp ah,al			;is it ROM?
	jz notwriteable
	mov al,ah
	call setcseipbyte
	clc
	ret
notwriteable:
	stc
	ret
iswriteablecseip endp

;--- clear TF in the copy of flags register onto the stack

clear_tf_onstack proc
	push es
	mov es,[regs.rSS]
if ?PM
	mov bx,es
	call getselattr
	jz @F
	.386
	mov ebx,dword ptr [regs.rSP]
	and byte ptr es:[ebx+1],not 1
	jmp ctos_1
	.8086
@@:
endif
	mov bx,[regs.rSP]
	and byte ptr es:[bx+1],not 1
ctos_1:
	pop es
	ret
clear_tf_onstack endp

;--- Print message about unexpected interrupt, dump registers, and end
;--- command.  This code is also used by the G and P commands.

ue_int:
	mov dx,[run_int]
	call int21ah9	;print string
	cmp dx,offset progtrm
	je @F			;if it terminated, skip the registers
	call dumpregs
@@:
	jmp cmdloop		;back to the start

if ?PM or CATCHINT07

;--- unexpected exception occured inside debugger

ue_intx proc
	cld
	push ss
	pop ds
	call unhack		;set debugger's int 23/24
	mov dx,[run_int]
	call int21ah9	;print string
if EXCCSIP
	mov di,offset line_out
	mov si,offset excloc
	call copystring
	mov ax,intexccs
	call hexword
	mov al,':'
	stosb
	mov ax,intexcip
	call hexword
	call putsline
endif
	jmp cmdloop
ue_intx endp

endif

;--- U command - disassemble.

u_cmd proc
	mov [lastcmd],offset lastuu	
	cmp al,CR
	jne uu1		;if an address was given
lastuu:
if ?PM
	call getcsattr
	mov [bCSAttr],al
	jz uu_0
	.386
	mov ecx,dword ptr [u_addr]
	add ecx,1Fh
	jnc @F
	mov ecx,-1
@@:
	inc ecx
uu3_32:
	push ecx
	push edx
	call disasm1
	pop ebx
	pop ecx
	mov eax,dword ptr [u_addr]
	mov edx,eax
	sub eax,ecx		;current position - end
	sub ebx,ecx		;previous position - end
	cmp eax,ebx
	jnb uu3_32		;if we haven't reached the goal
	ret
	.8086
uu_0:
endif
	mov cx,word ptr [u_addr]
	add cx,1fh
	jnc uu2		;if no overflow
	mov cx,-1
	jmp uu2

uu1:
	mov cx,20h		;default length
	mov bx,[regs.rCS]
	call getrangeX	;get address range into bx:(e)dx
	call chkeol		;expect end of line here
	sizeprfX		;mov [u_addr+0],edx
	mov [u_addr+0],dx
	mov [u_addr+4],bx

;--- At this point, cx holds the last address, and dx the address.

uu2:
	inc cx
uu3:
	push cx
	push dx
	call disasm1	;do it
	pop bx
	pop cx
	mov ax,[u_addr]
	mov dx,ax
	sub ax,cx		;current position - end
	sub bx,cx		;previous position - end
	cmp ax,bx
	jnb uu3		;if we haven't reached the goal
	ret
u_cmd endp


lockdrive:
	push ax
	push bx
	push cx
	push dx
	mov bl,al
	inc bl
	mov bh,0
	mov cx,084Ah
	mov dx,0001h
	mov ax,440Dh
	int 21h
	pop dx
	pop cx
	pop bx
	pop ax
	ret
unlockdrive:
	push ax
	push bx
	push cx
	push dx
	mov bl,al
	inc bl
	mov bh,0
	mov cx,086Ah
	mov dx,0001h
	mov ax,440Dh
	int 21h
	pop dx
	pop cx
	pop bx
	pop ax
	ret

;--- W command - write a program, or disk sectors, to disk.

w_cmd proc
	call parselw	;parse L and W argument format (out: bx:(e)dx=address)
	jz write_file	;if request to write program
if NOEXTENDER
	call ispm
	jz @F
	call isextenderavailable	;in protected-mode, DOS translation needed
	jnc @F
	mov dx,offset nodosext
	jmp int21ah9
@@:
endif
	cmp cs:[usepacket],2
	jb ww0_1
	mov dl,al		;A=0,B=1,C=2,...
	mov si,6001h	;write, assume "file data"
if VDD
	mov ax,[hVdd]
	cmp ax,-1
	jnz callvddwrite
endif
	inc dl			;A=1,B=2,C=3,...
	call lockdrive
	mov ax,7305h	;DS:(E)BX->packet
	stc
	int 21h			;use int 21h here, not doscall
	pushf
	call unlockdrive
	popf
	jmp ww0_2
if VDD
callvddwrite:
	mov cx,5
	add cl,[dpmi32]
	DispatchCall
	jmp ww0_2
endif
ww0_1:
	int 26h
ww0_2:
	mov dx,offset writing
ww1::				;<--- entry from ll
	mov bx,ss		;restore segment registers
	mov ds,bx
	mov sp,[top_sp]
	mov es,bx
	jnc ww3		;if no error
	cmp al,0ch
	jbe @F		;if in range
	mov al,0ch
@@:
	cbw
	shl ax,1
	xchg si,ax
	mov al,[si+dskerrs]
	mov si,offset dskerr0
	add si,ax
	mov di,offset line_out
	call copystring	;si->di
	mov si,dx
	call copystring	;si->di
	mov si,offset drive
	call copystring	;si->di
	mov al,driveno
	add al,'A'
	stosb
	call putsline
ww3:
	jmp cmdloop		;can't ret because stack is wrong

w_cmd endp

;--- Write to file.  First check the file extension.
;--- size of file is in client's BX:CX, 
;--- default start address is DS:100h

write_file proc
if DRIVER
	jmp cmd_error
else
	mov al,[fileext]	;get flags of file extension
	test al,EXT_EXE + EXT_HEX
	jz @F				;if not EXE or HEX
	mov dx,offset nowhexe
	jmp ww6
@@:
	cmp al,0
	jnz ww7		;if extension exists
	mov dx,offset nownull
ww6:
	jmp int21ah9

;--- File extension is OK; write it.  First, create the file.

ww7:
if ?PM
	call ispm
	jz @F
	mov dx,offset nopmsupp	;cant write it in protected-mode
	jmp int21ah9
@@:
endif
	mov bp,offset line_out
	cmp dh,0feh
	jb @F			;if dx < fe00h
	sub dh,0feh		;dx -= 0xfe00
	add bx,0fe0h
@@:
	mov [bp+10],dx	;save lower part of address in line_out+10
	mov si,bx		;upper part goes into si
	mov ah,3ch		;create file
	xor cx,cx		;no attributes
	mov dx,DTA
	call doscall
	jc io_error		;if error
	push ax			;save file handle

;--- Print message about writing.

	mov dx,offset wwmsg1
	call int21ah9	;print string
	mov ax,[regs.rBX]
	cmp ax,10h
	jb @F			;if not too large
	xor ax,ax		;too large:  zero it out
@@:
	mov [bp+8],ax
	or ax,ax
	jz @F
	call hexnyb		;convert to hex and print
@@:
	mov ax,[regs.rCX]
	mov [bp+6],ax
	call hexword
	call puts		;print size
	mov dx,offset wwmsg2
	call int21ah9	;print string

;--- Now write the file.  Size remaining is in line_out+6.

	pop bx			;recover file handle
	mov dx,[bp+10]	;address to write from is si:dx
ww11:
	mov ax,0fe00h
	sub ax,dx
	cmp byte ptr [bp+8],0
	jnz @F			;if more than 0fe00h bytes remaining
	cmp ax,[bp+6]
	jb @F			;ditto
	mov ax,[bp+6]
@@:
	xchg ax,cx		;mov cx,ax
	mov ds,si
	mov ah,40h		;write to file
	int 21h			;use INT, not doscall
	push ss			;restore DS
	pop ds
	cmp ax,cx
	jne ww13		;if disk full
	xor dx,dx		;next time write from xxxx:0
	add si,0fe0h	;update segment pointer
	sub [bp+6],cx
	lahf
	sbb byte ptr [bp+8],0
	jnz ww11		;if more to go
	sahf
	jnz ww11		;ditto
	jmp ww14		;done

ww13:
	mov dx,offset diskful
	call int21ah9	;print string
	mov ah,41h		;unlink file
	mov dx,DTA
	call doscall

;--- Close the file.

ww14:
	mov ah,3eh		;close file
	int 21h
	ret
endif
write_file endp

;--- Error opening file.  This is also called by the load command.

io_error:
	cmp ax,2
	mov dx,offset doserr2	;File not found
	je @F
	cmp ax,3
	mov dx,offset doserr3	;Path not found
	je @F
	cmp ax,5
	mov dx,offset doserr5	;Access denied
	je @F
	cmp ax,8
	mov dx,offset doserr8	;Insufficient memory
	je @F
	mov di,offset openerr1
	call hexword
	mov dx,offset openerr	;Error ____ opening file
@@:
int21ah9::
	mov ah,9
	call doscall
	ret

if EMSCMD

;--- X commands - manipulate EMS memory.

;--- XA - Allocate EMS.

xa proc
	call emschk
	call skipcomma
	call getword		;get argument into DX
	call chkeol			;expect end of line here
	mov bx,dx
	mov ah,43h			;allocate handle
	and bx,bx
	jnz @F
	mov ax,5A00h		;use the EMS 4.0 version to alloc 0 pages
@@:
	call emscall
	push dx
	mov si,offset xaans
	call copystring
	pop ax
	call hexword
	jmp putsline	;print string and return
xa endp

;--- XD - Deallocate EMS handle.

xd proc

	call emschk
	call skipcomma
	call getword	;get argument into DX
	call chkeol		;expect end of line here
	mov ah,45h		;deallocate handle
	call emscall
	push dx
	mov si,offset xdans
	call copystring
	pop ax
	call hexword
	jmp putsline	;print string and return

xd endp

;--- x main dispatcher

x_cmd proc
	cmp al,'?'
	je xhelp		;if a call for help
	or al,TOLOWER
	cmp al,'a'
	je xa		;if XA command
	cmp al,'d'
	je xd		;if XD command
	cmp al,'r'
	je xr		;if XR command
	cmp al,'m'
	je xm		;if XM command
	cmp al,'s'
	je xs		;if XS command
	jmp cmd_error

xhelp:
	mov dx,offset xhelpmsg
	mov cx,size_xhelpmsg
	jmp stdout	;print string and return
x_cmd endp

;--- XR - Reallocate EMS handle.

xr proc
	call emschk
	call skipcomma
	call getword		;get handle argument into DX
	mov bx,dx
	call skipcomma
	call getword		;get count argument into DX
	call chkeol			;expect end of line here
	xchg bx,dx
	mov ah,51h			;reallocate handle
	call emscall
	mov si,offset xrans
	call copystring
	jmp putsline		;print string and return

xr endp

;--- XM - Map EMS memory to physical page.

xm proc
	call emschk
	call skipcomma
	call getword	;get logical page (FFFF means unmap)
	mov bx,dx		;save it in BX
	call skipcomm0
	call getbyte	;get physical page (DL)
	push dx
	call skipcomm0
	call getword	;get handle into DX
	call chkeol		;expect end of line
	pop ax			;recover physical page into AL
	push ax
	mov ah,44h		;function 5 - map memory
	call emscall
	mov si,offset xmans
	call copystring
	mov bp,di
	mov di,offset line_out + xmans_pos1
	xchg ax,bx		;mov ax,bx
	call hexword
	mov di,offset line_out + xmans_pos2
	pop ax
	call hexbyte
	mov di,bp
	jmp putsline	;print string and return

xm endp

;--- XS - Print EMS status.

xs proc
	call emschk
	lodsb
	call chkeol		;no arguments allowed

;   First print out the handles and handle sizes.  This can be done either
;   by trying all possible handles or getting a handle table.
;   The latter is preferable, if it fits in memory.

	mov ah,4bh		;function 12 - get handle count
	call emscall
	cmp bx,( real_end - line_out ) / 4
	jbe xs3			;if we can do it by getting the table

	xor dx,dx		;start handle
nexthdl:
	mov ah,4ch		;function 13 - get handle pages
	int 67h
	cmp ah,83h
	je xs2			;if no such handle
	or ah,ah
	jz @F
	jmp ems_err		;if other error
@@:
	xchg ax,bx		;mov ax,bx
	call hndlshow
xs2:
	inc dl			;end of loop
	jnz nexthdl		;if more to be done

	jmp xs5			;done with this part

;--- Get the information in tabular form.

xs3:
	mov ah,4dh		;function 14 - get all handle pages
	mov di,offset line_out
	call emscall
	and bx,bx		;has returned no of entries in BX
	jz xs5
	mov si,di
@@:
	lodsw
	xchg ax,dx
	lodsw
	call hndlshow
	dec bx
	jnz @B		;if more to go

xs5:
	mov dx,offset crlf
	call int21ah9	;print string

;   Next print the mappable physical address array.
;   The size of the array shouldn't be a problem.

	mov ax,5800h	;function 25 - get mappable phys. address array
	mov di,offset line_out	;address to put array
	call emscall
	mov dx,offset xsnopgs
	jcxz xs7		;NO mappable pages!

	mov si,di
xs6:
	push cx
	lodsw
	mov di,offset xsstr2b
	call hexword
	lodsw
	mov di,offset xsstr2a
	call hexbyte
	mov dx,offset xsstr2
	mov cx,size_xsstr2
	call stdout		;print string
	pop cx			;end of loop
	test cl,1
	jz @F
	mov dx,offset crlf		;blank line
	call int21ah9	;print string
@@:
	loop xs6
	mov dx,offset crlf		;blank line
xs7:
	call int21ah9	;print string

;--- Finally, print the cumulative totals.

	mov ah,42h		;function 3 - get unallocated page count
	call emscall
	mov ax,dx		;total pages available
	sub ax,bx		;number of pages allocated
	mov bx,offset xsstrpg
	call sumshow	;print the line
	mov ah,4bh		;function 12 - get handle count
	call emscall
	push bx

;--- try EMS 4.0 function 5402h to get total number of handles

	mov ax,5402h
	int 67h         ;don't use emscall, this function may fail!
	mov dx,bx
	cmp ah,0
	jz @F
	mov dx,0ffh		;total number of handles
@@:
	pop ax			;ax = number of handles allocated
	mov bx,offset xsstrhd
	call sumshow	;print the line
	ret				;done

xs endp

;--- Call EMS

emscall proc
if ?PM
	call ispm
	jz ems_rm
	.286
	invoke intcall, 67h, cs:[pspdbg]
	jmp ems_call_done
	.8086
ems_rm:
endif
	int 67h
ems_call_done:
	and ah,ah	;error?
	js ems_err
	ret			;return if OK

emscall endp

;--- ems error in AH

ems_err proc
	mov al,ah
	cmp al,8bh
	jg ce2		;if out of range
	cbw
	mov bx,ax
	shl bx,1
	mov si,[emserrs+100h+bx]
	or si,si
	jnz ce3		;if there's a word there
ce2:
	mov di,offset emserrxa
	call hexbyte
	mov si,offset emserrx
ce3:
	mov di,offset line_out
	call copystring	;si->di
	call putsline
	jmp cmdloop

ems_err endp

;--- Check for EMS

emschk proc
if ?PM
	call ispm
	jz emschk1
	mov bl,67h
	mov ax,0200h
	int 31h
	mov ax,cx
	or ax,dx
	jz echk2
	jmp emschk2
emschk1:
endif
	push es
	mov ax,3567h	;get interrupt vector 67h
	int 21h
	mov ax,es
	pop es
	or ax,bx
	jz echk2
emschk2:
	mov ah,46h		;get version
;	int 67h
	call emscall
	and ah,ah
	jnz echk2
	ret
echk2:
	mov si,offset emsnot
	call copystring
	call putsline
	jmp cmdloop
emschk endp

;--- HNDLSHOW - Print XS line giving the handle and pages allocated.
;
;--- Entry   DX Handle
;            AX Number of pages
;
;    Exit    Line printed
;
;    Uses    ax,cl,di.

hndlshow proc
	mov di,offset xsstr1b
	call hexword
	mov ax,dx
	mov di,offset xsstr1a
	call hexword
	push dx
	mov dx,offset xsstr1
	mov cx,size_xsstr1
	call stdout
	pop dx
	ret
hndlshow endp

;--- SUMSHOW - Print summary line for XS command.
;
;---Entry    AX Number of xxxx's that have been used
;            DX Total number of xxxx's
;            BX Name of xxxx
;
;   Exit     String printed
;
;   Uses     AX, CX, DX, DI

sumshow proc
	mov di,offset line_out
	call trimhex
	mov si,offset xsstr3
	call copystring
	xchg ax,dx		;mov ax,dx
	call trimhex
	mov si,offset xsstr3a
	call copystring
	mov si,bx
	call copystring
	mov si,offset xsstr3b
	call copystring
	jmp putsline

sumshow endp

;   TRIMHEX - Print word without leading zeroes.
;
;   Entry    AX Number to print
;            DI Where to print it
;
;   Uses     AX, CX, DI.

trimhex proc
	call hexword
	push di
	sub di,4		;back up DI to start of word
	mov cx,3
	mov al,'0'
@@:
	scasb
	jne @F			;return if not a '0'
	mov byte ptr [di-1],' '
	loop @B
@@:
	pop di
	ret
trimhex endp

endif

;--- syntax error handler.
;--- in: SI->current char in line_in

cmd_error proc
	mov cx,si
	sub cx,offset line_in+4
	add cx,[promptlen]
	mov di,offset line_out
	mov dx,di
	cmp cx,127
	ja @F			;if we're really messed up
	inc cx			;number of spaces to skip
	mov al,' '
	rep stosb
@@:
	mov si,offset errcarat
	mov cl,sizeof errcarat
	rep movsb
	call putsline	;print string
	jmp [errret]
cmd_error endp

;--- FREEMEM - cancel child process

freemem proc
	mov [regs.rCS],cs
	mov [regs.rIP],offset fmem2
if ?PM
	xor ax,ax
	mov [regs.rIP+2],ax
	mov [regs.rSP+2],ax
endif
	mov [regs.rSS],ss
	push ax
	mov [regs.rSP],sp	;save sp-2
	pop ax
	call run
	ret
fmem2:
	mov ax,4c00h	;quit
	int 21h
freemem endp

;--- this is called by "run"
;--- better don't use INTs inside
;--- set debuggee's INT 23/24

setint2324 proc
	mov si,offset run2324
if ?PM
	call ispm
	jnz si2324pm
endif
	push es

	xor di,di
	mov es,di
	mov di,23h*4
	movsw
	movsw
	movsw
	movsw

if ?PM
	call hook2f
endif

	pop es
	ret
if ?PM
si2324pm:
	mov bx,0223h
@@:
	sizeprf		;mov edx,[si+0]
	mov dx,[si+0]
	mov cx,[si+4]
	mov ax,205h
	int 31h
	add si,6
	inc bl
	dec bh
	jnz @B
	ret
endif
setint2324 endp

;--- This is the routine that starts up the running program.

run proc
	call seteq		;set CS:E/IP to '=' address
	mov bx,[pspdbe]
	call setpsp		;set debuggee's PSP
	call setint2324	;set debuggee's int 23/24

	mov [run_sp],sp	;save stack position
if DRIVER eq 0
	sub sp,[spadjust]
	mov ds:[SPSAV],sp
endif
	cli
	mov sp,offset regs
	cmp [machine],3
	jb no386
	.386
	popad
	mov fs,[regs.rFS]
	mov gs,[regs.rGS]
	jmp loadsegs
	.8086
no386:
	pop di
	pop si	;skip hi edi
	pop si
	pop bp	;skip hi esi
	pop bp
	add sp,6;skip hi ebp+reserved
	pop bx
	pop dx	;skip hi ebx
	pop dx
	pop cx	;skip hi edx
	pop cx
	pop ax	;skip hi ecx
	pop ax
	add sp,2;skip hi eax
loadsegs:
	pop es		;temporary load DS value into ES (to make sure it is valid)
	pop es		;now load the true value for ES
	pop ss
patch_movsp label byte		;patch with 3Eh (=DS:) if cpu < 386
	db 66h				;mov esp,[regs.rSP]
	mov sp,[regs.rSP]	;restore program stack
	mov [bInDbg],0
	sizeprf				;push dword ptr [regs.rFL]
	push [regs.rFL]
	sizeprf				;push dword ptr [regs.rCS]
	push [regs.rCS]
	sizeprf				;push dword ptr [regs.rIP]
	push [regs.rIP]
	test byte ptr [regs.rFL+1],2	;IF set?
	mov ds,[regs.rDS]
	jz @F
	sti				;required for ring3 protected mode if IOPL==0
@@:
patch_iret label byte
	db 66h			;patch with CFh (=IRET) if cpu < 386
	iret			;jump to program
run endp

;--- debugger's int 22h (program termination) handler.
;--- there's no need to preserve registers.

int22:
	cli
	mov cs:[run_int],offset progtrm	;remember interrupt type
	mov cs:[lastcmd],offset dmycmd
	mov ax,cs
	mov ss,ax
	mov ds,ax
	jmp intrtn1		;jump to register saving routine (sort of)

;--- Interrupt 0 (divide error) handler.

intr00:
	mov cs:[run_int],offset int0msg	;remember interrupt type
	jmp intrtn		;jump to register saving routine

;--- Interrupt 1 (single-step interrupt) handler.

intr01:
	mov cs:[run_int],offset int1msg	;remember interrupt type
	jmp intrtn		;jump to register saving routine

if CATCHINT06
intr06:
	mov cs:[run_int],offset exc06msg
	jmp intrtn
endif
if CATCHINT07
intr07:
	mov cs:[run_int],offset exc07msg
	cmp cs:[bInDbg],0
	jz @F
	push ax
	push bp
	mov bp,sp
	mov ax,[bp+4]
	mov cs:intexcip, ax
	mov ax,[bp+6]
	mov cs:intexccs, ax
	pop bp
	pop ax
	push cs
	pop ss
	mov sp,cs:[top_sp]
	jmp ue_intx
@@:
	jmp intrtn
endif

if CATCHINT0C
NotOurInt0C:
	jmp cs:[oldi0C]
intr0C:
	push ax
	mov al, 0Bh		; get ISR mask from PIC
	out 20h, al
	in al, 10h
	test al, 10h	; IRQ4 (int 0Ch) occured?
	pop ax
	jnz NotOurInt0C
	mov cs:[run_int],offset exc0Cmsg
	jmp intrtn
endif

if CATCHINT0D
NotOurInt0D:
	jmp cs:[oldi0D]
intr0D:
	push ax
	mov al, 0Bh		; get ISR mask from PIC
	out 20h, al
	in al, 20h
	test al, 20h	; IRQ5 (int 0Dh) occured?
	pop ax
	jnz NotOurInt0D
	cmp cs:[bInDbg],0
	jz @F
	push cs
	pop ss
	mov sp,cs:[top_sp]
	jmp ue_intx
@@:
	mov cs:[run_int],offset exc0Dmsg
	jmp intrtn
endif

;--- Interrupt 3 (breakpoint interrupt) handler.

intr03:
	mov cs:[run_int],offset int3msg	;remember interrupt type

;--- Common interrupt routine.

;--- Housekeeping.

intrtn proc
	cli						;just in case
	pop cs:[regs.rIP]		;recover things from stack
	pop cs:[regs.rCS]
	pop cs:[regs.rFL]
	mov cs:[regs.rSS],ss	;save stack position
	sizeprf
	mov cs:[regs.rSP],sp
	mov sp,cs				;mov ss,cs
	mov ss,sp
	mov sp,offset regs.rSS
intrtn2::			;<--- entry protected-mode
	push es
	push ds
	push ss
	pop ds
	cmp [machine],3
	jb @F
	.386
	mov [regs.rFS],fs
	mov [regs.rGS],gs

;--- regs.rDI+4 is dword aligned, so DWORD pushs are safe here

	pushfd
	popf		;skip LoWord(EFL)
	pop word ptr [regs.rFL+2]
	
	push 0
	pushf
	popfd		;clear HiWord(EFL) inside debugger (resets AC flag)

	pushad
	jmp intrtn1
	.8086
@@:
	push ax
	push ax
	push cx
	push cx
	push dx
	push dx
	push bx
	push bx
	sub sp,6
	push bp
	push si
	push si
	push di
	push di
intrtn1::		;<--- entry for int 22

	mov sp,[run_sp]		;restore running stack
	cld					;clear direction flag
	sti					;interrupts back on

if ?PM
	mov ax,1686h
	int 2Fh
	cmp ax,1
	sbb ax,ax
	mov [regs.msw],ax	;0000=real-mode, FFFF=protected-mode
endif

	call getpsp
	mov  [pspdbe],bx
	call getint2324		;save debuggee's int 23/24, set debugger's int 23/24

	push ds
	pop es
	call setpspdbg		;set debugger's PSP
	and byte ptr [regs.rFL+1],not 1	;clear single-step interrupt

	mov [bInDbg],1
	cmp [run_int],offset progtrm
	jnz @F
if ?PM
	mov [cssel],0		;reset flag 'initial switch has occured'
endif
	mov ah,4Dh
	int 21h
	mov di,offset progexit
	call hexword
@@:
	ret

intrtn endp

;--- this is low-level, called on entry into the debugger.
;--- the debuggee's registers have already been saved here.
;--- 1. get debuggee's interrupt vectors 23/24
;--- 2. set debugger's interrupt vectors 23/24
;--- DS=debugger's segment
;--- ES=undefined, will be modified
;--- Int 21h should not be used here!

getint2324 proc
	mov di,offset run2324
if ?PM
	call ispm
	jnz getint2324pm
endif

	push ds
	pop es
	xor si,si
	mov ds,si
	mov si,23h*4
	push si
	movsw		;save interrupt vector 23h
	movsw
	movsw		;save interrupt vector 24h
	movsw
	pop di
	push es
	pop ds
if DRIVER eq 0  ;the driver version has no PSP at 0-100h
	xor si,si
	mov es,si
	mov si,CCIV	;move from debugger's PSP to IVT
	movsw
	movsw
	movsw
	movsw
endif
	ret
if ?PM
getint2324pm:

	.286
	mov bx,0223h
@@:
	mov ax,204h
	int 31h
	sizeprf	;mov [di+0],edx
	mov [di+0],dx
	mov [di+4],cx
	add di,6
	inc bl
	dec bh
	jnz @B

setdbgI2324::		;<--- entry
	sizeprf		;pushad
	pusha
	sizeprf		;xor edx, edx
	xor dx,dx
	mov si,offset dbg2324
	mov bx,0223h
@@:
	lodsw
	mov dx,ax
	mov cx,cs
	mov ax,205h
	int 31h
	inc bl
	dec bh
	jnz @B
	sizeprf		;popad
	popa
	ret
	.8086

endif

getint2324 endp

;   The next three subroutines concern the handling of INT 23 and 24.
;   These interrupt vectors are saved and restored when running the
;   child process, but are not active when DEBUG itself is running.
;   It is still useful for the programmer to be able to check where INT 23
;   and 24 point, so these values are copied into the interrupt table
;   during parts of the c, d, e, m, and s commands, so that they appear
;   to be in effect.  The e command also copies these values back.
;   Between calls to dohack and unhack, there should be no calls to DOS,
;   so that there is no possibility of these vectors being used when
;   the child process is not running.

;   PREPHACK - Set up for interrupt vector substitution.
;   save current value of Int 23/24 (debugger's) to save2324
;   Entry   es = cs

prephack proc
	cmp [hakstat],0
	jnz @F					;if hack status error
	push di
	mov di,offset sav2324	;debugger's Int2324
	call prehak1
	pop di
	ret
@@:
	push ax
	push dx
	mov dx,offset ph_msg	;'error in sequence of calls to hack'
	call int21ah9	;print string
	pop dx
	pop ax
	ret
prephack endp

;--- get current int 23/24, store them at ES:DI
;--- DI is either sav2324 (debugger's) or run2324 (debuggee's)

prehak1:
if ?PM
	call ispm
	jnz prehak_pm	;nothing to do
endif
	push ds
	push si
	xor si,si
	mov ds,si
	mov si,4*23h
	movsw
	movsw
	movsw
	movsw
	pop si
	pop ds
prehak_pm:
	ret

CONST segment
ph_msg	db 'Error in sequence of calls to hack.',CR,LF,'$'
CONST ends

;   DOHACK - set debuggee's int 23/24
;   UNHACK - set debugger's int 23/24
;       It's OK to do either of these twice in a row.
;       In particular, the 's' command may do unhack twice in a row.
;   Entry   ds = debugger's segment
;   Exit    es = debugger's segment

dohack proc
	push si
	mov [hakstat],1
	mov si,offset run2324	;debuggee's interrupt vectors
if ?PM
	call ispm
	jnz dohack_pm
endif
	jmp hak1

if ?PM
restdbgi2324:			;set debugger's int 23/24 in PM
	call setdbgI2324
	push ss
	pop es
	ret
endif

unhack::				;set debugger's int 23/24, set ES to debugger segment
	mov [hakstat],0
if ?PM
	call ispm
	jnz restdbgi2324
endif
	push si
	mov si,offset sav2324	;debugger's interrupt vectors
hak1:
	push di
	xor di,di
	mov es,di
	mov di,4*23h
	movsw
	movsw
	movsw
	movsw
	pop di
	pop si
	push cs
	pop es
	ret
if ?PM

;--- set debuggee's int 23/24 pmode

dohack_pm:
	.286
	push ss
	pop es
	sizeprf
	pusha
	mov bx,0223h
@@:
	sizeprf		;mov edx,[si+0+0]
	mov dx,[si+0+0]
	mov cx,[si+0+4]
	mov ax,205h
	int 31h
	add si,6
	inc bl
	dec bh
	jnz @B
	sizeprf
	popa
	pop si
	ret
	.8086
endif
dohack endp

InDos:
	push ds
	push si
if ?PM
	call ispm
	mov si,word ptr [pInDOS+0]
	mov ds, [InDosSel]
	jnz @F
	mov ds, word ptr cs:[pInDOS+2]
@@:
else
	lds si,[pInDOS]
endif
	cmp byte ptr [si],0
	pop si
	pop ds
	ret

stdoutal:
	push cx
	push dx
	push ax
	mov cx,1
	mov dx,sp
	call stdout
	pop ax
	pop dx
	pop cx
	ret

fullbsout:
	mov al,8
	call stdoutal
	mov al,20h
	call stdoutal
	mov al,8
	jmp stdoutal

;   GETLINE - Print a prompt (address in DX, length in CX) and read a line
;   of input.
;   GETLINE0 - Same as above, but use the output line (so far), plus two
;   spaces and a colon, as a prompt.
;   GETLINE00 - Same as above, but use the output line (so far) as a prompt.
;   Entry   CX  Length of prompt (getline only)
;       DX  Address of prompt string (getline only)
;
;       DI  Address + 1 of last character in prompt (getline0 and
;           getline00 only)
;
;   Exit    AL  First nonwhite character in input line
;       SI  Address of the next character after that
;   Uses    AH,BX,CX,DX,DI

getline0:
	mov ax,'  '		;add two spaces and a colon
	stosw
	mov al,':'
	stosb
getline00:
	mov dx,offset line_out
	mov cx,di
	sub cx,dx

getline proc
	mov [promptlen],cx	;save length of prompt
if DRIVER eq 0
	call bufsetup
	pushf
endif
	call stdout ;write prompt (string DX, size CX)
if DRIVER eq 0
	popf
	jc gl5		;if tty input
	mov [lastcmd],offset dmycmd

;   This part reads the input line from a file (in the case of
;   'debug < file').  It is necessary to do this by hand because DOS
;   function 0ah does not handle EOF correctly otherwise.  This is
;   especially important for debug because it traps Control-C.

gl1:
	mov cx,[bufend]
	sub cx,si		;cx = number of valid characters
	jz gl3		;if none
@@:
	lodsb
	cmp al,CR
	je gl4		;if end of line
	cmp al,LF
	je gl4		;if eol
	stosb
	loop @B		;if there are more valid characters
gl3:
	call fillbuf
	jnc gl1		;if we have more characters
	mov al,LF
	cmp di,offset line_in+LINE_IN_LEN
	jb gl4
	dec si
	dec di
gl4:
	mov [bufnext],si
	mov [notatty],al
	mov al,CR
	stosb
	mov cx,di
	mov dx,offset line_in + 2
	sub cx,dx
	call stdout	;print out the received line
	jmp gl6		;done
gl5:
endif
	mov dx,offset line_in
	call InDos
	jnz rawinput
	mov ah,0ah		;buffered keyboard input
	call doscall
gl6:
	mov al,10
	call stdoutal
	mov si,offset line_in + 2
	call skipwhite
	ret

rawinput:
	push di
	push ds
	pop es
	inc dx
	inc dx
	mov di,dx
rawnext:
	mov ah,00h
	int 16h
	cmp al,0
	jz rawnext
	cmp al,0E0h
	jz rawnext
	cmp al,08h
	jz del_key
	cmp al,7Fh
	jz del_key
	stosb
	call stdoutal
	cmp al,0Dh
	jnz rawnext
	dec di
	sub di,dx
	mov ax,di
	mov di,dx
	mov byte ptr [di-1],al
	dec dx
	dec dx
	pop di
	jmp gl6
del_key:
	cmp di,dx
	jz rawnext
	dec di
	call fullbsout
	jmp rawnext

getline endp

;   BUFSETUP - Set up buffer reading.  This just means discard an LF
;   if the last character read (as stored in 'notatty') is CR.
;   Entry   DI  First available byte in input buffer
;   Exit    SI  Address of next character.
;   If the input is from a tty, then bufsetup returns with carry set.

if DRIVER eq 0

bufsetup proc
	cmp [notatty],0
	jnz bs1		;if not a tty
	stc
	ret

bs1:
	mov di,offset line_in+2
	mov si,[bufnext]
	cmp si,[bufend]
	jb bs2		;if there's a character already
	call fillbuf
	jc bs4		;if eof
bs2:
	cmp [notatty],CR
	jne bs3		;if nothing more to do
	cmp byte ptr [si],LF
	jne bs3		;if not a line feed
	inc si		;skip it
bs3:
	clc
	ret

bs4:
	jmp q_cmd	;quit:  we've hit an eof

bufsetup endp

endif

;   FILLBUF - Fill input buffer.  Mostly this is an internal routine
;   for getline.
;   Entry   DI  First available byte in input buffer
;   Exit    SI  Next readable byte (i.e., equal to DI)
;       Carry flag is set if and only if there is an error (e.g., eof)
;   Uses    None.

fillbuf proc
	push ax
	push bx
	push cx
	push dx
	mov si,di		;we know this already
	mov ah,3fh		;read from file
	xor bx,bx
	mov cx,offset line_in+LINE_IN_LEN
	mov dx,di
	sub cx,dx
	jz fb1			;if no more room
	call doscall
	jc fb1			;if error
	or ax,ax
	jz fb1			;if eof
	add ax,dx
	clc
	jmp fb2

fb1:
	xchg ax,dx		;ax = last valid byte address + 1
	stc

fb2:
	mov [bufend],ax
	pop dx
	pop cx
	pop bx
	pop ax
	ret
fillbuf endp

;   PARSECM - Parse command line for C and M commands.
;   Entry   AL          First nonwhite character of parameters
;           SI          Address of the character after that
;   Exit    DS:(E)SI    Address from first parameter
;           ES:(E)DI    Address from second parameter
;           (E)CX       Length of address range minus one

parsecm proc
	call prephack
	mov bx,[regs.rDS]	;get source range
	xor cx,cx
	call getrange	;get address range into bx:(e)dx bx:(e)cx
	push bx			;save segment first address
if ?PM
	cmp [bAddr32],0
	jz @F
	.386
	sub ecx,edx
	push edx		;save offset first address
	push ecx
	jmp pc_01
	.8086
@@:
endif
	sub cx,dx		;number of bytes minus one
	push dx
	push cx
pc_01:
	call skipcomm0
	mov bx,[regs.rDS]
if ?PM
	cmp [bAddr32],0
	jz pc_1
	.386
	call getaddr		;get address into bx:(e)dx
	mov [bAddr32],1		;restore bAddr32
	pop ecx
	mov edi,ecx
	add edi,edx
	jc errorj7
	call chkeol
	mov edi,edx
	mov es,bx
	pop esi
	pop ds
	ret
	.8086
pc_1:
endif
	call getaddr	;get destination address into bx:(e)dx
	pop cx
	mov di,cx
	add di,dx
	jc errorj7		;if it wrapped around
	call chkeol		;expect end of line
	mov di,dx
	mov es,bx
	pop si
	pop ds
	ret
parsecm endp

errorj7:
	jmp cmd_error

;   PARSELW - Parse command line for L and W commands.
;
;   Entry   AL  First nonwhite character of parameters
;       SI  Address of the character after that
;
;   Exit    If there is at most one argument (program load/write), then the
;       zero flag is set, and registers are set as follows:
;       bx:(e)dx    Transfer address
;
;       If there are more arguments (absolute disk read/write), then the
;       zero flag is clear, and registers are set as follows:
;
;       DOS versions prior to 3.31:
;       AL  Drive number
;       CX  Number of sectors to read
;       DX  Beginning logical sector number
;       DS:BX   Transfer address
;
;       Later DOS versions:
;       AL  Drive number
;       BX  Offset of packet
;       CX  0FFFFh

parselw proc
	mov bx,[regs.rCS]	;default segment
	mov dx,100h		;default offset
	cmp al,CR
	je plw2			;if no arguments
	call getaddr	;get buffer address into bx:(e)dx
	call skipcomm0
	cmp al,CR
	je plw2			;if only one argument
	push bx			;save segment
	push dx			;save offset
	mov bx,80h		;max number of sectors to read
	neg dx
	jz plw1			;if address is zero
	mov cl,9
	shr dx,cl		;max number of sectors which can be read
	mov di,dx
plw1:
	call getbyte	;get drive number (DL)
	call skipcomm0
	push dx
;	add dl,'A'
	mov [driveno],dl
	call getdword	;get relative sector number
	call skipcomm0
	push bx			;save sector number high
	push dx			;save sector number low
	push si			;in case we find an error
	call getword	;get sector count
	dec dx
	cmp dx,di
	jae errorj7		;if too many sectors
	inc dx
	mov cx,dx
	call chkeol		;expect end of line
	cmp [usepacket],0
	jnz plw3		;if new-style packet called for
	pop si			;in case of error
	pop dx			;get LoWord starting logical sector number 
	pop bx			;get HiWord 
	or bx,bx		;just a 16bit sector number possible
	jnz errorj7		;if too big
	pop ax			;drive number
	pop bx			;transfer buffer ofs
	pop ds			;transfer buffer seg
	or cx,cx		;set nonzero flag
plw2:
	ret

;--- new style packet, [usepacket] != 0

plw3:
	pop bx			;discard si
	mov bx,offset packet
	pop word ptr [bx].PACKET.secno+0
	pop word ptr [bx].PACKET.secno+2
	mov [bx].PACKET.numsecs,cx
	pop ax			;drive number
	pop word ptr [bx].PACKET.dstofs
	pop dx
	xor cx,cx
if ?PM
	call ispm
	jz @F
	cmp [dpmi32],0
	jz @F
	.386
	mov [bx].PACKET32.dstseg,dx
	movzx ebx,bx
	shr edx,16		;get HiWord(offset)
	cmp [bAddr32],1
	jz @F
	xor dx,dx
	.8086
@@:
endif
	mov [bx].PACKET.dstseg,dx	;PACKET.dstseg or HiWord(PACKET32.dstofs)
	dec cx			;set nonzero flag and make cx = -1
	ret
parselw endp

;   PARSE_PT - Parse 'p' or 't' command.
;   Entry   AL  First character of command
;       SI  Address of next character
;   Exit    CX  Number of times to repeat
;   Uses    AH,BX,CX,DX.

parse_pt proc
	call parseql	;get optional <=addr> argument
	call skipcomm0	;skip any white space
	mov cx,1		;default count
	cmp al,CR
	je @F			;if no count given
	call getword
	call chkeol		;expect end of line here
	mov cx,dx
	jcxz errorj10	;must be at least 1
@@:
;	call seteq		;make the = operand take effect
	ret
parse_pt endp

;   PARSEQL - Parse '=' operand for 'g', 'p' and 't' commands.
;   Entry   AL  First character of command
;           SI  Address of next character
;   Exit    AL  First character beyond range
;           SI  Address of the character after that
;           eqflag  Nonzero if an '=' operand was present
;           eqladdr Address, if one was given
;   Uses AH,BX,CX,(E)DX.

parseql proc
	mov [eqflag],0	;mark '=' as absent
	cmp al,'='
	jne peq1		;if no '=' operand
	call skipwhite
	mov bx,[regs.rCS]	;default segment
if ?PM
	sizeprf
	xor dx,dx
endif
	call getaddrX	;get the address into bx:(e)dx
	sizeprfX		;mov [eqladdr+0],edx
	mov [eqladdr+0],dx
	mov [eqladdr+4],bx
	inc [eqflag]
peq1:
	ret
parseql endp

;   SETEQ - Copy the = arguments to their place, if appropriate.  (This
;   is not done immediately, because the 'g' command may have a syntax
;   error.)
;   Uses AX.

seteq proc
	cmp [eqflag],0		;'=' argument given?
	jz @F
	sizeprfX			;mov eax,[eqladdr+0]
	mov ax,[eqladdr+0]
	sizeprfX			;mov [regs.rIP+0],eax
	mov [regs.rIP+0],ax
	mov ax,[eqladdr+4]
	mov [regs.rCS],ax
	mov [eqflag],0		;clear the flag
@@:
	ret
seteq endp

;--- get a valid offset for segment in BX

getofsforbx proc
if ?PM
	push ax		;needed?
	call getselattr
	pop ax
	jz gofbx_2
	.386
	mov [bAddr32],1
	push bx
	call getdword
	push bx
	push dx
	pop edx
	pop bx
	ret
	.8086
gofbx_2:
endif
	call getword
	ret
getofsforbx endp

errorj10:
	jmp cmd_error

;--- a range is entered with the L/ength argument
;--- get a valid length for segment in BX
;--- L=0 means 64 kB (at least in 16bit mode)

getlenforbx proc
if ?PM
	call ispm
	jz glfbx_1
	cmp [machine],3
	jb glfbx_1
	.386
	push ecx
	lar ecx,ebx
	test ecx,400000h	;is segment 32bit?
	pop ecx
	jz glfbx_1
	push dx
	push bx
	call getdword
	push bx
	push dx
	pop ecx
	pop bx
	pop dx
	stc
	jecxz glfbx_2
	dec ecx
	add ecx, edx
	ret
	.8086
glfbx_1:
endif
	push dx
	call getword
	mov cx,dx
	pop dx
;   stc
;	jcxz glfbx_2	;0 means 64k
	dec cx
	add cx,dx		;C if it wraps around
glfbx_2:
	ret
getlenforbx endp

;   GETRANGE - Get address range from input line.
;    a range consists of either start and end address
;    or a start address, a 'L' and a length.
;   Entry   AL  First character of range
;       SI  Address of next character
;       BX  Default segment to use
;       CX  Default length to use (or 0 if not allowed)
;   Exit    AL  First character beyond range
;       SI  Address of the character after that
;       BX:(E)DX    First address in range
;       BX:(E)CX    Last address in range
;   Uses    AH

getrangeX:
	push cx
	call getaddrX
	jmp getrange_1

getrange proc
	push cx			;save the default length
	call getaddr	;get address into bx:(e)dx (sets bAddr32)
getrange_1::		;<-- entry getrangeX
	push si
	call skipcomm0
	cmp al,' '
	ja gr2
	pop si			;restore si and cx
	pop cx
	jcxz errorj10	;if a range is mandatory
if ?PM
	cmp [bAddr32],0	;can be 1 only on a 80386+
	jz @F
	.386
	dec ecx
	add ecx,edx
	jnc gr1			;if no wraparound
	or ecx,-1		;go to end of segment
	jmp gr1
@@:
endif
	dec cx
	add cx,dx
	jnc gr1			;if no wraparound
	mov cx,0ffffh	;go to end of segment
gr1:
	dec si			;restore al
	lodsb
	ret

gr2:
	or al,TOLOWER
	cmp al,'l'
	je gr3			;if a range is given
;	call skipwh0	;get next nonblank
if ?PM
	cmp [machine],3
	jb gr2_1
	.386
	push edx
	call getofsforbx
	mov ecx,edx
	pop edx
	cmp edx,ecx
	ja errorj2
	jmp gr4
	.8086
gr2_1:
endif
	push dx
	call getword
	mov cx,dx
	pop dx
	cmp dx,cx
	ja errorj2			;if empty range
	jmp gr4

gr3:
	call skipcomma		;discard the 'l'
	call getlenforbx
	jc errorj2
gr4:
	add sp,4			;discard saved cx, si
	ret
getrange endp

errorj2:
	jmp cmd_error

;   GETADDR - Get address from input line.
;   Entry   AL  First character of address
;       SI  Address of next character
;       BX  Default segment to use
;   Exit    AL  First character beyond address
;       SI  Address of the character after that
;       BX:(E)DX    Address found
;   Uses    AH,CX

;--- entry getaddrX differs from getaddr in that BX isn't made
;--- writeable in pmode

getaddr proc
if ?PM
	mov dx,offset verifysegm	;make BX a writeable segment
	push dx
endif
getaddrX::
if ?PM
	mov [bAddr32],0
	cmp byte ptr [si-1],'$' ;a real-mode segment?
	jnz ga1_1
	lodsb
	call ispm
	jz ga1_1
	call getword
	mov bx,dx
	push ax
	mov ax,2
	int 31h
	jc errorj2
	mov bx,ax
	mov dx,ax
	pop ax
	jmp ga1_2
endif
ga1_1:
	call getofsforbx
ga1_2:
	push si
	call skipwh0
	cmp al,':'
	je ga2		;if this is a segment descriptor
	pop si
	dec si
	lodsb
	ret

ga2:
	pop ax		;throw away saved si
	mov bx,dx	;mov segment into BX
ga3:
	call skipwhite	;skip to next word
	call getofsforbx
	ret
getaddr endp

;   GETSTR - Get string of bytes.  Put the answer in line_out.
;   Entry   AL first character
;           SI address of next character
;   Exit    [line_out] first byte of string
;           DI address of last+1 byte of string
;   Uses    AX,CL,DL,SI

getstr proc
	mov di,offset line_out
	cmp al,CR
	je errorj2		;we don't allow empty byte strings
gs1:
	cmp al,"'"
	je gs2		;if string
	cmp al,'"'
	je gs2		;ditto
	call getbyte;byte in DL
	mov [di],dl	;store the byte
	inc di
	jmp gs6

gs2:
	mov ah,al	;save quote character
gs3:
	lodsb
	cmp al,ah
	je gs5		;if possible end of string
	cmp al,CR
	je errorj2	;if end of line
gs4:
	stosb		;save character and continue
	jmp gs3

gs5:
	lodsb
	cmp al,ah
	je gs4		;if doubled quote character
gs6:
	call skipcomm0	;go back for more
	cmp al,CR
	jne gs1		;if not done yet
	ret
getstr endp

;--- in: AL=first char
;---     SI->2. char
;--- out: value in BX:DX

issymbol proc
	push ax
	push di
	push cx
	mov di,offset regnames
	mov cx,NUMREGNAMES
	mov ah,[si]		;get second char of name 
	and ax,TOUPPER_W
	cmp byte ptr [si+1],'A'
	jnc maybenotasymbol
	repnz scasw
	jnz notasymbol
	xor bx,bx
	mov di, [di+NUMREGNAMES*2 - 2]
getsymlow:
	mov dx,[di]
	inc si		;skip over second char
	clc
	pop cx
	pop di
	pop ax
	ret
maybenotasymbol:
	cmp al,'E'		;386 standard register names start with E
	jnz notasymbol
	mov al,[si+1]
	xchg al,ah
	and ax,TOUPPER_W
	cmp ax,"PI"
	jnz @F
	mov di,offset regs.rIP
	jmp iseip
@@:
	mov cx,8	;scan for the 8 standard register names only
	repnz scasw
	jnz notasymbol
	mov di,[di+NUMREGNAMES*2 - 2]
iseip:
	mov bx,[di+2]	;get HiWord of DWORD register
	inc si
	jmp getsymlow
notasymbol:
	pop cx
	pop di
	pop ax
	stc
	ret
issymbol endp

;   GETDWORD - Get (hex) dword from input line.
;       Entry   AL  first character
;           SI  address of next character
;       Exit    BX:DX   dword
;           AL  first character not in the word
;           SI  address of the next character after that
;       Uses    AH,CL

getdword proc
	call issymbol
	jc @F
	lodsb
	ret
@@:
	call getnyb
	jc errorj6		;if error
	cbw
	xchg ax,dx
	xor bx,bx		;clear high order word
gd1:
	lodsb
	call getnyb
	jc gd3
	test bh,0f0h
	jnz errorj6		;if too big
	mov cx,4
gd2:
	shl dx,1		;double shift left
	rcl bx,1
	loop gd2
	or dl,al
	jmp gd1
gd3:
	ret
getdword endp

errorj6:
	jmp cmd_error

;   GETWORD - Get (hex) word from input line.
;       Entry   AL  first character
;           SI  address of next character
;       Exit    DX  word
;           AL  first character not in the word
;           SI  address of the next character after that
;       Uses    AH,CL

getword proc
	push bx
	call getdword
	and bx,bx		;hiword clear?
	pop bx
	jnz errorj6		;if error
	ret
getword endp

;   GETBYTE - Get (hex) byte from input line into DL.
;       Entry   AL  first character
;           SI  address of next character
;       Exit    DL  byte
;           AL  first character not in the word
;           SI  address of the next character after that
;       Uses    AH,CL

getbyte:
	call getword
	and dh,dh
	jnz errorj6		;if error
	ret

;--- GETNYB - Convert the hex character in AL into a nybble.  Return
;--- carry set in case of error.

getnyb:
	push ax
	sub al,'0'
	cmp al,9
	jbe gn1		;if normal digit
	pop ax
	push ax
	or al,TOLOWER
	sub al,'a'
	cmp al,'f'-'a'
	ja gn2		;if not a-f or A-F
	add al,10
gn1:
	inc sp		;normal return (first pop old AX)
	inc sp
	clc
	ret
gn2:
	pop ax		;error return
	stc
	ret

;--- CHKEOL1 - Check for end of line.

chkeol:
	call skipwh0
	cmp al,CR
	jne errorj8		;if not found
	ret

errorj8:
	jmp cmd_error

;   SKIPCOMMA - Skip white space, then an optional comma, and more white
;       space.
;   SKIPCOMM0 - Same as above, but we already have the character in AL.

skipcomma:
	lodsb
skipcomm0:
	call skipwh0
	cmp al,','
	jne sc2		;if no comma
	push si
	call skipwhite
	cmp al,CR
	jne sc1		;if not end of line
	pop si
	mov al,','
	ret
sc1:
	add sp,2	;pop si into nowhere
sc2:
	ret

;--- SKIPALPHA - Skip alphabetic character, and then white space.

skipalpha:
	lodsb
	and al,TOUPPER
	sub al,'A'
	cmp al,'Z'-'A'
	jbe skipalpha
	dec si
;	jmp skipwhite	;(control falls through)

;--- SKIPWHITE - Skip spaces and tabs.
;--- SKIPWH0 - Same as above, but we already have the character in AL.

skipwhite:
	lodsb
skipwh0:
	cmp al,' '
	je skipwhite
	cmp al,TAB
	je skipwhite
	ret

;--- IFSEP Compare AL with separators ' ', '\t', ',', ';', '='.

ifsep:
	cmp al,' '
	je @F
	cmp al,TAB
	je @F
	cmp al,','
	je @F
	cmp al,';'
	je @F
	cmp al,'='
@@:
	ret

;   Here is the start of the disassembly part of the program.

_DATA segment

dis_n	dw 0		;number of bytes in instruction so far
		dw 0		;must follow dis_n (will always remain 0)
;--- preflags and preused must be consecutive
preflags db 0		;flags for prefixes found so far
preused	db 0		;flags for prefixes used so far

PRESEG	equ 1		;segment prefix
PREREP	equ 2		;rep prefixes
PREREPZ	equ 4		;f3, not f2
PRELOCK	equ 8		;lock prefix
PRE32D	equ 10h		;flag for 32-bit data
PRE32A	equ 20h		;flag for 32-bit addressing
PREWAIT	equ 40h		;prefix wait (not really a prefix)
GOTREGM	equ 80h		;set if we have the reg/mem part

instru	db 0		;the main instruction byte
rmsize	db 0		;<0 or 0 or >0 means mod r/m is 8 or 16 or 32
segmnt	db 0		;segment determined by prefix (or otherwise)
idxins	dw 0		;index of the instruction (unsqueezed)
addrr	dw 0		;address in mod r/m byte (16bit only)
savesp2	dw 0		;save the stack pointer here (used in disasm)

disflags db 0		;flags for the disassembler

;--- equates for disflags:

DIS_F_REPT		equ 1	;repeat after pop ss, etc.
DIS_F_SHOW		equ 2	;show memory contents
DIS_I_SHOW		equ 4	;there are memory contents to show
DIS_I_UNUSED	equ 8	;(internal) print " (unused)"
DIS_I_SHOWSIZ	equ 10h	;(internal) always show the operand size
DIS_I_KNOWSIZ	equ 20h	;(internal) we know the operand size of instr.

disflags2 db 0		;another copy of DIS_I_KNOWSIZ

sizeloc dw 0		;address of size words in output line

_DATA ends

CONST segment

;--- table of obsolete-instruction values.
;--- instructions are FENI, FDISI, FSETPM, MOV to/from TRx
obsinst	dw SFPGROUP3, SFPGROUP3+1, SFPGROUP3+4
		dw SPARSE_BASE+24h, SPARSE_BASE+26h

;--- Table for 16-bit mod r/m addressing.  8 = BX, 4 = BP, 2 = SI, 1 = DI.

rmtab	db 8+2, 8+1, 4+2, 4+1, 2, 1, 4, 8

DefGPR macro regist
REG_&regist& equ ($ - rgnam816)/2
	db "&regist&"
	endm

REG_NO_GPR	equ 24	;16-23 are registers EAX-EDI

DefSR macro regist
REG_&regist& equ REG_NO_GPR + ($ - segrgnam)/2
	db "&regist&"
	endm

;   Tables of register names.
;   rgnam816/rgnam16/segrgnam must be consecutive.

rgnam816 label byte
	DefGPR AL
	DefGPR CL
	DefGPR DL
	DefGPR BL
	DefGPR AH
	DefGPR CH
	DefGPR DH
	DefGPR BH
rgnam16 label byte
	DefGPR AX
	DefGPR CX
	DefGPR DX
	DefGPR BX
	DefGPR SP
	DefGPR BP
	DefGPR SI
	DefGPR DI
N_REGS16 equ ( $ - rgnam16 ) / 2
segrgnam label byte
	DefSR ES
	DefSR CS
	DefSR SS
	DefSR DS
	DefSR FS
	DefSR GS
N_SEGREGS equ ( $ - segrgnam ) / 2
	DefSR ST
	DefSR MM
	DefSR CR
	DefSR DR
	DefSR TR
N_ALLREGS equ ( $ - rgnam816 ) / 2

segrgaddr	dw regs.rES,regs.rCS,regs.rSS,regs.rDS

;--- Tables for handling of named prefixes.

prefixlist	db 26h,2eh,36h,3eh,64h,65h	;segment prefixes (in order)
			db 9bh,0f0h,0f2h,0f3h		;WAIT,LOCK,REPNE,REPE
N_PREFIX equ $ - prefixlist
prefixmnem	dw MN_WAIT,MN_LOCK,MN_REPNE,MN_REPE

CONST ends

disasm1:				;<--- standard entry
	mov [disflags],0

disasm proc				;<--- entry with disflags set
	mov [savesp2],sp
	xor ax,ax
	mov [dis_n],ax
	mov word ptr [preflags],ax	;clear preflags and preused
if ?PM
	mov bx,[u_addr+4]
	call getselattr
	mov [bCSAttr],al
	jz @F
	or [preflags], PRE32D or PRE32A
;	or [preused], PRE32D or PRE32A
@@:
endif
	mov [segmnt],3			;initially use DS segment
	mov [rmsize],80h		;don't display any memory
	mov word ptr [ai.dismach],0;no special machine needed, so far
	call disgetbyte			;get a byte of the instruction
	cmp al,9bh				;wait instruction (must be the first prefix)
	jne da2					;if not

;   The wait instruction is actually a separate instruction as far as
;   the x86 is concerned, but we treat it as a prefix since there are
;   some mnemonics that incorporate it.  But it has to be treated specially
;   since you can't do, e.g., seg cs wait ... but must do wait seg cs ...
;   instead.  We'll catch it later if the wait instruction is not going to
;   be part of a shared mnemonic.

	or [preflags],PREWAIT

;   If we've found a prefix, we return here for the actual instruction
;   (or another prefix).

da1:
	call disgetbyte
da2:
	mov [instru],al	;save away the instruction
	mov ah,0

;--- Now we have the sequence number of the instruction in AX.  Look it up.

da3:
	mov bx,ax
	mov [idxins],ax	;save the compressed index
	cmp ax,SPARSE_BASE
	jb @F			;if it's not from the squeezed part of the table
	mov bl,[sqztab+bx-SPARSE_BASE]
	mov bh,0
	add bx,SPARSE_BASE	;bx = compressed index
@@:
	mov cl,[optypes+bx]	;cx = opcode type
	mov ch,0
	shl bx,1
	mov bx,[opinfo+bx]	;bx = other info (mnemonic if a true instruction)
	mov si,cx
	mov ax,bx
	mov cl,12
	shr ax,cl
	cmp al,[ai.dismach]
	jb @F				;if a higher machine is already required
	mov [ai.dismach],al	;set machine type
@@:
	and bh,0fh			;=and bx,0fffh - remove the machine field
	cmp si,OPTYPES_BASE
	jae da13			;if this is an actual instruction
	call [dis_jmp2+si]	;otherwise, do more specific processing
	jmp da3				;back for more

CONST segment

	align 2

;   Jump table for OP_IMM, OP_RM, OP_M, OP_R_MOD, OP_MOFFS, OP_R, OP_R_ADD,
;   and OP_AX.
;   See orders of asm_jmp1 and bittab.

dis_jmp1 label word
	dw dop_imm, dop_rm, dop_m, dop_r_mod
	dw dop_moffs, dop_r, dop_r_add, dop_ax

;   jump table for displaying operands
;   See orders of asm_jmp1 and bittab.

dis_optab label word
	dw dop_m64,  dop_mfloat, dop_mdouble, dop_m80	;00-03
	dw dop_mxx,  dop_farmem, dop_farimm,  dop_rel8	;04-07
	dw dop_rel1632, dop49,   dop_sti,     dop_cr	;08-11
	dw dop_dr,   dop_tr,     dop_segreg,  dop_imms8	;12-15
	dw dop_imm8, dop_mmx,    dop_shosiz				;16-18
;--- string items OP_1 .. OP_SS
	db '1',0	;19
	db '3',0	;20
	db 'DX'		;21
	db 'CL'		;22
	db 'ST'		;23
	db 'CS','DS','ES','FS','GS','SS'	;24-29

;--- Jump table for a certain place.
;--- the size of this table matches OPTYPES_BASE

dis_jmp2 label word
	dw disbad		;illegal instruction
	dw da_twobyte	;two byte instruction (0F xx)
	dw da_insgrp	;instruction group
	dw da_fpuins	;coprocessor instruction
	dw da_fpugrp	;coprocessor instruction group
	dw da_insprf	;instruction prefix (including 66h/67h)
OPTYPES_BASE equ $ - dis_jmp2

CONST ends

;--- Two-byte instruction 0F xx: index 1E0-2DF.

da_twobyte:
	call disgetbyte
	mov [instru],al
	mov ah,0
	add ax,SPARSE_BASE
	ret

;--- Instruction group.
;--- BX contains "instruction base": 100h, 110h, ...

da_insgrp:
	call getregmem_r	;get the middle 3 bits of the R/M byte
	cbw
	add ax,bx			;offset
	ret

;--- Coprocessor instruction.
;--- BX contains "instruction base": 148h, 158h, ...

da_fpuins:
	or [disflags], DIS_I_SHOWSIZ
	or [ai.dmflags], DM_COPR
	call getregmem
	cmp al,0c0h
	jb da_insgrp	;range 00-bfh is same as an instruction group
	mov cl,3
	shr al,cl		;C0-FF --> 18-1F
	sub al,18h-8	;18-1F --> 08-0F
	cbw
	add ax,bx		;offset
	ret

;--- Coprocessor instruction group.
;--- BX contains "instruction base": 1C8h, 1D0h, 1D8h

da_fpugrp:
	mov al,[ai.regmem]
	and al,7
	cbw
	add ax,bx
	ret

;--- Instruction prefix.  At this point, bl = prefix bits; bh = segment

da_insprf:
if 1
	mov al,bl
	and bl,not (PRE32D or PRE32A)	;these flags are XORed!
endif
	test bl,[preflags]
	jnz da12		;if there are duplicates
	or [preflags],bl
if 1
	mov bl,al
	and al,PRE32D or PRE32A
	xor [preflags],al
endif
	test bl,PRESEG
	jz @F			;if not a segment
	mov [segmnt],bh	;save the segment
@@:
	pop ax			;discard return address
	jmp da1

da12:
	jmp disbad		;we don't allow duplicate prefixes

;   OK.  Here we go.  This is an actual instruction.
;   BX=offset of mnemonic in mnlist
;   SI=offset of operand list in oplists
;   First print the op mnemonic.

da13:
	push si
	lea si,[mnlist+bx]	;offset of mnemonic
	cmp si,offset mnlist+MN_BSWAP
	jne @F				;if not BSWAP
	call dischk32d
	jz da12				;if no operand-size prefix
@@:
	call showop			;print out the op code (at line_out+28)
	mov [sizeloc],0		;clear out this flag
	pop si				;recover list of operands
	add si,offset oplists - OPTYPES_BASE
	cmp byte ptr [si],0
	je da21				;if we're done

;   Loop over operands.  si -> operand type.
;   Fortunately the operands appear in the instruction in the same
;   order as they appear in the disassembly output.

da14:
	mov [disflags2],0		;clear out size-related flags
	lodsb					;get the operand type
	cmp al,OP_SIZE
	jb da18					;if it's not size dependent
	mov [disflags2],DIS_I_KNOWSIZ	;indicate variable size
	cmp al,OP_8
	jae da16				;if the size is fixed (8,16,32,64)
	cmp al,OP_1632
	jae da15				;if word or dword
	mov ah,-1
	test [instru],1
	jz da17					;if byte
da15:
	or [preused],PRE32D		;mark this flag as used
	mov ah,[preflags]
	and ah,PRE32D			;this will be 10h for dword, 00h for word
	jmp da17				;done

da16:
	mov ah,al		;OP_8, OP_16, OP_32 or OP_64 (we know which)
	and ah,0f0h		;this converts ah to <0 for byte, =0 for word,
	sub ah,OP_16	;and >0 for dword (byte=F0,word=0,dword=10,qword=20)

;--- Now we know the size (in ah); branch off to do the operand itself.

da17:
	mov bl,al
	and bx,0eh			;8 entries (IMM, RM, M, R_MOD, M_OFFS, R, R_ADD, AX)
	call [dis_jmp1+bx]	;print out the operand
	jmp da20			;done with operand

;--- Sizeless operands.

da18:
	cbw
	xchg ax,bx
	cmp bl,OP_STR
	jb @F				;if it's not a string
	mov ax,[dis_optab+bx-2]
	stosw
	cmp ah,0
	jnz da20			;if it's two characters
	dec di
	jmp da20			;done with operand
@@:
	call [dis_optab+bx-2]	;otherwise, do something else

;--- operand done, check if there's another one

da20:
	cmp byte ptr [si],0
	jz da21				;if we're done
	mov al,','
	stosb
	jmp da14			;another operand

;--- all operands done.
;--- now check and loop for unused prefixes:
;--- OPSIZE (66h), ADDRSIZE (67h), WAIT, segment, REP[N][Z], LOCK

da21:
	mov al,[preused]
	not al
	and al,[preflags]
	jnz @F			;if some flags remain unused
	jmp da28		;if all flags were used
@@:
	mov cx,N_WTAB
	mov bx,offset wtab1
	mov dx,2*N_WTAB-2
	mov ah,PREWAIT
	test al,ah
	jnz @F			;if there's a WAIT prefix hanging

	mov cx,N_LTABO
	mov bx,offset ltabo1
	mov dx,2*N_LTABO-2
	mov ah,PRE32D
	test al,ah
	jnz @F			;if it's not a 66h prefix that's hanging

	mov cx,N_LTABA
	mov bx,offset ltaba1
	mov dx,2*N_LTABA-2
	mov ah,PRE32A
	test al,ah
	jnz @F			;if it's not a 67h prefix that's hanging
	jmp da24
@@:
	or [preused],ah	;mark this prefix as used
	push di
	mov di,bx
	mov bl,ah
	mov ax,[idxins]
	repne scasw
	jne da23_1		;if not found in the list
	add di,dx		;replace the mnemonic with the 32-bit name
	mov si,[di]
	add si,offset mnlist
	call showop		;copy op mnemonic
da23_0:
	pop di
	jmp da21
da23_1:
if ?PM
	test bl,PRE32A or PRE32D	;is a 66/67 prefix unhandled?
	jz disbad2
	test [bCSAttr],40h		;32bit code segment?
	jnz da23_0				;then ignore those. 
endif
disbad2:
	jmp disbad

da24:
	test al,PRESEG
	jz da25			;if not because of a segment prefix
	mov ax,[idxins]
	cmp ah,0
	jnz disbad2		;if index > 256
	push di
	mov cx,P_LEN
	mov di,offset prfxtab
	repne scasb
	pop di
	jne disbad2		;if it's not on the list
	mov cx,3
	call moveover
	push di
	mov di,offset line_out+MNEMONOFS
	call showseg	;show segment register
	mov al,':'
	stosb
	pop di
	or [preused],PRESEG		;mark it as used
	jmp da21

da25:
	test al,PREREP
	jz da26			;if not a REP prefix
	and al,PREREP+PREREPZ
	or [preused],al
	mov ax,[idxins]
	cmp ah,0
	jnz disbad2		;if not in the first 256 bytes
	and al,not 1	;clear bit0 (MOVSW -> MOVSB)
	push di
	mov di,offset replist
	mov cx,N_REPNC	;scan those for REP first
	repne scasb
	mov si,offset mnlist+MN_REP
	je da27			;if one of the REP instructions
	mov cl,N_REPALL - N_REPNC
	repne scasb
	jne disbad2		;if not one of the REPE/REPNE instructions
	mov si,offset mnlist+MN_REPE
	test [preused],PREREPZ
	jnz da27		;if REPE
	mov si,offset mnlist+MN_REPNE
	jmp da27		;it's REPNE

disbad3:
	jmp disbad

da26:
	test al,PRELOCK
	jz disbad3		;if not a lock prefix, either
	push di
	mov ax,[idxins]
	mov di,offset locktab
	mov cx,N_LOCK
	repne scasw
	jne disbad3		;if not in the approved list
	test [preused],PRESEG
	jz disbad3		;if memory was not accessed
	mov si,offset mnlist+MN_LOCK
	or [preused],PRELOCK

;--- Slip in another mnemonic: REP/REPE/REPNE/LOCK.
;--- SI = offset of mnemonic, what should be
;--- DI is on the stack.

da27:
	pop di
	mov cx,8
	push si
	call moveover
	pop si
	push di
	call showop
	pop di
	jmp da21

;--- Done with instruction.  Erase the size indicator, if appropriate.

da28:
	mov cx,[sizeloc]
	cmp cx,0
	jz da28b		;if there was no size given
	mov al,[disflags]
	test al,DIS_I_SHOWSIZ
	jnz da28b		;if we need to show the size
	test al,DIS_I_KNOWSIZ
	jz da28b		;if the size is not known already
	xchg cx,di
	mov si,di		;save old di
	mov al,' '
@@:
	scasb			;skip size name
	jne @B			;if not done yet
					;(The above is the same as repne scasb, but
					;has no effect on cx.)
	add di,4		;skip 'PTR '
	xchg si,di
	sub cx,si
	rep movsb		;move the line

;--- Now we're really done.  Print out the bytes on the left.

da28b:
	push di		;print start of disassembly line
	mov di,offset line_out
	mov ax,[u_addr+4]	;print address
	call hexword
	mov al,':'
	stosb
	sizeprfX			;mov eax,[u_addr+0]
	mov ax,[u_addr+0]
if ?PM
	mov si,hexword
	test [bCSAttr],40h
	jz @F
	mov si,hexdword
@@:
	call si
else
	call hexword
endif
	mov al,' '
	stosb
	mov bx,[dis_n]
@@:
	mov si,offset line_out+MNEMONOFS - 1
	sub si, di
	shr si, 1
	cmp bx,si
	jle da29		;if it's a short instruction which fits in one line
	sub bx,si
	push bx
	mov bx,si
	push di
	call disshowbytes
	call putsline
	pop cx
	pop bx
	mov di,offset line_out
	sub cx,di
	mov al,' '
	rep stosb
	jmp @B
da29:
	call disshowbytes
da30:
	mov al,' '		;pad to op code
	mov cx,offset line_out+MNEMONOFS
	sub cx,di
	jc @F
	rep stosb
@@:
	pop di
	test [disflags], DIS_I_UNUSED
	jz da32			;if we don't print ' (unused)'
	mov si,offset unused
	cmp byte ptr [di-1],' '
	jne da31		;if there's already a space here
	inc si
da31:
	call copystring	;si->di

;--- Print info. on minimal processor needed.

da32:
	push di
	mov di,offset obsinst
	mov cx,[idxins]
	call showmach	;show the machine type, if needed
	pop di
	jcxz da32f		;if no message

;--- Print a message on the far right.

	mov ax,offset line_out+79
	sub ax,cx
	push cx
	call tab_to		;tab out to the location
	pop cx
	rep movsb		;copy the string
	jmp da32z		;done

;--- Dump referenced memory location.

da32f:
	mov al,[disflags]
	xor al,DIS_F_SHOW + DIS_I_SHOW
	test al,DIS_F_SHOW + DIS_I_SHOW
	jnz da32z		;if there is no memory location to show
	cmp [segmnt],3
	ja da32z		;if FS or GS
	mov ax,offset line_out+79-10
	cmp [rmsize],0
	jl da32h		;if byte
	jz da32g		;if word
	sub ax,4
da32g:
	dec ax
	dec ax
da32h:
	call tab_to
	call showseg		;show segment register
	mov al,':'
	stosb
	mov ax,[addrr]
	call hexword		;show offset
	mov al,'='
	stosb
	mov al,[segmnt]		;segment number
	cbw
	shl ax,1
	xchg ax,bx			;mov bx,ax
	mov bx,[segrgaddr+bx] ;get address of value
	push es
	mov es,[bx]
	mov bx,[addrr]
	mov al,es:[bx+0]	;avoid a "mov ax,[-1]"
	mov ah,es:[bx+1]
	mov dl,es:[bx+2]	;avoid a "mov dx,[-1]"
	mov dh,es:[bx+3]
	pop es
	cmp [rmsize],0
	jl da32j		;if byte
	jz da32i		;if word
	xchg ax,dx
	call hexword
	xchg ax,dx
da32i:
	call hexword
	jmp da32z		;done
da32j:
	call hexbyte	;display byte

da32z:
	call trimputs	;done with operand list
	mov al,[disflags]
	test al,DIS_F_REPT
	jz	da34		;if we're not allowed to repeat ourselves
	test al,DIS_I_UNUSED
	jnz da33		;if we printed ' (unused)'
	mov ax,[idxins]
	cmp ax,17h
	je da33			;if it was 'pop ss'
	cmp ax,8eh
	je da33			;if it was 'mov ss,--'
	cmp ax,0fbh
	jne da34		;if it was not 'sti'
da33:
	jmp disasm1
da34:
	ret

;--- MOD R/M (OP_RM)

dop_rm:
	call getregmem
	cmp al,0c0h
	jb dop05
	jmp dop33			;if pure register reference
dop05:					;<--- used by OP_M, OP_M64, OP_M80
	call showsize		;print out size in AH
dop06:					;<--- used by OP_MOFFS, OP_MXX, OP_MFLOAT, OP_MDOUBLE
	or [preused],PRESEG	;needed even if there's no segment override
						;because handling of LOCK prefix relies on it
	test [preflags],PRESEG
	jz @F				;if no segment override
	call showseg		;print segment name
	mov al,':'
	stosb
@@:
	mov al,[ai.regmem]
	and al,0c7h
	or [preused],PRE32A
	test [preflags],PRE32A
	jz @F
	jmp dop18		;if 32-bit addressing
@@:
	or [disflags], DIS_I_SHOW	;we'd like to show this address
	mov word ptr [addrr],0		;zero out the address initially
	cmp al,6
	xchg ax,bx		;mov bx,ax
	mov al,'['
	stosb
	je dop16		;if [xxxx]
	and bx,7
	mov bl,[rmtab+bx]
	test bl,8
	jnz dop09		;if BX
	test bl,4
	jz dop11		;if not BP
	mov ax,'PB'
	mov cx,[regs.rBP]
	test [preflags],PRESEG
	jnz dop10		;if segment override
	dec [segmnt]	;default is now SS
	jmp dop10

dop09:
	mov ax,'XB'		;BX
	mov cx,[regs.rBX]

dop10:
	mov [addrr],cx	;print it out, etc.
	stosw
	test bl,2+1
	jz dop13		;if done
	mov al,'+'
	stosb
dop11:
	mov ax,'IS'		;SI?
	mov cx,[regs.rSI]
	test bl,1
	jz @F			;if SI
	mov al,'D'		;DI
	mov cx,[regs.rDI]
@@:
	add [addrr],cx	;print it out, etc.
	stosw
dop13:
	test byte ptr [ai.regmem],0c0h
	jz dop17		;if no displacement
	test byte ptr [ai.regmem],80h
	jnz dop15		;if word displacement
	call disgetbyte
	cbw
	add [addrr],ax
	cmp al,0
	mov ah,'+'
	jge @F			;if >= 0
	mov ah,'-'
	neg al
@@:
	mov [di],ah
	inc di
	call hexbyte	;print the byte displacement
	jmp dop17		;done

dop15:
	mov al,'+'
	stosb
dop16:
	call disgetword
	add [addrr],ax
	call hexword    ;print word displacement

dop17:
	mov al,']'
	stosb
	ret

;--- 32-bit MOD REG R/M addressing.

dop18:
	cmp al,5
	jne @F			;if not just a disp32 address
	mov al,'['
	stosb
	call disp32		;display 32bit offset
	jmp dop27

@@:
	push ax
	and al,7
	cmp al,4
	jne @F			;if no SIB
	call disgetbyte	;get and save it
	mov [ai.sibbyte],al
@@:
	pop ax
	test al,80h
	jnz dop22		;if disp32
	test al,40h
	jz dop23		;if no disp8
	call disgetbyte
	cmp al,0
	jge @F			;if >= 0
	neg al
	mov byte ptr [di],'-'
	inc di
@@:
	call hexbyte
	jmp dop23		;done

dop22:
	call disp32		;print disp32

dop23:
	mov al,[ai.regmem]
	and al,7
	cmp al,4
	jne dop28		;if no SIB
	mov al,[ai.sibbyte]
if 1               ;bugfix: make 'u' correctly handle [ESP],[ESP+x]
	cmp al,24h
	jnz @F
	mov al,4
	jmp dop28
@@:
endif
	and al,7
	cmp al,5
	jne @F			;if not [EBP]
	test byte ptr [ai.regmem],0c0h
	jnz @F			;if MOD != 0
	call disp32		;show 32-bit displacement instead of [EBP]
	jmp dop25

@@:
	mov word ptr [di],'E['
	inc di
	inc di
	call showreg16	;show 16bit register name (number in AL)
	mov al,']'
	stosb

dop25:
	mov al,[ai.sibbyte]
	shr al,1
	shr al,1
	shr al,1
	and al,7
	cmp al,4
	je disbad1		;if illegal
	mov word ptr [di],'E['
	inc di
	inc di
	call showreg16
	mov ah,[ai.sibbyte]
	test ah,0c0h
	jz dop27		;if SS = 0
	mov al,'*'
	stosb
	mov al,'2'
	test ah,80h
	jz @F			;if *2
	mov al,'4'
	test ah,40h
	jz @F			;if *4
	mov al,'8'
@@:
	stosb
dop27:
	mov al,']'
	stosb
	ret

;--- 32-bit addressing without SIB

dop28:
	mov word ptr [di],'E['
	inc di
	inc di
	call showreg16
	mov al,']'
	stosb
	ret

;--- Memory-only reference (OP_M)

dop_m:
	call getregmem
	cmp al,0c0h
	jae disbad1		;if it's a register reference
	jmp dop05

disbad1:
	jmp disbad		;this is not supposed to happen

;--- Register reference from MOD R/M part (OP_R_MOD)

dop_r_mod:
	call getregmem
	cmp al,0c0h
	jb disbad1		;if it's a memory reference
	jmp dop33

;--- Memory offset reference (OP_MOFFS)

dop_moffs:
	call showsize	;print the size and save various things
	mov al,5
	test [preflags],PRE32A
	jnz @F			;if 32-bit addressing
	inc ax
@@:
	mov [ai.regmem],al
	jmp dop06		;don't show size

;--- Pure register reference (OP_R)

dop_r:
	call getregmem_r

dop33:					;<--- used by OP_RM, OP_R_MOD and OP_R_ADD
	and al,7			;entry point for regs from MOD R/M, and others
	mov cl,[disflags2]
	or [disflags],cl	;if it was variable size operand, the size
						;should now be marked as known.
	cmp ah,0
	jl dop35			;if byte register
	jz dop34			;if word register
	cmp ah,20h			;qword register (mmx)?
	jz dop35_1
	mov byte ptr [di],'E'
	inc di
dop34:
	add al,8
dop35:
	cbw
	shl ax,1
	xchg ax,bx			;mov bx,ax
	mov ax,word ptr [rgnam816+bx];get the register name
	stosw
	ret
dop35_1:
	push ax
	mov ax,"MM"
	stosw
	pop ax
	add al,'0'
	stosb
	ret

;--- Register number embedded in the instruction (OP_R_ADD)

dop_r_add:
	mov al,[instru]
	jmp dop33

;--- AL or AX or EAX (OP_AX)

dop_ax:
	mov al,0
	jmp dop33

;--- QWORD mem (OP_M64).
;--- this operand type is used by:
;--- + cmpxchg8b
;--- + fild, fistp

dop_m64:
;	mov ax,'Q'		;print 'Q' +'WORD'
	mov ah,20h		;size QWORD
	jmp dop40

;--- FLOAT (=REAL4) mem (OP_MFLOAT).

dop_mfloat:
	mov ax,'LF'
	stosw
	mov al,'O'
	stosb
	mov ax,'TA'
	jmp dop38c

;--- DOUBLE (=REAL8) mem (OP_MDOUBLE).

dop_mdouble:
	mov ax,'OD'
	stosw
	mov ax,'BU'
	stosw
	mov ax,'EL'
dop38c:
	stosw
	call showptr
	jmp dop42a

;--- TBYTE (=REAL10) mem (OP_M80).

dop_m80:
	mov ax,0ff00h+'T'	;print 't' + 'byte'
	stosb
dop40:
	call getregmem
	cmp al,0c0h
	jae disbad5		;if it's a register reference
	and [disflags],not DIS_F_SHOW	;don't show this
	jmp dop05

;--- far memory (OP_FARMEM).
;--- this is either a FAR16 (DWORD) or FAR32 (FWORD) pointer

dop_farmem:
	call dischk32d
	jz @F			;if not dword far
	call showdwd
	sub di,4		;erase "PTR "
@@:
	mov ax,'AF'		;store "FAR "
	stosw
	mov ax,' R'
	stosw

;--- mem (OP_MXX).

dop_mxx:
	and [disflags],not DIS_F_SHOW	;don't show this
dop42a:
	call getregmem
	cmp al,0c0h
	jae disbad5		;if it's a register reference
	jmp dop06		;don't show size

disbad5:
	jmp disbad

;--- far immediate (OP_FARIMM). Either FAR16 or FAR32

dop_farimm:
	call disgetword
	push ax
	call dischk32d
	jz @F			;if not 32-bit address
	call disgetword
	push ax
@@:
	call disgetword
	call hexword
	mov al,':'
	stosb
	call dischk32d
	jz @F			;if not 32-bit address
	pop ax
	call hexword
@@:
	pop ax
	call hexword
	ret

;--- 8-bit relative jump (OP_REL8)

dop_rel8:
	call disgetbyte
	cbw
	jmp dop48

;--- 16/32-bit relative jump (OP_REL1632)

dop_rel1632:
	call disgetword
	call dischk32d
	jz dop48		;if not 32-bit offset
	push ax
if ?PM
	test [bCSAttr],40h	;for 32bit code segments
	jnz dop47_1			;no need to display "DWORD "
endif
	call showdwd
	sub di,4		;erase "PTR "
dop47_1:
	pop dx
	call disgetword
	mov bx,[u_addr+0]
	add bx,[dis_n]
	add dx,bx
	adc ax,[u_addr+2]
	call hexword
	xchg ax,dx
	jmp hexword		;call hexword and return

dop48:
if ?PM
	test [bCSAttr],40h
	jnz @F
endif
	add ax,[u_addr]
	add ax,[dis_n]
	jmp hexword		;call hexword and return
if ?PM
@@:
	.386
	cwde	;=movsx eax,ax
	add eax,dword ptr [u_addr]
	add eax,dword ptr [dis_n]
	jmp hexdword
	.8086
endif

;--- Check for ST(1) (OP_1CHK).

dop49:
	pop ax		;discard return address
	mov al,[ai.regmem]
	and al,7
	cmp al,1
	je dop50		;if it's ST(1)
	jmp da14		;another operand (but no comma)

dop50:
	jmp da21		;end of list

;--- ST(I) (OP_STI).

dop_sti:
	mov al,[ai.regmem]
	and al,7
	xchg ax,bx		;mov bx,ax
	mov ax,'TS'
	stosw			;store ST(bl)
	mov al,'('
	stosb
	mov ax,')0'
	or al,bl
	stosw
	ret

;--- CRx (OP_CR).

dop_cr:
	mov bx,'RC'
	call getregmem_r
	cmp al,4
	ja disbad4		;if too large
	jne @F
	mov [ai.dismach],5	;CR4 is new to the 586
@@:
	cmp [idxins],SPARSE_BASE+22h
	jne dop55		;if not MOV CRx,xx
	cmp al,1
	jne dop55		;if not CR1

disbad4:
	jmp disbad		;can't MOV CR1,xx

;--- DRx (OP_DR).

dop_dr:
	call getregmem_r
	mov bx,'RD'
	mov cx,-1		;no max or illegal value
	jmp dop55

;--- TRx (OP_TR).

dop_tr:
	call getregmem_r
	cmp al,3
	jb disbad		;if too small
	cmp al,6
	jae @F			;if TR6-7
	mov [ai.dismach],4	;TR3-5 are new to the 486
@@:
	mov bx,'RT'

dop55:
	xchg ax,bx
	stosw			;store XX
	xchg ax,bx
	or al,'0'
	stosb
	ret

;--- Segment register (OP_SEGREG).

dop_segreg:
	call getregmem_r
	cmp al,6
	jae disbad		;if not a segment register
	cmp al,2
	je @F			;if SS
	and [disflags],not DIS_F_REPT	;clear flag:  don't repeat
@@:
	cmp al,4
	jb @F			;if not FS or GS
	mov [ai.dismach],3	;(no new 486-686 instructions involve seg regs)
@@:
	add al,16
	jmp dop35		;go print it out

showsizeop:
;--- for PUSH imm8 add D/W to opcode if size differs from default (WORD/DWORD)
	cmp [instru],6ah
	jnz sso_skip
	call dischk32d
@@:
if ?PM
	mov ah,[bCSAttr]
	.286
	shr ah,2		;40h -> 10h (=PRE32D)
	.8086
else
	mov ah,0
endif
	mov al,'W'
	test ah,PRE32D
	jnz @F
	mov al,'D'
@@:
	xor ah,[preflags]
	test ah,PRE32D
	jz sso_skip
	mov [di-4],al
sso_skip:
	ret
;--- Sign-extended immediate byte (OP_IMMS8). "push xx"

dop_imms8:
	call showsizeop
	call disgetbyte
	cmp al,0
	xchg ax,bx		;mov bl,al
	mov al,'+'
	jge @F			;if >= 0
	neg bl
	mov al,'-'
@@:
	stosb
	xchg ax,bx		;mov al,bl
	jmp dop59a		;call hexbyte and return

;--- Immediate byte (OP_IMM8).

dop_imm8:
	call disgetbyte
dop59a:
	jmp hexbyte		;call hexbyte and return

;--- Show MMx reg (OP_MMX; previously was "Show ECX if LOOPxx is 32bit)"

dop_mmx:
	mov bx,'MM'
	call getregmem_r
	and al,7
	jmp dop55

;--- Set flag to always show size (OP_SHOSIZ).

dop_shosiz:
	or [disflags],DIS_I_SHOWSIZ
dop60a:
	pop ax			;discard return address
	jmp da14		;next...

disbad:
	mov sp,[savesp2]	;pop junk off stack
	mov ax,offset da13
	push ax
	mov [dis_n],0
	mov word ptr [preflags],0		;clear preflags and preused
	mov [rmsize],80h				;don't display any memory
	mov word ptr [ai.dismach],0		;forget about the machine type
	and [disflags],not DIS_I_SHOW	;and flags
	call disgetbyte
	mov di,offset prefixlist
	mov cx,N_PREFIX
	repne scasb
	je @F			;if it's a named prefix
	dec [dis_n]
	mov bx,MN_DB	;offset of 'DB' mnemonic
	mov si,OPLIST_26+OPTYPES_BASE;this says OP_IMM8
	ret
@@:
	or [disflags],DIS_I_UNUSED	;print special flag
	mov bx,N_PREFIX-1
	sub bx,cx
	shl bx,1
	cmp bx,6*2
	jb @F			;if SEG directive
	mov bx,[prefixmnem+bx-6*2]
	mov si,OPTYPES_BASE	;no operand
	ret
@@:
	lea si,[bx+OPLIST_40+OPTYPES_BASE]	;this is OP_ES
	mov bx,MN_SEG
	ret

;   GETREGMEM_R - Get the reg part of the reg/mem part of the instruction
;   Uses    CL

getregmem_r:
	call getregmem
	mov cl,3
	shr al,cl
	and al,7
	ret

;--- GETREGMEM - Get the reg/mem part of the instruction

getregmem:
	test [preused],GOTREGM
	jnz @F			;if we have it already
	or [preused],GOTREGM
	call disgetbyte	;get the byte
	mov [ai.regmem],al	;save it away
@@:
	mov al,[ai.regmem]
	ret

;   SHOWSEG - Show the segment descriptor in SEGMNT
;   Entry   DI  Where to put it
;   Exit    DI  Updated
;   Uses    AX, BX

showseg:
	mov al,[segmnt]	;segment number
	cbw
	shl ax,1
	xchg ax,bx		;mov bx,ax
	mov ax,word ptr [segrgnam+bx] ;get register name
	stosw
	ret

;   DISP32 - Print 32-bit displacement for addressing modes.
;   Entry   None
;   Exit    None
;   Uses    AX

disp32:
	call disgetword
	push ax
	call disgetword
	call hexword
	pop ax
	call hexword
	ret

;   SHOWREG16 - Show 16-bit register name.
;   Entry   AL  register number (0-7)
;   Exit    None
;   Uses    AX

showreg16:
	cbw
	shl ax,1
	xchg ax,bx
	push ax
	mov ax,word ptr [rgnam16+bx]
	stosw
	pop ax
	xchg ax,bx
	ret

;--- DISCHK32D - Check for 32 bit operand size prefix (66h).

dischk32d:
	or [preused],PRE32D
	test [preflags],PRE32D
	ret

disasm endp

;--- Here are the routines for printing out the operands themselves.
;--- Immediate data (OP_IMM)

dop_imm proc
	cmp ah,0
	jl dop03		;if just a byte
	pushf
	test [disflags], DIS_I_SHOWSIZ
	jz @F			;if we don't need to show the size
	call showsize	;print size in AH
	sub di,4		;erase "PTR "
@@:
	call disgetword
	popf
	jz @F			;if just a word
	push ax
	call disgetword	;print the high order word
	call hexword
	pop ax
@@:
	call hexword
	ret

dop03:
	call disgetbyte	;print immediate byte
	call hexbyte
	ret
dop_imm endp

;   SHOWOP  Show the op code
;   Entry   SI  Null-terminated string containing the op mnemonic
;   Exit    DI  Address of next available byte in output line
;           (>= offset line_out + 32 due to padding)
;   Uses    AL

showop proc
	mov di,offset line_out+MNEMONOFS
@@:
	lodsb
	mov ah,al
	and al,7Fh
	stosb
	and ah,ah
	jns @B
	mov al,' '
@@:
	stosb
	cmp di,offset line_out+MNEMONOFS+8
	jb @B
	ret
showop endp

;   SHOWSIZE - Print a description of the size
;   Entry   AH  10h=DWORD, 00h=WORD, F0h=BYTE, 20h=QWORD
;   Uses    AX

;   SHOWPTR - Print " PTR"
;   Uses    AX

;   SHOWDWD - Print "DWORD PTR"
;   Uses    AX

showsize proc
	mov [rmsize],ah	;save r/m size
	mov [sizeloc],di;save where we're putting this
	mov al,'Q'
	cmp ah,20h
	jz showqwd
	cmp ah,0
	jg showdwd	;if dword
	je showwd	;if word
	mov ax,'YB'
	stosw
	mov ax,'ET'
	jmp ssz3
showdwd::		;<---
	mov al,'D'
showqwd:
	stosb
showwd:
	mov ax,'OW'
	stosw
	mov ax,'DR'
ssz3:
	stosw
showptr::		;<---
	mov ax,'P '
	stosw
	mov ax,'RT'
	stosw
	mov al,' '
	stosb
	ret
showsize endp

;   DISGETBYTE - Get byte for disassembler.
;   Entry   None
;   Exit    AL  Next byte in instruction stream
;   Uses    None

disgetbyte proc
	push ds
if ?PM
	test [bCSAttr],40h
	jnz @F
endif
	push si
	mov si,[u_addr]
	mov ds,[u_addr+4]
	add si,cs:[dis_n]	;index to the right byte
	lodsb 				;get the byte
	pop si
	pop ds
	inc [dis_n]			;indicate that we've gotten this byte
	ret
if ?PM
	.386
@@:
	push esi
	lds esi,fword ptr [u_addr]
	add esi,dword ptr cs:[dis_n]	;index to the right byte
	lodsb ds:[esi]
	pop esi
	pop ds
	inc [dis_n]
	ret
	.8086
endif
disgetbyte endp

;   DISGETWORD - Get word for disassembler.
;   Entry   None
;   Exit    AX  Next word
;   Uses    None

disgetword proc
	push ds
if ?PM
	test [bCSAttr],40h
	jnz @F
endif
	push si		;save si
	mov si,[u_addr]
	mov ds,[u_addr+4]
	add si,cs:[dis_n]	;index to the right byte
	lodsw
	pop si		;restore things
	pop ds
	add [dis_n],2
	ret
if ?PM
	.386
@@:
	push esi
	lds esi,fword ptr [u_addr]
	add esi,dword ptr cs:[dis_n]	;index to the right byte
	lodsw ds:[esi]
	pop esi
	pop ds
	add [dis_n],2
	ret
	.8086
endif
disgetword endp

;   DISSHOWBYTES - Show bytes for the disassembler.
;   Entry   BX  Number of bytes (must be > 0)
;   Exit        u_addr updated
;   Uses    BX, SI.

disshowbytes proc
if ?PM
	test [bCSAttr],40h
	jnz dissb_1
endif
	mov si,[u_addr]
	mov ds,[u_addr+4]
@@:
	lodsb
	call hexbyte
	dec bx
	jnz @B
	push ss
	pop ds
	mov [u_addr],si
	ret
if ?PM
	.386
dissb_1:
	lds esi,fword ptr [u_addr]
@@:
	lodsb ds:[esi]
	call hexbyte
	dec bx
	jnz @B
	push ss
	pop ds
	mov dword ptr [u_addr],esi
	ret
    .8086
endif
disshowbytes endp

;   MOVEOVER - Move the line to the right - disassembler subfunction.
;   Entry   DI  Last address + 1 of line so far
;   Exit    CX  Number of bytes to move
;   DI  Updated
;   Uses    SI

moveover proc
	cmp [sizeloc],0
	je @F		;if sizeloc not saved
	add [sizeloc],cx
@@:
	mov si,di
	add di,cx
	mov cx,di
	sub cx,offset line_out+MNEMONOFS
	push di
	std
	dec si
	dec di
	rep movsb
	pop di
	cld
	ret
moveover endp

;   SHOWMACH - Return strings 
;           "[needs _86]" or "[needs _87]",
;           "[needs math coprocessor]" or "[obsolete]"
;   Entry   di -> table of obsolete instructions ( 5 items )
;           cx -> instruction
;   Exit    si Address of string
;           cx Length of string, or 0 if not needed
;   Uses    al, di

showmach proc
	mov si,offset needsmsg		;candidate message
	test [ai.dmflags],DM_COPR
	jz is_cpu   		;if not a coprocessor instruction
	mov byte ptr [si+9],'7'	;change message text ('x87')
	mov al,[mach_87]
	cmp [has_87],0
	jnz sm2				;if it has a coprocessor
	mov al,[machine]
	cmp al,[ai.dismach]
	jb sm3				;if we display the message
	mov si,offset needsmath	;print this message instead
	mov cx,sizeof needsmath
	ret

is_cpu:
	mov byte ptr [si+9],'6'	;reset message text ('x86')
	mov al,[machine]
sm2:
	cmp al,[ai.dismach]
	jae sm4				;if no message (so far)
sm3:
	mov al,[ai.dismach]
	add al,'0'
	mov [si+7],al
	mov cx,sizeof needsmsg	;length of the message
	ret

;--- Check for obsolete instruction.

sm4:
	mov si,offset obsolete	;candidate message
	mov ax,cx				;get info on this instruction
	mov cx,5
	repne scasw
	jne @F			;if no matches
	mov di,offset obsmach + 5 - 1
	sub di,cx
	xor cx,cx		;clear CX:  no message
	mov al,[mach_87]
	cmp al,[di]
	jle @F			;if this machine is OK
	mov cx,sizeof obsolete
@@:
	ret
showmach endp

;--- DUMPREGS - Dump registers.
;--- 16bit: 8 std regs, NL, skip 2, 4 seg regs, IP, flags
;--- 32bit: 6 std regs, NL, 2 std regs+IP+FL, flags, NL, 6 seg regs

dumpregs proc
	mov si,offset regnames
	mov di,offset line_out
	mov cx,8			;print all 8 std regs (16-bit)
	test [rmode],RM_386REGS
	jz @F
	mov cl,6			;room for 6 std regs (32-bit) only
@@:
	call dmpr1			;print first row
	call trimputs
	mov di,offset line_out
	test [rmode],RM_386REGS
	jnz @F
	push si
	add si,2*2			;skip "IP"+"FL"
	mov cl,4			;print 4 segment regs
	call dmpr1w
	pop si
	inc cx			;cx=1
	call dmpr1		;print (E)IP
	call dmpflags	;print flags in 8086 mode
	jmp no386_31
@@:
	mov cl,4		;print rest of 32-bit std regs + EIP + EFL
	call dmpr1d
	push si
	call dmpflags	;print flags in 386 mode 
	call trimputs
	pop si
	mov di,offset line_out
	mov cl,6		;print ds, es, ss, cs, fs, gs
	call dmpr1w
no386_31:
	call trimputs

;--- display 1 disassembled line at CS:[E]IP

	mov si, offset regs.rIP
	mov di, offset u_addr
	movsw
	movsw
	mov ax,[regs.rCS]
	stosw
	mov [disflags],DIS_F_REPT or DIS_F_SHOW
	call disasm

;--- 'r' resets default setting for 'u' to CS:[E]IP

	sizeprf
	mov ax,[regs.rIP]
	sizeprf
	mov [u_addr],ax
	ret
dumpregs endp

;--- Function to print multiple WORD/DWORD register entries.
;--- SI->register names (2 bytes)
;--- CX=count

dmpr1:
	test [rmode],RM_386REGS
	jnz dmpr1d

;--- Function to print multiple WORD register entries.
;--- SI->register names (2 bytes)
;--- CX=count

dmpr1w:
	movsw
	mov al,'='
	stosb
	mov bx,[si+NUMREGNAMES*2-2]
	mov ax,[bx]
	call hexword
	mov al,' '
	stosb
	loop dmpr1w
	ret

;--- Function to print multiple DWORD register entries.
;--- SI->register names (2 bytes)
;--- CX=count

dmpr1d:
	mov al,'E'
	stosb
	movsw
	mov al,'='
	stosb
	mov bx,[si+NUMREGNAMES*2-2]
	.386
	mov eax,[bx]
	.8086
	call hexdword
	mov al,' '
	stosb
	loop dmpr1d
	ret

;--- the layout for FSAVE/FRSTOR depends on mode and 16/32bit

if 0
FPENV16 struc
cw	dw ?
sw	dw ?
tw	dw ?
fip	dw ?	;ip offset
union
opc dw ?	;real-mode: opcode[0-10], ip 16-19 in high bits
fcs	dw ?	;protected-mode: ip selector
ends
fop	dw ?	;operand ptr offset
union
foph dw ?	;real-mode: operand ptr 16-19 in high bits
fos	dw ?	;protected-mode: operand ptr selector
ends
FPENV16 ends

FPENV32 struc
cw	dw ?
	dw ?
sw	dw ?
	dw ?
tw	dw ?
	dw ?
fip	dd ?	;ip offset (real-mode: bits 0-15 only)
union
struct
fopcr dd ?	;real-mode: opcode (0-10), ip (12-27)
ends
struct
fcs	dw ?	;protected-mode: ip selector
fopcp dw ?	;protected-mode: opcode(bits 0-10)
ends
ends
foo	dd ?	;operand ptr offset (real-mode: bits 0-15 only)
union
struct
fooh dd ?	;real-mode: operand ptr (12-27)
ends
struct
fos	dw ?	;protected-mode: operand ptr selector
	dw ?	;protected-mode: not used
ends
ends
FPENV32 ends
endif

CONST segment
fregnames label byte
	db "CW", "SW", "TW"
	db "OPC=", "IP=", "DP="
dEmpty db "empty"
dNaN db "NaN"
CONST ends

;--- dumpregsFPU - Dump Floating Point Registers 
;--- modifies SI, DI, [E]AX, BX, CX, [E]DX

dumpregsFPU proc
	mov di,offset line_out
	mov si,offset fregnames
	mov bx,offset line_in + 2
	sizeprf
	fnsave [bx]

;--- display CW. SW and TW

	mov cx,3
nextfpr:
	movsw
	mov al,'='
	stosb
	xchg si,bx
	sizeprf		;lodsd
	lodsw
	xchg si,bx
	push ax
	call hexword
	mov al,' '
	stosb
	loop nextfpr

;--- display OPC
;--- in 16bit format protected-mode, there's no OPC
;--- for 32bit, there's one, but the location is different from real-mode

	push bx
if ?PM
	call ispm
	jz @F
	add bx,2	;location of OPC in protected-mode differs from real-mode!
	cmp [machine],3
	jnb @F
	add si,4	;no OPC for FPENV16 in protected-mode
	jmp noopc
@@:
endif
	movsw
	movsw
	xchg si,bx
	sizeprf			;lodsd
	lodsw			;skip word/dword
	lodsw
	xchg si,bx
	and ax,07FFh	;bits 0-10 only
	call hexword
	mov al,' '
	stosb
noopc:
	pop bx

;--- display IP and DP

	mov cl,2		;ch is 0 already
nextfp:
	push cx
	movsw
	movsb
	xchg si,bx
	sizeprf		;lodsd
	lodsw
	sizeprf		;mov edx,eax
	mov dx,ax
	sizeprf		;lodsd
	lodsw
	xchg si,bx
if ?PM
	call ispm
	jz @F
	call hexword
	mov al,':'
	stosb
	jmp fppm
@@:
endif
	mov cl,12
	sizeprf		;shr eax,cl
	shr ax,cl
	cmp [machine],3
	jb @F
	call hexword
	jmp fppm
@@:
	call hexnyb
fppm:
	sizeprfX	;mov eax,edx
	mov ax,dx
if ?PM
	call ispm
	jz @F
	cmp [machine],3
	jb @F
	call hexdword
	jmp fppm32
@@:
endif
	call hexword
fppm32:
	mov al,' '
	stosb
	pop cx
	loop nextfp

	xchg si,bx
	call trimputs

;--- display ST0 - ST7

	pop bp	;get TW
	pop ax	;get SW
	pop dx	;get CW (not used)

	mov cl,10
	shr ax, cl	;mov TOP to bits 1-3
	and al, 00001110b
	mov cl, al
	ror bp, cl

	mov cl,'0'
nextst:         ;<- next float to display
	mov di,offset line_out
	push cx
	mov ax,"TS"
	stosw
	mov al,cl
	mov ah,'='
	stosw
	push di
	test al,1
	mov al,' '
	mov cx,22
	rep stosb
	jz @F
	mov ax,0A0Dh
	stosw
@@:
	mov al,'$'
	stosb
	pop di

	mov ax,bp
	ror bp,1	;remain 8086 compatible here!
	ror bp,1
	and al,3	;00=valid,01=zero,02=NaN,03=Empty
	jz isvalid
	push si
	mov si,offset dEmpty
	mov cl, sizeof dEmpty
	cmp al,3
	jz @F
	mov si,offset dNaN
	mov cl, sizeof dNaN
	cmp al,2
	jz @F
	mov al,'0'
	stosb
	mov cl,0
@@:
	rep movsb
	pop si
	jmp regoutdone
isvalid:
if ?PM
	invoke FloatToStr, si, di
else
	mov ax,[si+8]
	call hexword
	mov al,'.'
	stosb
	mov ax,[si+6]
	call hexword
	mov ax,[si+4]
	call hexword
	mov ax,[si+2]
	call hexword
	mov ax,[si+0]
	call hexword
endif
regoutdone:
	mov dx,offset line_out
	call int21ah9
	pop cx
	add si,10	;sizeof TBYTE
	inc cl
	cmp cl,'8'
	jnz nextst
	.286	;avoid WAIT prefix
	sizeprf
	frstor [line_in + 2]
	.8086
	ret
dumpregsFPU endp

;--- DMPFLAGS - Dump flags output.

dmpflags proc
	mov si,offset flgbits
	mov cx,8	;lengthof flgbits
nextitem:
	lodsw
	test ax,[regs.rFL]
	mov ax,[si+16-2]
	jz @F			;if not asserted
	mov ax,[si+32-2]
@@:
	stosw
	mov al,' '
	stosb
	loop nextitem
	ret
dmpflags endp

if MMXSUPP
	.386
dumpregsMMX proc
	fnsaved [line_in + 2]
	mov si,offset line_in + 7*4 + 2
	mov cl,'0'
;	mov di, offset line_out
nextitem:
	mov ax,"MM"
	stosw
	mov al,cl
	mov ah,'='
	stosw
	push cx
	mov dl,8
nextbyte:
	lodsb
	call hexbyte
	mov al,' '
	test dl,1
	jz @F
	mov al,'-'
@@:
	stosb
	dec dl
	jnz nextbyte
	dec di
	mov ax,'  '
	stosw
	add si,2
	pop cx
	test cl,1
	jz @F
	push cx
	call putsline
	pop cx
	mov di,offset line_out
@@:
	inc cl
	cmp cl,'8'
	jnz nextitem
	fldenvd [line_in + 2]
	ret
dumpregsMMX endp
	.8086
endif

;--- copystring - copy non-empty null-terminated string.
;--- SI->string
;--- DI->buffer

copystring proc
	lodsb
@@:
	stosb
	lodsb
	cmp al,0
	jne @B
	ret
copystring endp

;   HEXDWORD - Print hex word (in EAX).
;   clears HiWord(EAX)

;   HEXWORD - Print hex word (in AX).
;   HEXBYTE - Print hex byte (in AL).
;   HEXNYB - Print hex digit.
;   Uses    al, di.

hexdword proc
	push ax
	.386
	shr eax,16
	.8086
	call hexword
	pop ax
hexdword endp	;fall through!

hexword proc
	push ax
	mov al,ah
	call hexbyte
	pop ax
hexword endp	;fall through!

hexbyte:
	push ax
	push cx
	mov cl,4
	shr al,cl
	call hexnyb
	pop cx
	pop ax

hexnyb:
	and al,0fh
	add al,90h		;these four instructions change to ascii hex
	daa
	adc al,40h
	daa
	stosb
	ret

;   TAB_TO - Space fill until reaching the column indicated by AX.
;   (Print a new line if necessary.)

tab_to proc
	push ax
	sub ax,di
	ja @F			;if there's room on this line
	call trimputs
	mov di,offset line_out
@@:
	pop cx
	sub cx,di
	mov al,' '
	rep stosb		;space fill to the right end
	ret
tab_to endp

;   TRIMPUTS - Trim excess blanks from string and print (with CR/LF).
;   PUTSLINE - Add CR/LF to string and print it.
;   PUTS - Print string through DI.

trimputs:
	dec di
	cmp byte ptr [di],' '
	je trimputs
	inc di

putsline:
	mov ax,LF * 256 + CR
	stosw

puts:
	mov cx,di
	mov dx,offset line_out
	sub cx,dx

;--- fall thru'
;--- stdout: write DS:DX, size CX to STDOUT (1)
;--- modifies ax

stdout proc
	call InDos
	push bx
	jnz @F
	mov bx,1		;standard output
	mov ah,40h		;write to file
	call doscall
	pop bx
	ret
@@:					;use BIOS for output
	jcxz nooutput
	push si
	mov si,dx
@@:
	lodsb
	mov bx,0007
	mov ah,0Eh
	int 10h
	loop @B
	pop si
nooutput:
	pop bx
	ret
stdout endp

if DRIVER eq 0
createdummytask proc

	mov di, offset regs
	mov cx, sizeof regs / 2
	xor ax, ax
	rep stosw

	mov ah,48h		;get largest free block
	mov bx,-1
	int 21h
	cmp bx,11h		;must be at least 110h bytes!!!
	jc ct_done
	mov ah,48h		;allocate it
	int 21h
	jc ct_done		;shouldn't happen

	mov byte ptr [regs.rIP+1],1	;IP=100h

	call setespefl

	push bx
	mov di,offset regs.rDS	;init regs.rDS,regs.rES,regs.rSS,regs.rCS
	stosw
	stosw
	stosw
	stosw
	call setup_adu
	mov bx,[regs.rCS]	;bx:dx = where to load program
	mov es,bx
	pop ax			;get size of memory block
	mov dx,ax
	add dx,bx
	mov es:[ALASAP],dx
	cmp ax,1000h
	jbe @F			;if memory left <= 64K
	xor ax,ax		;ax = 1000h (same thing, after shifting)
@@:
	mov cl,4
	shl ax,cl
	dec ax
	dec ax
	mov [regs.rSP],ax
	xchg ax,di		;es:di = child stack pointer
	xor ax,ax
	stosw			;push 0 on client's stack

;--- Create a PSP

	mov ah,55h		;create child PSP
	mov dx,es
	mov si,es:[ALASAP]
	clc				;works around OS/2 bug
	int 21h
	mov word ptr es:[TPIV+0],offset int22
	mov es:[TPIV+2],cs
	cmp [bInit],0
	jnz @F
	inc [bInit]
	mov byte ptr es:[100h],0C3h	;place opcode for 'RET' at CS:IP
@@:
	mov [pspdbe],es
	mov ax,es
	dec ax
	mov es,ax
	inc ax
	mov es:[0001],ax
	mov byte ptr es:[0008],0
	push ds			;restore ES
	pop es
	call setpspdbg	;set debugger's PSP
ct_done:
	ret

createdummytask endp

endif

if ?PM

;--- hook int 2Fh if a DPMI host is found
;--- for Win3x/9x and DosEmu host
;--- int 2Fh, ax=1687h is not hooked, however
;--- because it doesn't work. Debugging
;--- in protected-mode still may work, but
;--- the initial-switch to PM must be single-stepped
;--- modifies AX, BX, CX, DX, DI

hook2f proc
	cmp cs:[cssel],0		;initial switch already occured?
	jz @F
	ret
@@:
	cmp word ptr [oldi2f+2],0
	jnz hook2f_2
	mov ax,1687h			;DPMI host installed?
	int 2Fh
	and ax,ax
	jnz hook2f_2
	mov word ptr [dpmientry+0],di	;true host DPMI entry
	mov word ptr [dpmientry+2],es
	mov word ptr [dpmiwatch+0],di
	mov word ptr [dpmiwatch+2],es
	cmp [bNoHook2F],0				;can int 2Fh be hooked?
	jnz hook2f_2
	mov word ptr [dpmiwatch+0],offset mydpmientry
	mov word ptr [dpmiwatch+2],cs
	mov ax,352Fh
	int 21h
	mov word ptr [oldi2f+0],bx
	mov word ptr [oldi2f+2],es
	mov dx,offset debug2F
	mov ax,252Fh
	int 21h
if DISPHOOK
	push ds
	pop es
	push si
;--- don't use line_out here!
	mov di,offset line_in + 128
	mov dx,di
	mov si,offset dpmihook
	call copystring
	pop si
	mov ax,cs
	call hexword
	mov al,':'
	stosb
	mov ax,offset mydpmientry
	call hexword
	mov ax,LF * 256 + CR
	stosw
	mov cx,di
	sub cx,dx
	call stdout
endif
hook2f_2:
	push ds
	pop es
	ret
hook2f endp

endif

_TEXT ends

_DATA segment

;--- I/O buffers.  (End of permanently resident part.)

line_in		db 255,0,CR				;length = 257
line_out	equ line_in+LINE_IN_LEN+1;length = 1 + 263
real_end	equ line_in+LINE_IN_LEN+1+264

_DATA ends

_ITEXT segment

if DRIVER eq 0

initcont:
	mov sp,ax
	mov ah,4Ah
	int 21h			;free rest of DOS memory
	mov byte ptr [line_out-1],'0'	;initialize line_out?
	cmp [fileext],0
	jz @F
	call loadfile
@@:
	jmp cmdloop

;---------------------------------------
;--- Debug initialization code.
;---------------------------------------

imsg1	db DBGNAME,' version 1.27.  Debugger.',CR,LF,CR,LF
	db 'Usage: ', DBGNAME, ' [[drive:][path]progname [arglist]]',CR,LF,CR,LF
	db '  progname (executable) file to debug or examine',CR,LF
	db '  arglist parameters given to program',CR,LF,CR,LF
	db 'For a list of debugging commands, '
	db 'run ', DBGNAME, ' and type ? at the prompt.',CR,LF,'$'

imsg2	db 'Invalid switch - '
imsg2a	db 'x',CR,LF,'$'

endif

if ?PM
if DOSEMU
dDosEmuDate db "02/25/93"
endif
endif
if VDD
szDebxxVdd	db "DEBXXVDD.DLL",0
szDispatch	db "Dispatch",0
szInit		db "Init",0
endif

if DRIVER

init_req struct
	req_hdr <>
units	 db ?	;+13 number of supported units
endaddr  dd ?	;+14 end address of resident part
cmdline  dd ?	;+18 address of command line
init_req ends

driver_entry proc far

	push ds
	push di
	lds di, cs:[request_ptr]	; load address of request header
	mov [di].req_hdr.status,0100h
	push bx
	push ds
	push es
	push bp
	push di
	push si
	push dx
	push cx
	push cs
	pop ds
	call initcode
	mov [Intrp],offset interrupt
	mov dx,offset drv_installed
	mov ah,9
	int 21h
	sub bx,2
	mov [bx],offset ue_int
	mov [run_sp],bx
	pop cx
	pop dx
	pop si
	pop di
	pop bp
	pop es
	pop ds
	mov word ptr [di].init_req.endaddr+0,bx	; if bx == 0, driver won't be installed
	mov word ptr [di].init_req.endaddr+2,cs	; set end address
	pop bx
	pop di
	pop ds
	retf
drv_installed:
	db "DEBUGX device driver installed",13,10,'$'
driver_entry endp

start:
	push cs
	pop ds
	mov dx,offset cantrun
	mov ah,9
	int 21h
	mov ah,4ch
	int 21h
cantrun:
	db "This is a device driver version of DEBUG.",13,10
	db "It is supposed to be installed via",13,10
	db "DEVICE=<name_of_executable>",13,10
	db "in CONFIG.SYS. Thanks for your attention!",13,10
	db "$"

endif

initcode proc
	cld
if DRIVER
	mov ah,51h
	int 21h
	mov ax,bx
else
	mov ax,cs
	mov word ptr [execblk.cmdtail+2],ax
	mov word ptr [execblk.fcb1+2],ax
	mov word ptr [execblk.fcb2+2],ax
endif
	mov [pspdbg],ax

;--- Check for console input vs. input from a file or other device.

	mov ax,4400h	;IOCTL--get info
	xor bx,bx       ;stdin
	int 21h
	jc @F			;if not device
	and dl,81h		;check if console device
	cmp dl,81h
	jne @F			;if not the console input
	mov [notatty],0	;it _is_ a tty
@@:
	mov ax,4400h	;IOCTL--get info
	mov bx,1        ;stdout
	int 21h
	jc @F
	mov [stdoutf],dl
@@:

;--- Check DOS version

	mov ax,3000h	;check DOS version
	int 21h
	xchg al,ah
	cmp ax,31fh
	jb init2		;if version < 3.3, then don't use new INT 25h method
	inc [usepacket]
if VDD
	cmp ah,5
	jnz @F
	mov ax,3306h
	int 21h
	cmp bx,3205h
	jnz @F
	mov si,offset szDebxxVdd	;DS:SI->"DEBXXVDD.DLL"
	mov bx,offset szDispatch	;DS:BX->"Dispatch"
	mov di,offset szInit		;ES:DI->"Init"
	RegisterModule
	jc init2
	mov [hVdd], ax
	jmp isntordos71
@@:
endif
	cmp ax,070Ah
	jb init2
isntordos71:
	inc [usepacket]	;enable FAT32 access method for L/W

;   Determine the processor type.  This is adapted from code in the
;   Pentium<tm> Family User's Manual, Volume 3:  Architecture and
;   Programming Manual, Intel Corp., 1994, Chapter 5.  That code contains
;   the following comment:

;   This program has been developed by Intel Corporation.
;   Software developers have Intel's permission to incorporate
;   this source code into your software royalty free.

;   Intel 8086 CPU check.
;   Bits 12-15 of the FLAGS register are always set on the 8086 processor.
;   Probably the 186 as well.

init2:
	push sp
	pop ax
	cmp ax,sp		
	jnz init6		;if 8086 or 80186 (can't tell them apart)

;   Intel 286 CPU check.
;   Bits 12-15 of the flags register are always clear on the
;   Intel 286 processor in real-address mode.

	mov [machine],2
	pushf			;get original flags into AX
	pop ax
	or ax,0f000h	;try to set bits 12-15
	push ax			;save new flags value on stack
	popf			;replace current flags value
	pushf			;get new flags
	pop ax			;store new flags in AX
	test ah,0f0h	;if bits 12-15 clear, CPU = 80286
	jz init6		;if 80286

;   Intel 386 CPU check.
;   The AC bit, bit #18, is a new bit introduced in the EFLAGS
;   register on the Intel486 DX cpu to generate alignment faults.
;   This bit cannot be set on the Intel386 CPU.

;   It is now safe to use 32-bit opcode/operands.

	.386

	inc [machine]
	mov bx,sp		;save current stack pointer to align
	and sp,not 3	;align stack to avoid AC fault
	pushfd			;push original EFLAGS
	pop eax			;get original EFLAGS
	mov ecx,eax		;save original EFLAGS in CX
	xor eax,40000h	;flip (XOR) AC bit in EFLAGS
	push eax		;put new EFLAGS value on stack
	popfd			;replace EFLAGS value
	pushfd			;get new EFLAGS
	pop eax			;store new EFLAGS value in EAX
	cmp eax,ecx
	jz init5		;if 80386 CPU

;   Intel486 DX CPU, Intel487 SX NDP, and Intel486 SX CPU check.
;   Checking for ability to set/clear ID flag (bit 21) in EFLAGS
;   which indicates the presence of a processor with the ability
;   to use the CPUID instruction.

	inc [machine]	;it's a 486
	mov eax,ecx		;get original EFLAGS
	xor eax,200000h	;flip (XOR) ID bit in EFLAGS
	push eax		;save new EFLAGS value on stack
	popfd			;replace current EFLAGS value
	pushfd			;get new EFLAGS
	pop eax			;store new EFLAGS in EAX
	cmp eax,ecx		;check if it's changed
	je init5		;if it's a 486 (can't toggle ID bit)
	push ecx
	popfd			;restore AC bit in EFLAGS first
	mov sp,bx		;restore original stack pointer

;--- Execute CPUID instruction.

	.586

	xor eax,eax		;set up input for CPUID instruction
	cpuid
	cmp eax,1
	jl init6		;if 1 is not a valid input value for CPUID
	xor eax,eax		;otherwise, run CPUID with ax = 1
	inc eax
	cpuid
if MMXSUPP
	test edx,800000h
	setnz [has_mmx]
endif
	mov al,ah
	and al,0fh		;bits 8-11 are the model number
	cmp al,6
	jbe init3		;if <= 6
	mov al,6		;if > 6, set it to 6
init3:
	mov [machine],al;save it
	jmp init6		;don't restore SP

init5:
	push ecx
	popfd			;restore AC bit in EFLAGS first
	mov sp,bx		;restore original stack pointer

	.8086		 	;back to 1980s technology

;   Next determine the type of FPU in a system and set the mach_87
;   variable with the appropriate value.  All registers are used by
;   this code; none are preserved.

;   Coprocessor check.
;   The algorithm is to determine whether the floating-point
;   status and control words can be written to.  If not, no
;   coprocessor exists.  If the status and control words can be
;   written to, the correct coprocessor is then determined
;   depending on the processor ID.  The Intel386 CPU can
;   work with either an Intel 287 NDP or an Intel387 NDP.
;   The infinity of the coprocessormust be checked
;   to determine the correct coprocessor ID.

init6:
	mov al,[machine]
	mov [mach_87],al	;by default, set mach_87 to machine
	inc [has_87]
	cmp al,5			;a Pentium or above always will have a FPU
	jnc init7
	dec [has_87]

	fninit				;reset FP status word
	mov ax,5a5ah		;init with non-zero value
	push ax
	mov bp,sp
	fnstsw [bp]			;save FP status word
	pop ax				;check FP status word
	cmp al,0
	jne init7			;if no FPU present

	push ax
	fnstcw [bp]			;save FP control word
	pop ax				;check FP control word
	and ax,103fh		;see if selected parts look OK
	cmp ax,3fh
	jne init7			;if no FPU present
	inc [has_87]		;there's an FPU

;--- If we're using a 386, check for 287 vs. 387 by checking whether
;--- +infinity = -infinity.

	cmp [machine],3
	jne init7		;if not a 386
	fld1			;must use default control from FNINIT
	fldz			;form infinity
	fdivp ST(1),ST		;1 / 0 = infinity
	fld ST			;form negative infinity
	fchs
	fcompp			;see if they are the same and remove them
	push ax
	fstsw [bp]		;look at status from FCOMPP
	pop ax
	sahf
	jnz init7		;if they are different, then it's a 387
	dec [mach_87]	;otherwise, it's a 287
init7:

;--- remove size and addr prefixes if cpu is < 80386

	cmp [machine],3
	jnb nopatch
	mov si,offset patches
	mov cx,cntpatch
@@:
	lodsw
	xchg ax,bx
	mov byte ptr [bx],90h
	loop @B
	mov [patch_movsp],3Eh	;set ("unnecessary") DS segment prefix
	mov [patch_iret],0CFh	;code for IRET
nopatch:

;--- Interpret switches and erase them from the command line.

	mov ax,3700h		;get switch character
	int 21h
	mov [switchar],dl
	cmp dl,'/'
	jne @F
	mov [swch1],dl
@@:

if DRIVER eq 0
	mov si,DTA+1
@@:
	lodsb
	cmp al,' '
	je @B
	cmp al,TAB
	je @B

;--- Process the /? switch (or the [switchar]? switch).
;--- If switchar != / and /? occurs, make sure nothing follows.

	cmp al,dl
	je init11		;if switch character
	cmp al,'/'
	jne init12		;if not the help switch
	mov al,[si]
	cmp al,'?'
	jne init12		;if not /?
	mov al,[si+1]
	cmp al,' '
	je init10		;if nothing after /?
	cmp al,TAB
	je init10		;ditto
	cmp al,CR
	jne init12		;if not end of line

;--- Print a help message

init10:
	mov dx,offset imsg1	;command-line help message
	call int21ah9	;print string
	int 20h			;done

;--- Do the (proper) switches.

init11:
	lodsb
	cmp al,'?'
	je init10		;if -?

;--- ||| Other switches may go here.

	mov [imsg2a],al
	mov dx,offset imsg2	;Invalid switch
	call int21ah9	;print string
	mov ax,4c01h	;Quit and return error status
	int 21h

;--- Feed the remaining command line to the 'n' command.

init12:
	dec si
	lodsb
	call n_cmd		;process the rest of the line

endif

;--- Set up interrupt vectors.

	mov cx,NUMINTS
	mov si,offset inttab
	mov di,offset intsave
@@:
	lodsb
	mov ah,35h
	int 21h
	mov [di+0],bx
	mov [di+2],es
	add di,4
	xchg ax,dx		;save int # in dl
	lodsw			;get address
	xchg ax,dx		;restore int # in al, set int offset in dx
	mov ah,25h		;set interrupt vector
	int 21h
	loop @B

if MCB
	mov ah,52h		;get list of lists
	int 21h
	mov ax,es:[bx-2]	;start of MCBs
	mov [wMCB],ax
endif
	mov ah,34h
	int 21h
	mov word ptr [pInDOS+0],bx
	mov word ptr [pInDOS+2],es

;--- get address of DOS swappable DATA area
;--- to be used to get/set PSP and thus avoid DOS calls
;--- will not work for DOS < 3

if USESDA
	push ds
	mov ax,5D06h
	int 21h
	mov ax,ds
	pop ds
	jc @F
	mov word ptr [pSDA+0],si
	mov word ptr [pSDA+2],ax
@@:
endif

if ?PM

;--- Windows 3x/9x and DosEmu are among those hosts which handle some
;--- V86 Ints internally without first calling the interrupt chain.
;--- This causes various sorts of troubles and incompatibilities.

if WIN9XSUPP
	mov ax,1600h	;running in a win3x/win9x dos box?
	int 2Fh
	and al,al       ;returns in AL 3=win3x, 4=win9x
	jnz no2fhook
endif
if DOSEMU
	mov ax,0F000h
	mov es,ax
	mov di,0FFF5h
	mov si,offset dDosEmuDate
	mov cx,4
	repe cmpsw		;running in DosEmu?
	jz no2fhook
endif
	jmp dpmihostchecked
no2fhook:
	inc [bNoHook2F]
dpmihostchecked:
endif

	push ds
	pop es

if DRIVER eq 0

;--- Save and modify termination address and the parent PSP field.

	mov si,TPIV
	mov di,offset psp22
	movsw
	movsw
	mov word ptr [si-4],offset intr22

	mov [si-2],cs
	mov si,PARENT
	movsw
	mov [si-2],cs
	mov [pspdbe],cs	;indicate there is no debuggee loaded yet

endif

;--- shrink DEBUG and set its stack

	mov ax,offset real_end + STACKSIZ + 15
	and al,not 15		;new stack pointer
	mov bx,ax
	dec ax
	dec ax
	mov [top_sp],ax	;save new SP minus two (for the word we'll push)
if DRIVER
	ret
else
	inc ax
	inc ax
	mov cl,4
	shr bx,cl
	jmp initcont
endif
initcode endp

_ITEXT ends

_IDATA segment
cntpatch = ($ - patches) / 2
_IDATA ends

	end start
