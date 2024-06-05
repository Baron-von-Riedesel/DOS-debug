;   DEBUG.ASM Masm/JWasm assembler source for Debug/X.

;   To assemble, use:
;       jwasm -bin -Fo debug.com debug.asm
;
;   To create DEBUGX, the DPMI aware version of debug, use:
;       jwasm -D?DPMI=1 -bin -Fo debugx.com debug.asm

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
;       - allow to modify floating point registers
;       - better syntax checks for A (so i.e. "mov ax,al" is rejected)
;       - add MMX instructions for A and U
;       - support loading *.HEX files
;       - hide debug's IVT vectors 0,1,3 for d(i)? Alternately, init them only when the
;         first G/P/T cmd is run, like MS Debug does for 1 & 3?

VERSION    textequ <2.50>

	option casemap:none
	option proc:private
;	option noljmp	;enable to see the short jump extensions

BS         equ 8
TAB        equ 9
LF         equ 10
CR         equ 13
TOLOWER    equ 20h
TOUPPER    equ 0dfh
TOUPPER_W  equ (TOUPPER shl 8) or TOUPPER
MNEMONOFS  equ 28	;offset in output line where mnemonics start (disassember)
STACKSIZ   equ 200h	;debug's stack size
MCLOPT     equ 1	;1=accept /m cmdline opt ( disable IRQ checks for int 08-0F )
LINE_IN_LEN equ 257	;length of line_in (including header stuff)

ifndef FMTEXE
FMTEXE     equ 0	;1=debugger binary has .EXE format
endif
ifndef DRIVER
DRIVER     equ 0	;1=create a device driver (for CONFIG.SYS) variant
endif
ifndef BOOTDBG
BOOTDBG    equ 0	;1=create a bootstrap binary (DebugB)
endif
ifndef RING0
RING0      equ 0	;1=create a ring0 debugger variant (DebugR)
endif
ifndef ?DPMI
?DPMI      equ 0	;1=create a DPMI-aware variant (DebugX)
endif
ifndef LMODE
LMODE      equ 0	;1=long mode version if RING0==1 - this will define a 64-bit segment ( requires JWasm )
endif

;--- default assembly-time values; may be overwritten below.

DGCMD      = 0		; support DG cmd
DICMD      = 0		; support DI cmd
DLCMD      = 0		; support DL cmd
DMCMD      = 1		; support DM cmd
DPCMD      = 0		; support DP cmd (dump partition)
DPCMDR0    = 0		; support DP cmd (dump paging table, ring0 only)
DTCMD      = 0		; support DT cmd
DXCMD      = 0		; support DX cmd
QCMD       = 1		; support Q cmd
LCMD       = 1		; support L cmd
WCMD       = 1		; support W cmd
XCMDS      = 1		; support Xx cmds
LCMDFILE   = 1		; support L cmd for files and N cmd
WCMDFILE   = 1		; support W cmd for files and N cmd
USESDA     = 1		; use SDA to get/set PSP in real-mode
INT22      = 1		; handle int 22h ( DOS program termination )
INT2324    = 1		; switch int 23h & 24h for debugger/debuggee
USEFP2STR  = 0		; 1=use FloatToStr()
FLATSS     = 0		; always 0 except for DebugRL; flat stack needed for long mode ring0 variant.

SKIPBPINDBG equ 1	; 1=breakpoints occuring while in debug are reported, won't reenter debug

if LMODE
CS32	equ 40h or 20h	; check both default size and 64-bit mode
else
CS32	equ 40h		; check just the default size in legacy
endif

@VecAttr textequ <>

ifndef V86M
V86M       equ 0	; 1=support v86 mode ( for RING0 only )
endif

if RING0
 if LMODE
DBGNAME    equ <"DEBUG64">
DBGNAME2   equ <"Debug64">
@VecAttr   textequ <lowword>
;--- long mode needs a flat 32-bit stack inside debug!
;--- that's because otherwise an exception inside the PL0 debugger 
;--- would switch to 64-bit code with a 16-bit "flat" stack pointer.
FLATSS     = 1	; 1=32-bit flat stack
 else
DBGNAME    equ <"DEB386">
DBGNAME2   equ <"Deb386">
 endif

?PM        equ 1
USEHWBP    equ 1	; 1=use 386 hw breakpoints
VDD        equ 0
;NOEXTENDER equ 0	; ??? used at all for ring0 ???
DISPPL0STK equ 0	;1=display ring 0 stack in register dump
CHKIOPL    equ 1	;1=don't stop if GPF cause of IOPL==0 and iosensitive instr
 ifndef BCMD
BCMD       equ 1
 endif
DGCMD      = 1
DICMD      = 1
DLCMD      = 1
DMCMD      = 0
DTCMD      = 1
VXCMD      = 1
elseif ?DPMI
DBGNAME    equ <"DEBUGX">
DBGNAME2   equ <"DebugX">
?PM        equ 1
VDD        equ 1	;1=try to load DEBXXVDD.DLL
NOEXTENDER equ 1	;1=don't assume DPMI host includes a DOS extender
WIN9XSUPP  equ 1	;1=avoid to hook DPMI entry when running in Win9x
DOSEMU     equ 1	;1=avoid to hook DPMI entry when running in DosEmu
DISPHOOK   equ 1	;1=display "DPMI entry hooked..."
 ifndef CATCHEXC06
CATCHEXC06 equ 0	;1=catch exception 06h in protected-mode
 endif
 ifndef CATCHEXC07
CATCHEXC07 equ 0	;1=catch exception 07h in protected-mode
 endif
CATCHEXC0C equ 1	;1=catch exception 0Ch in protected-mode
CATCHINT21 equ 1	;1=hook into protected-mode int 21h
 ifndef CATCHINT31
CATCHINT31 equ 0	;1=hook DPMI int 31h
 endif
CATCHINT41 equ 1	;1=hook into protected-mode debug interface
MMXSUPP    equ 1	;1=support MMX specific commands
 ifndef USEHWBP
USEHWBP    equ 1	;1=try to use 386 hw breakpoints (fails on NTVDM/DosEmu)
 endif
 ifndef BCMD
BCMD       equ 0	;BCMD=1 requires USEHWBP=1
 endif
DICMD      = 1
DLCMD      = 1
DXCMD      = 1
USEFP2STR  = 1
else
DBGNAME    equ <"DEBUG">
DBGNAME2   equ <"Debug">
?PM        equ 0
VDD        equ 0
NOEXTENDER equ 0
 ifndef BCMD
BCMD       equ 0
 endif
 if BCMD
USEHWBP    equ 1
 elseifndef USEHWBP
USEHWBP    equ 0
 endif
endif

if DRIVER
CATCHINT06 = 1
QCMD       = 0
LCMDFILE   = 0
WCMDFILE   = 0
INT22      = 0
INT2324    = 0
elseif RING0
CATCHINT06 = 1
 ifndef CATCHINT0C ; may be activated with cmdline option
CATCHINT0C = 0
 endif
CATCHINT0D = 1
CATCHINT41 = 0
DPCMDR0    = 0
LCMD       = 0
QCMD       = 0	; may be set to 1
WCMD       = 0
XCMDS      = 0
LCMDFILE   = 0
WCMDFILE   = 0
USESDA     = 0
INT22      = 0
INT2324    = 0
elseif BOOTDBG
CATCHINT06 = 1
DICMD      = 1
DMCMD      = 0
DPCMD      = 1
DXCMD      = 1
QCMD       = 0
WCMD       = 0
XCMDS      = 0
LCMDFILE   = 0
WCMDFILE   = 0
USESDA     = 0
INT22      = 0
INT2324    = 0
endif

ifndef USEUNREAL
USEUNREAL  equ 0	;1=use "unreal" mode for DX cmd ( won't work in v86 )
endif
ifndef MMXSUPP
MMXSUPP    equ 0
endif
ifndef VXCHG
VXCHG      equ 0	;1=support video swap so outputs remain separated
endif
ifndef ALTVID
ALTVID     equ 0    ;1=support alternate video adapter
endif
ifndef DICMD
DICMD      = 0
endif
ifndef DXCMD
DXCMD      = 0
endif
ifndef VXCMD
VXCMD      = 0
endif

if (DRIVER or BOOTDBG or RING0)
REDIRECT equ 0
else
REDIRECT equ 1		;stdin/stdout redirection
endif

SYSRQINT   equ 9	;if CATCHSYSREQ==1, defines the method (int 09h or int 15h)

ifndef CATCHINT01
CATCHINT01 equ 1	;catch INT 01 (single-step)
NOEXC01INDBG equ 1	;v2.01: ignore unexpected debug exceptions in debug itself
endif
ifndef CATCHINT03
CATCHINT03 equ 1	;catch INT 03 (break)
endif
ifndef CATCHINT06
CATCHINT06 equ 0	;catch exception 06h
endif
ifndef CATCHINT07
CATCHINT07 equ 0	;catch exception 07h
endif
ifndef CATCHINT0C
CATCHINT0C equ 0	;catch exception 0Ch
endif
ifndef CATCHINT0D
CATCHINT0D equ 0	;catch exception 0Dh
endif
ifndef CATCHSYSREQ
CATCHSYSREQ equ 0	;catch int 09h/15h (sysreq)
endif
ifndef CATCHINT41
CATCHINT41 equ 0	;hook int 41h
endif

ife ?DPMI
CATCHEXC06 equ 0
CATCHEXC07 equ 0
CATCHEXC0C equ 0
endif

if ?PM or CATCHINT07
EXCCSIP    equ 1	;display CS:IP where exception occured
 if V86M
EXCCSEIP   equ 1	;debugger may callout to v86-monitor, which is 32-bit CS
 else
EXCCSEIP   equ 0	;may be activated if unknown exceptions occur in debugger
 endif
else
EXCCSIP    equ 0
endif

PSPS struct
       dw ?		;+00
ALASAP dw ?		;+02 Address of LAst Segment  Allocated to Program
       dw ?,?,?	;+04
TPIV   dd ?		;+0A Terminate Program Interrupt Vector (int 22h)
CCIV   dd ?		;+0E Control C Interrupt Vector (int 23h)
CEIV   dd ?		;+12 Critical Error Interrupt Vector (int 24h)
       org 16h
PARENT dw ?		;+16 segment of parent PSP
       org 2Eh
SPSAV  dd ?		;+2E Saved SS:SP in last DOS call
       org 5Ch
FCB1   db 16 dup (?)
FCB2   db 16 dup (?)
       org 80h
DTA    db 128 dup (?);Program arguments; also used to store file name (N cmd)
PSPS ends

;--- attributes returned by int 21h, ax=4400h
AT_DEVICE  equ 80h  ; is device (not file)

ifdef _DEBUG
@dprintf macro text:req,a1,a2,a3,a4,a5,a6,a7,a8
local sym
CONST segment
sym db text,10,0
CONST ends
	pushcontext cpu
	.386
	for x,<a8,a7,a6,a5,a4,a3,a2,a1>
	 ifnb <x>
	  push x
	 endif
	endm
	push offset sym
	call dprintf
	popcontext cpu
endm
else
@dprintf textequ <;>
endif

;--- restore segment register (DS/ES) to DGROUP

@RestoreSeg macro segm
if FLATSS
	mov segm, cs:[wDgroup]
else
	push ss
	pop segm
endif
endm

;--- sizeprf is to make DEBUG's support for 32bit code as small as possible.
;--- for this to achieve a patch table is created in _IDATA which is filled
;--- by memory offsets where prefix bytes 66h or 67h are found.

sizeprf macro
ife RING0
curreip = $
_IDATA segment
	dw curreip
_IDATA ends
endif
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

;--- define segments. Usually, the debugger runs in the tiny memory model,
;--- that is, all segments are grouped into "physical segment" DGROUP, and
;--- CS=SS=DS=ES=DGROUP ( exception: RING0=1 && FLATSS=1 ). When other memory
;--- regions are to be accessed, preferably ES is temporary used then, in a
;--- few cases ( m/c cmds ) also DS.

_TEXT segment dword public 'CODE'
_TEXT ends

if RING0
 if LMODE
	.x64
_TEXT64 segment use64 para public 'CODE'	; alignment para is needed for correct offsets
_TEXT64 ends
	.8086
 endif
endif

CONST segment readonly word public 'DATA'
CONST ends

ASMDATA segment word public 'DATA'
asmtab label byte
ASMDATA ends

OTDATA segment word public 'DATA'
OTDATA ends

_DATA segment dword public 'DATA'
_DATA ends

if RING0
_ITEXT segment dword public 'I_CODE'
else
_ITEXT segment word public 'I_CODE'
endif
_ITEXT ends

_IDATA segment word public 'I_DATA'
patches label word
_IDATA ends

DGROUP group _TEXT, CONST, ASMDATA, OTDATA, _DATA, _ITEXT, _IDATA

if FMTEXE or DRIVER
STACK segment para stack 'STACK'
	db STACKSIZ dup (?)
STACK ends
DGROUP group STACK
endif

	assume ds:DGROUP

_TEXT segment

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

 ife (RING0 or BOOTDBG)
  ife FMTEXE
	org 100h
  endif
 endif
 ife FMTEXE
start:
	jmp initcode
 endif
 if RING0
	jmp getr0stk	; get ring 0 SS:ESP
	org start+6		; entercmd must be start+2*3
	jmp uninstall	; uninstall
 endif

endif

_TEXT ends

CONST segment

;--- cmds b,j,k,v,y and z don't exist yet

cmdlist label word
	dw a_cmd
if BCMD
bcmdv dw b_cmderr	; may be dynamically set to b_cmd
else
	dw cmd_error
endif
	dw c_cmd, d_cmd
	dw e_cmd, f_cmd, g_cmd, h_cmd
	dw i_cmd, cmd_error, cmd_error
ife RING0
	dw l_cmd
else
	dw cmd_error
endif
	dw m_cmd
if LCMDFILE or WCMDFILE
	dw n_cmd
else
	dw cmd_error
endif
	dw o_cmd, p_cmd
if QCMD
	dw q_cmd
else
	dw cmd_error
endif
	dw r_cmd, s_cmd, t_cmd
	dw u_cmd
if VXCHG
	dw v_cmd
elseif VXCMD
	dw v_cmd
else
	dw cmd_error
endif
if WCMD
	dw w_cmd
else
	dw cmd_error
endif
if XCMDS
	dw x_cmd
else
	dw cmd_error
endif
ENDCMD equ <'x'>

if ?DPMI
dbg2324 dw i23pm, i24pm
endif

CONST ends

_DATA segment

if FLATSS
top_sp	dd 0		;debugger's SP top ( also end of debug's MCB )
run_sp	dd 0		;debugger's SP when run() is executed ( also used temp. by disasm )
else
top_sp	dw 0		;debugger's SP top ( also end of debug's MCB )
run_sp	dw 0		;debugger's SP when run() is executed
endif
errret	dw 0		;return here if error
ife (BOOTDBG or RING0)
spadjust dw 40h 	;adjust sp by this amount for save
pspdbe	dw 0		;debuggee's program segment prefix (segment/selector)
endif

;--- wDgroup contains the DGROUP segment, not translated!
;--- pspdbg contains the PSP, not translated
;--- pspdbgpm is the translated pspdbg (.EXE only)
;--- in protected-mode, the code usually uses [dssel] to set SS and DS

wDgroup label word	;pspdbg is the PSP segment or just the CS segment (Dgroup)
if FMTEXE
		dw 0		;for .EXE, DGROUP and debugger's psp are different
endif
pspdbg	dw 0		;debugger's PSP - always a segment
if ?DPMI and FMTEXE
pspdbgpm dw 0		;selector for debugger's PSP
endif

if INT2324
run2324	dw 0,0,0,0	;debuggee's interrupt vectors 23 and 24 (both modes)
 if ?DPMI
		dw 0,0		;in DPMI32, vectors are FWORDs
 endif
endif
if RING0
wFlat	dw 0
 if V86M
dwV86Ofs dd 0
 endif
endif
if VDD
hVdd	dw -1		;handle of NT helper VDD
endif

if INT2324
sav2324	dw 0,0,0,0	;debugger's interrupt vectors 23 and 24 (real-mode only)
endif
if INT22
psp22	dw 0,0		;original terminate address in debugger's PSP
parent	dw 0		;original parent PSP in debugger's PSP (must be next)
endif
if DMCMD
wMCB	dw 0		;start of MCB chain (always segment)
endif
ife ( BOOTDBG or RING0 )
pInDOS	dd 0		;far16 address of InDOS flag (real mode)
endif
if ?DPMI
InDosSel dw 0		;selector value for pInDOS in protected-mode
endif
if VXCHG
 ifndef VXCHGFLIP
XMSM struct
size_  dd ?
srchdl dw ?
srcadr dd ?
dsthdl dw ?
dstadr dd ?
XMSM ends
xmsdrv	dd 0        ; XMM driver address, obtained thru int 2F, ax=4310h
xmsmove  XMSM <>    ; XMS block move struct, used to save/restore screens
csrpos dw 0         ; cursor position of currently inactive screen
vrows  db 0         ; current rows; to see if debuggee changed video mode
 endif
endif
if ALTVID           ; exchange some video BIOS data fields for option /2.
oldcsrpos dw 0      ; cursor position
oldcrtp   dw 0      ; CRTC port
oldcols   dw 80     ; columns
oldmr label word
oldmode   db 0      ; video mode
oldrows   db 24     ; rows - 1
endif
if USESDA
pSDA	dd 0		;far16 address of DOS swappable data area (real-mode)
 if ?DPMI
SDASel	dw 0		;selector value for pSDA in protected-mode
 endif
endif
if INT2324
hakstat	db 0		;whether we have hacked vectors 23/24 or not
endif
machine	db 0		;cpu (0=8086,1,2,3=80386,...)

RM_386REGS	equ 1	;bit 0: 1=386 register display
if RING0
rmode	db RM_386REGS
else
rmode	db 0		;flags for R command
endif
tmode	db 0		;bit 0: 1=ms-debug compatible trace mode

if USEHWBP
bBPhit   db 0
wStoreBP   dw offset storebpdef  ; proc to set first bp for G/P/T
wRMSetBP   dw offset r0sethwbp   ; proc to set hw bps in real-mode/r0
wRMResetBP dw offset r0resethwbp ; proc to reset hw bps in real-mode/r0
endif

has_87	db 0		;if there is a math coprocessor present
mach_87	db 0		;coprocessor (0=8087,1,2,3=80387,...)
if MMXSUPP
has_mmx	db 0
endif
bInDbg	db 0		;1=debugger is running
if MCLOPT and ( CATCHINT0C or CATCHINT0D )
bMPicB	db 8		;master PIC base
endif
if REDIRECT
fStdin	db AT_DEVICE;flags stdin
fStdout	db AT_DEVICE;flags stdout
endif
swchar	db '-'		;switch character
vpage	db 0		;video page the debugger is to use for BIOS output 
swch1	db ' '		;switch character if it's a slash
promptlen dw 0		;length of prompt
if REDIRECT
bufnext	dw line_in+2	;if stdin=file: address of next available character
bufend	dw line_in+2	;if stdin=file: address + 1 of last valid character
endif

a_addr	dw 0,0,0	;address for next A command
d_addr	dw 0,0,0	;address for last D command; must follow a_addr
u_addr	dw 0,0,0	;address for last U command; must follow d_addr

if USEHWBP
;--- bits in bType:
;---   0-3: type
BP_CODE   equ  0h
BP_TEMP   equ 20h	;1=bp is temporary
BP_ACTIVE equ 40h	;1=bp has been set
BP_USED   equ 80h	;1=used,0=free
BP_ACTIVEBIT equ 6

HWBPSTRUCT struct
dwLinAd dd ?
bType   db ?
 if ?DPMI
wHdl	dw ?	; DPMI only
 endif
HWBPSTRUCT ends

MAXHWBP equ 4
HWBps HWBPSTRUCT MAXHWBP dup (<0,0>)
endif

if DXCMD
x_addr	dd 0		;(phys) address for last DX command
endif
eqladdr	dw 0,0,0	;optional '=' argument in G, P and T command
;run_cs	dw 0		;save original CS when running in G
lastcmd	dw dmycmd
run_intw label word
run_int	db 0,0		;interrupt type that stopped the running
eqflag	db 0		;flag indicating presence of '=' argument
bInit	db 0		;0=ensure a valid opcode is at debuggee's CS:IP
if ?PM
scratchsel dw 0		;scratch selector ( used by cmds a,c,e,f,g,m,p,t )
 if RING0 and V86M
scratchv86 dw 0
bV86Bp     db 0F4h  ;may be 0F4h or 63h
 endif
bCSAttr db 0		;current code attribute (D bit).
bAddr32 db 0		;1=offset is 32-bit ( segment limit > 0ffffh )
bFlagsPM db 0		;b0: 0=no default set for A cmd, b1 & b2: for ring0, SysReq support
 if RING0
;--- exceptions trapped ( modified by VC/VT ) - fields must be consecutive!
wTrappedExc label word
	dw (1 shl 0) or (1 shl 1) or (1 shl 3) or (CATCHINT06 shl 6) (CATCHINT07 shl 7) or \
		(CATCHINT0C shl 12 ) or (CATCHINT0D shl 13) or (1 shl 14)
	dw (1 shl 0) or (1 shl 1) or (1 shl 3) or (CATCHINT06 shl 6) (CATCHINT07 shl 7) or \
		(CATCHINT0C shl 12 ) or (CATCHINT0D shl 13) or (1 shl 14)
  if FLATSS
bChar   db 0
  endif
 endif
endif
if LCMDFILE or WCMDFILE
fileext	db 0		;file extension (0 if no file name)

EXT_OTHER	equ 1
EXT_COM		equ 2
EXT_EXE		equ 4
EXT_HEX		equ 8
endif

ife RING0

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
PACKET32 struc	; this is for DPMI32 only
secno	dd ?
numsecs	dw ?
dstofs	dd ?
dstseg	dw ?
PACKET32 ends
 endif

	align 2

packet PACKET <0,0,0,0>
 if ?PM
	dw 0	; reserve space for the additional 2 bytes of PACKET32
 endif

endif

if RING0	; vectors in intsave are either real-mode or - if RING0 == 1 - protected-mode
INTVEC textequ <FWORD>
else
INTVEC textequ <DWORD>
endif

;--- order in intsave must match order in inttab

intsave label dword
oldi00	INTVEC 0	;saved vector i00
if RING0 or CATCHINT01
oldi01	INTVEC 0	;saved vector i01
endif
if RING0 or CATCHINT03
oldi03	INTVEC 0	;saved vector i03
endif
if CATCHINT06
oldi06	INTVEC 0	;saved vector i06
endif
if CATCHINT07
oldi07	INTVEC 0	;saved vector i07
endif
if CATCHINT0C
oldi0C	INTVEC 0	;saved vector i0C
endif
if CATCHINT0D
oldi0D	INTVEC 0	;saved vector i0D
endif
if RING0
oldi0E	INTVEC 0	;saved vector i0E
endif
if CATCHSYSREQ
oldisrq	INTVEC 0	;saved vector i09/i15
endif
if INT22
		INTVEC 0	;saved vector i22 ( real-mode only )
endif
if RING0 and CATCHINT41
oldint41 INTVEC 0	;saved vector i41 ( protected-mode only )
endif
if ?DPMI ;must be last
oldi2f	dd 0		; real-mode only
endif

if RING0
int10vec df 0	; (int 10h) output routine
int16vec df 0	; (int 16h) input routine
 if LMODE
jmpv64  label fword
		dd 0
		dw 8	; selector 8 is 64-bit ( Dos32cm )
jmpv161 label fword
		dw offset intrtnp1,0
jmpv161s dw 0	; debugger cs
jmpv162 label fword
	o	dw offset intrtnp2,0
jmpv162s dw 0	; debugger cs
dwBase64 dd 0	; linear address start _TEXT64
 endif
 if FLATSS
dwBase   dd 0	; linear address start _TEXT
 endif
endif

;--- Parameter block for exec call.

if LCMDFILE
EXECS struc
environ dw ?	; +0 environment segment
cmdtail dd ?	; +2 address of command tail to copy
fcb1    dd ?	;+6 address of first FCB to copy
fcb2    dd ?	;+10 address of second FCB to copy
sssp    dd ?	;+14 initial SS:SP
csip    dd ?	;+18 initial CS:IP
EXECS ends

execblk	EXECS {0,0,PSPS.FCB1,PSPS.FCB2,0,0}
endif

REGS struct
rDI		dw ?,?	;+00 edi	; must be in PUSHAD order
rSI		dw ?,?	;+04 esi
rBP		dw ?,?	;+08 ebp
		dw ?,?	;+12 reserved
rBX		dw ?,?	;+16 ebx
rDX		dw ?,?	;+20 edx
rCX		dw ?,?	;+24 ecx
rAX		dw ?,?	;+28 eax

rDS		dw ?	;+32 ds		; check run()/intrtn()/createdummytask() if this order changes!
rES		dw ?	;+34 es
rFS		dw ?	;+36 fs		; v2.0: order changed
rGS		dw ?	;+38 gs
rSS		dw ?	;+40 ss		; should start on a DWORD boundary ( in case AC is on )
rCS		dw ?	;+42 cs
if ?PM
		dw ?	; added ( for 32-bit CS push )
endif

rSP		dw ?,?	;+46 esp
rIP		dw ?,?	;+50 eip
rFL		dw ?,?	;+54 eflags
if RING0
union
r0SSEsp df ?
struct
r0Esp dd ?
r0SS  dw ?
ends
ends
dwErrCode dd ?
endif
if ?DPMI;?PM
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
bInt db ?
wOfs dw ?
INTITEM ends

;--- must match order in intsave

inttab label INTITEM
	INTITEM <00h, @VecAttr intr00>
if CATCHINT01
	INTITEM <01h, @VecAttr intr01>
endif
if CATCHINT03
	INTITEM <03h, @VecAttr intr03>
endif
if CATCHINT06
	INTITEM <06h, @VecAttr intr06>
endif
if CATCHINT07
	INTITEM <07h, @VecAttr intr07>
endif
if CATCHINT0C
	INTITEM <0Ch, @VecAttr intr0C>
endif
if CATCHINT0D
	INTITEM <0Dh, @VecAttr intr0D>
endif
if RING0
	INTITEM <0Eh, @VecAttr intr0E>
endif
if CATCHSYSREQ
	INTITEM <SYSRQINT, intrsrq>
endif
if INT22
	INTITEM <22h, intr22dbg>
endif
if RING0 and CATCHINT41
itab41	INTITEM <41h, intr41>
endif
NUMINTS = ( $ - inttab ) / sizeof INTITEM
if ?DPMI
	db 2Fh
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

ife (BOOTDBG or RING0)
    db '!'      ;additional prompt if InDos flag is set
endif
ifdef PROMPT
prompt1	db @CatStr(!',%PROMPT,!')
else
 if RING0 and V86M
prompt1	db '>'	;indicates v86 mode for DebugRV
 else
prompt1	db '-'	;main prompt
 endif
endif

prompt2	db ':'	;prompt for register value

if ?PM
 if ?DPMI
	db '!'
 endif
prompt3	db '#'	;protected-mode prompt
endif

helpmsg db DBGNAME2, ' v',@CatStr(!',%VERSION,!'),CR,LF
	db 'assemble', TAB, 'A [address]',CR,LF
if BCMD
	db 'clear bp', TAB, 'BC # (#=0|1|2|3)',CR,LF
	db 'set/show bp', TAB, 'BP [address [type]]',CR,LF
endif             
	db 'compare', TAB, TAB, 'C range address',CR,LF
	db 'dump', TAB, TAB, 'D [range]',CR,LF
if DGCMD
	db 'dump GDT', TAB, 'DG selector [count]',CR,LF
endif
if DICMD
 if RING0
	db 'dump IDT', TAB, 'DI interrupt [count]',CR,LF
 else
	db 'dump interrupt', TAB, 'DI interrupt [count]',CR,LF
 endif
endif
if DLCMD
	db 'dump LDT', TAB, 'DL selector [count]',CR,LF
endif
if DMCMD
	db 'dump MCB chain', TAB, 'DM',CR,LF
endif
if DPCMD
	db 'dump partitions', TAB, 'DP physical_disk',CR,LF
elseif DPCMDR0
	db 'dump page table', TAB, 'DP [linear_address]',CR,LF
endif
if DTCMD
	db 'dump TSS', TAB, 'DT [port count]',CR,LF
endif
if DXCMD
	db 'dump ext memory', TAB, 'DX [physical_address]',CR,LF
endif
	db 'enter', TAB, TAB, 'E address [list]',CR,LF
	db 'fill', TAB, TAB, 'F range list',CR,LF
	db 'go', TAB, TAB, 'G [=address] [breakpts]',CR,LF
	db 'hex add/sub', TAB, 'H value1 value2',CR,LF
	db 'input', TAB, TAB, 'I[W|D] port',CR,LF
if LCMDFILE
	db 'load program', TAB, 'L [address]',CR,LF
endif
if BOOTDBG
	db 'load sectors', TAB, 'L address disk sector count',CR,LF
elseife RING0
	db 'load sectors', TAB, 'L address drive sector count',CR,LF
endif
	db 'move', TAB, TAB, 'M range address',CR,LF
	db '80x86 mode', TAB, 'M [x] (x=0..6)',CR,LF
	db 'set FPU mode', TAB, 'MC [2|N] (2=287,N=no FPU)',CR,LF
if LCMDFILE or WCMDFILE
	db 'set name', TAB, 'N [[drive:][path]progname [arglist]]',CR,LF
endif
	db 'output', TAB, TAB, 'O[W|D] port value',CR,LF
	db 'proceed', TAB, TAB, 'P [=address] [count]',CR,LF
if QCMD
	db 'quit', TAB, TAB, 'Q',CR,LF
 if ?DPMI
	db 'forced pm quit', TAB, 'QQ',CR,LF
 endif
endif
	db 'register', TAB, 'R [register [value]]',CR,LF
if ?DPMI
helpmsg2 label byte
endif
if MMXSUPP
	db 'MMX register', TAB, 'RM',CR,LF
endif
	db 'FPU register', TAB, 'RN',CR,LF
	db 'toggle 386 regs', TAB, 'RX',CR,LF
	db 'search', TAB, TAB, 'S range list',CR,LF
if ?DPMI eq 0
helpmsg2 label byte
endif
if RING0
	db 'skip exception', TAB, 'SK',CR,LF
endif
	db 'trace', TAB, TAB, 'T [=address] [count]',CR,LF
	db 'trace mode', TAB, 'TM [0|1]',CR,LF
	db 'unassemble', TAB, 'U [range]',CR,LF
if VXCHG
	db 'view screen', TAB, 'V',CR,LF
endif
if VXCMD
	db 'clr/trap vector', TAB, 'V[C|T] vector [ring]',CR,LF
	db 'list vectors', TAB, 'VL',CR,LF
endif
if WCMDFILE
	db 'write program', TAB, 'W [address]',CR,LF
endif
if WCMD
	db 'write sectors', TAB, 'W address drive sector count',CR,LF
endif
if XCMDS
	db 'expanded mem', TAB, 'XA/XD/XM/XR/XS,X? for help'
endif
if ?DPMI
	db CR,LF,LF
	db "prompts: '-' = real/v86-mode; '#' = protected-mode"
endif
crlf db CR,LF
size_helpmsg2 equ $ - helpmsg2
	db '$'

presskey db '[more]'

errcarat db '^ Error'

ife (BOOTDBG or RING0)
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
elseif BOOTDBG
dskerr1	db "Invalid disk",CR,LF,'$'
dskerrb	db "Read fault",CR,LF,'$'
szNoHD	db "Not a HD",CR,LF,'$'
endif

if LCMD or WCMD
szDrive	db ' ____ing drive '
driveno db 0,0			;drive# for L/W cmds
endif

msg8088	db '8086/88',0
msgx86	db 'x86',0
no_copr	db ' without coprocessor',0
has_copr db ' with coprocessor',0
has_287	db ' with 287',0
regs386	db '386 regs o',0
tmodes	db 'trace mode is '
tmodes2	db '? - INTs are ',0
tmode1	db 'traced',0
tmode0	db 'processed',0
unused	db ' (unused)',0

needsmsg db '[needs x86]'		;<--- modified (7 and 9)
needsmath db '[needs math coprocessor]'
obsolete db '[obsolete]'

;--- exception 00-0E, Int 22h & SysReq messages

int0msg	db 'Divide error',CR,LF,'$'
int1msg	db 'Unexpected single-step interrupt',CR,LF,'$'
int3msg	db 'Unexpected breakpoint interrupt',CR,LF,'$'
if CATCHINT06 or CATCHEXC06
exc06msg db 'Invalid opcode fault',CR,LF,'$'
endif
if CATCHINT07 or CATCHEXC07
exc07msg db 'Coprocessor not present',CR,LF,'$'
endif
if CATCHINT0C or CATCHEXC0C
exc0Cmsg db 'Stack fault',CR,LF,'$'
endif
if CATCHINT0D or ?PM
exc0Dmsg db 'General protection fault',CR,LF,'$'
endif
if ?PM
 if RING0
exc0Emsg db 'Page fault, CR2='
exc0Ecr2 db '________',CR,LF,'$'
 else
exc0Emsg db 'Page fault.',CR,LF,'$'
 endif
endif
if INT22
progtrm	db CR,LF,'Program terminated normally ('
progexit db '____)',CR,LF,'$'
endif
if CATCHSYSREQ
sysrqmsg db 'SysRq detected',CR,LF,'$'
endif

EXC00MSG equ offset int0msg  - offset int0msg
EXC01MSG equ offset int1msg  - offset int0msg
EXC03MSG equ offset int3msg  - offset int0msg
if CATCHINT06 or CATCHEXC06
EXC06MSG equ offset exc06msg - offset int0msg
endif
if CATCHINT07 or CATCHEXC07
EXC07MSG equ offset exc07msg - offset int0msg
endif
if CATCHINT0C or CATCHEXC0C
EXC0CMSG equ offset exc0Cmsg - offset int0msg
endif
if CATCHINT0D or ?PM
EXC0DMSG equ offset exc0Dmsg - offset int0msg
endif
if ?PM
EXC0EMSG equ offset exc0Emsg - offset int0msg
endif
if INT22
INT22MSG equ offset progtrm  - offset int0msg
endif
if CATCHSYSREQ
SYSRQMSG equ offset sysrqmsg - offset int0msg
endif

if EXCCSIP
excloc	db 'CS:IP=',0
endif
if ?DPMI
nodosext db 'Command not supported in protected-mode without a DOS-Extender',CR,LF,'$'
nopmsupp db 'Command not supported in protected-mode',CR,LF,'$'
 if DISPHOOK
dpmihook db 'DPMI entry hooked, new entry=',0
 endif
nodesc	db 'not accessible in real-mode',0
gatewrong db 'gate not accessible',0
endif
if RING0
segerr	db "Debuggee segments invalid",CR,LF,'$'
fpuemerr db "CR0.EM=1, won't run FPU opcodes",CR,LF,'$'
 if QCMD
plerr   db "can't quit protected-mode",CR,LF,'$'
 endif
endif
cantwritebp db "Can't write breakpoint",CR,LF,'$'

if WCMDFILE
nowhexe	db 'EXE and HEX files cannot be written',CR,LF,'$'
nownull	db 'Cannot write: no file name given',CR,LF,'$'
wwmsg1	db 'Writing $'
wwmsg2	db ' bytes',CR,LF,'$'
diskful	db 'Disk full',CR,LF,'$'
endif
if LCMDFILE or WCMDFILE
openerr	db 'Error '
openerr1 db '____ opening file',CR,LF,'$'
doserr2	db 'File not found',CR,LF,'$'
doserr3	db 'Path not found',CR,LF,'$'
doserr5	db 'Access denied',CR,LF,'$'
doserr8	db 'Insufficient memory',CR,LF,'$'
endif

if XCMDS

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
	db '  Allocate', TAB, 'XA count',CR,LF
	db '  Deallocate', TAB, 'XD handle',CR,LF
	db '  Map memory', TAB, 'XM logical-page physical-page handle',CR,LF
	db '  Reallocate', TAB, 'XR handle count',CR,LF
	db '  Show status', TAB, 'XS',CR,LF
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

CONST ends

_TEXT segment

if RING0

;--- get ring0 SS:ESP

getr0stk proc
	.386
	mov eax, cs:[regs.r0Esp]
	mov dx, cs:[regs.r0SS]
 if LMODE
	sub eax, 6*8
	and al, 0F0h	; aligned to 16-byte
 elseif V86M
;--- it's important to generally subtract 10 dwords, regs.rFL will be modified by "skip" and cannot be used
	sub eax, 10*4	; adjust ESP ( ERRC, EIP, CS, EFL, ESP, SS, ES, DS, FS, GS )
 else
	sub eax, 6*4	; adjust ESP ( ERRC, EIP, CS, EFL, ESP, SS )
 endif
	retd
	.8086
getr0stk endp

;--- save/restore GDT descriptor of scratch selector
;--- al=1 -> save, al=0 -> restore
;--- ds=dgroup

srscratch:
	.386
if FLATSS
	sub esp, 6
	sgdt [esp]
else
	mov bp, sp
	sub sp, 6
	sgdt [bp-6]
endif
	movzx esi, [scratchsel]
	pop ax
	pop eax
	add esi, eax
	mov di, offset sdescsave
	push ds
	mov ds, [wFlat]
	cmp al,0
	jz @F
	mov eax, [esi+0]
	mov edx, [esi+4]
	pop ds
	mov [di+0], eax
	mov [di+4], edx
	ret
@@:
	mov eax,cs:[di+0]
	mov edx,cs:[di+4]
	mov [esi+0], eax
	mov [esi+4], edx
	pop ds
	ret

_DATA segment
sdescsave dd 0,0
_DATA ends

endif

if ?DPMI

simrealmodeint proto stdcall :word, :word


_DATA segment
	align 4
;dpmientry dd 0	;dpmi entry point returned by dpmi host
dpmiwatch dd 0	;address of dpmi initial switch to protected mode
dssel     dw 0	;debugger's segment DATA
cssel     dw 0	;debugger's segment CODE - also used as flag if initial switch has occured!
dpmi_rm2pm dd 0	;raw mode switch real-mode to protected-mode
dpmi_pm2rm df 0	;raw mode switch protected-mode to real-mode
dpmi_size  dw 0	;size of raw mode save state buffer
dpmi_rmsav dd 0	;raw mode save state real-mode
dpmi_pmsav df 0	;raw mode save state protected-mode
wOfsSize   dw 0	;size offset (2 or 4) for far16/far32
dpmi32     db 0	;bit 0: 0=16-bit client, 1=32-bit client
bNoHook2F db 0	;1=int 2F, ax=1687h cannot be hooked (win3x/9x dos box, DosEmu?)

;--- pmints and pmvectors must match!
pmvectors label fword	; vectors must be consecutive and in this order!
if CATCHINT41
oldint41  label dword
	dw 0, 0, 0
endif
if CATCHINT31
oldint31  label dword
	dw 0, 0, 0
endif
if CATCHINT21
oldint21  label dword
	dw 0, 0, 0
endif

_DATA ends

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
;	call cs:[dpmientry]	;call the REAL dpmi entry
	db 9ah		; opcode call ssss:oooo
dpmientry dd 0
	jnc initdpmi
	retf

	.286

CONST segment

pmints label byte     ;pmints and pmvectors must match!
if CATCHINT41
	db 41h
	dw intr41pm
endif
if CATCHINT31
	db 31h
	dw intr31pm
endif
if CATCHINT21
	db 21h
	dw intr21pm
endif
LPMINTS equ ($ - offset pmints) / 3

if 0	;v2.0: removed
convsegs label word
;	dw offset run_cs
;	dw offset pInDOS+2
;if USESDA
;	dw offset pSDA+2
;endif
	dw offset a_addr+4
	dw offset d_addr+4
NUMSEGS equ ($-convsegs)/2
endif

exctab label byte	; DPMI exception table
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
endexctab label byte

CONST ends

_DATA segment
dbeexc0d0e label word	; saved debuggee's exc 0d/0e when debugger is entered
	dw 2 dup (0,0,0)
_DATA ends

;--- client entered protected mode.
;--- inp: [sp+4] = client real-mode CS

INSTFRM struct
	org -2
_ds	dw ?			; client's DS ( selector )
	dw 8 dup (?)	; pusha
;_ret dw ?			; return addr initdpmi()
_ip	dw ?			; client's IP
_cs	dw ?			; client's CS
INSTFRM ends
    
initdpmi proc
	pusha
	mov bp,sp
	push ds
	mov bx,cs
	mov ax,000Ah	;get a data descriptor for DEBUG's segment
	int 31h
	jc fataldpmierr
	mov ds,ax
	@dprintf "initdpmi: client entered pm"
	mov [cssel],cs
	mov [dssel],ds
	mov cl, 90h
	mov ax, 200h
	cmp [machine],3		; is at least a 80386?
	jb @F
	mov dx, ss
	.386
	push edx
	lar edx, edx
	shr edx, 23
	pop edx
	.286
	adc al,0
	jz @F
	mov cl, 66h
	mov ah, 4
@@:

	mov [dpmi32], al
	mov byte ptr [wOfsSize], ah
if CATCHINT21
	mov [patchint21pm], cl
endif
if CATCHINT31
	mov [patchint31pm], cl
endif
if CATCHINT41
	mov [patchint41pm], cl
endif
	mov [patchiretpm], cl
	mov [patchfarretpm], cl
	mov [patchfarretpmval], ah
	mov [patchrmswitch], cl
	mov [patchsrstate], cl

	mov cx,2		;alloc 2 descriptors
	xor ax,ax
	int 31h
	jnc @F
fataldpmierr:
	mov ax,4CFFh
	int 21h
@@:
	mov [scratchsel],ax	;the first is used as scratch descriptor
	xchg bx,ax			; mov bx, ax
	xor cx,cx
	cmp [machine], 3	; is at least a 80386?
	jb @F
;	test [dpmi32], 1	; 32-bit client?
;	jz @F
	dec cx				; then limit=ffffffff
@@:
	or dx,-1
	mov ax,0008h
	int 31h
	add bx,8		;the second selector is client's CS
	xor cx,cx		;this limit is FFFF even for 32-bits
	mov ax,0008h
	int 31h
	mov dx,[bp].INSTFRM._cs	; get client's CS
	call setrmaddr			; set base
	mov ax,cs
	lar cx,ax
	shr cx,8				; CS remains 16-bit
	mov ax,0009h
	int 31h
	mov [bp].INSTFRM._cs,bx	; set client's CS
if FMTEXE
	mov bx, [pspdbg]
	mov ax, 2
	int 31h
	mov [pspdbgpm], ax
endif

if 1
;--- v2.0: (re)init default for d cmd
	mov ax, [bp].INSTFRM._ds
	mov [d_addr+4], ax
	mov [bFlagsPM], 0		; reset all pm flags
endif

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

if 0	; v2.0: removed, default for a/d cmds see above
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
endif

	sizeprf			; push edi - save hiword(edi)
	push di

	mov bp,[wOfsSize]	; get offset size for far16/far32
	mov ax,0305h			; get raw-mode save state addresses
	int 31h
	mov word ptr [dpmi_rmsav+0],cx
	mov word ptr [dpmi_rmsav+2],bx
	sizeprf					; mov dword ptr [dpmi_pmsav],edi
	mov word ptr [dpmi_pmsav],di
	mov word ptr ds:[bp+dpmi_pmsav],si
	mov word ptr [dpmi_size],ax
	mov ax,0306h			; get raw-mode switch addresses
	int 31h
	mov word ptr [dpmi_rm2pm+0],cx
	mov word ptr [dpmi_rm2pm+2],bx
	sizeprf					; mov dword ptr [dpmi_pm2rm],edi
	mov word ptr [dpmi_pm2rm],di
	mov word ptr ds:[bp+dpmi_pm2rm],si

	sizeprf			; pop edi - restore hiword(edi)
	pop di

;--- hook exceptions 0,1,3,6,(7),(C),D,E

	cld
	mov si,offset exctab
	sizeprf			; push edx - save hiword(edx)
	push dx
	sizeprf			; xor edx,edx
	xor dx,dx
	mov dx,offset exc00
@@:
	lodsb
	mov bl,al
	mov cx,cs
	mov ax,203h
	int 31h
	add dx,exc01-exc00
	cmp si,offset endexctab
	jb @B

;--- hook DPMI protected-mode interrupts

if LPMINTS
	mov si, offset pmvectors
	mov di, offset pmints
	mov cx, LPMINTS
nextpmint:
	mov bl, cs:[di]
	push cx
	mov ax, 204h
	int 31h
	sizeprf	;mov [si], edx
	mov [si], dx
	mov ds:[si+bp], cx
	sizeprf	;xor edx, edx
	xor dx, dx
	mov dx, [di+1]
	mov cx, cs
	mov al, 5
	int 31h
	add si, sizeof fword
	add di, 3
	pop cx
	loop nextpmint
endif

	sizeprf				; pop edx - restore hiword(edx)
	pop dx

	mov bl,2Fh			;get int 2Fh real-mode vector
	mov ax,200h
	int 31h
	cmp cx,[wDgroup]	;did we hook it and are the last in chain?
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
	retf

initdpmi endp

;--- v2.0: set/reset debugger's exception vectors for 0D/0E. Since the
;--- debugger very easily causes those exceptions, and the debuggee might
;--- have set the vectors to its own routines, it's a must to restore them
;--- to debugger code while the debugger is active.

;--- setdbeexc0d0e: set debuggee's exception 0d/0e when running it

setdbeexc0d0e proc
	call ispm_dbe
	jz done
	mov si, offset dbeexc0d0e
	mov bl, 0dh
nextexc:
	sizeprf	; lodsd
	lodsw
	sizeprf	; mov edx, eax
	mov dx, ax
	lodsw
	mov cx, ax
	jcxz @F
	mov ax, 0203h
	int 31h
@@:
	inc bl
	cmp bl, 0eh
	jbe nextexc
done:
	ret
setdbeexc0d0e endp

;--- set debugger's exception 0d/0e when reentering it
;--- for int 31h, ax=203h, flag [bInDbg] must be 1 if CATCHINT31 is active.

setdbgexc0d0e proc
	call ispm_dbe
	jz done
	mov di, offset dbeexc0d0e
	mov si, offset exc0d
	mov bl, 0dh
@@:
	mov ax, 0202h
	int 31h
	sizeprf
	mov ax, dx
	sizeprf
	stosw
	mov ax, cx
	stosw
	sizeprf			; movzx edx, si
	lea dx, [si]
	mov cx, cs
	mov ax, 0203h
	int 31h
	add si, exc01-exc00
	inc bl
	cmp bl, 0eh
	jbe @B
done:
	ret
setdbgexc0d0e endp

	include <TRAPD.INC>

if CATCHINT21
intr21pm proc
	cmp ah,04Ch
	jz is4c
prevint21:
patchint21pm db 66h	; jmp fword ptr cs:[oldint21]
	jmp cs:[oldint21]
is4c:
	push ds
	mov ds, cs:[dssel]
	call exitdpmi
	pop ds
	jmp prevint21
intr21pm endp
endif

if CATCHINT31
intr31pm proc
	cmp cs:[bInDbg],0; v2.0 do nothing if debugger is active
	jnz notinterested
	cmp ax,0203h	; set exception vector?
	jz is203
	cmp ax,0212h	; v2.0: set exception vector v1.0?
	jz is212
notinterested:
patchint31pm db 66h	; jmp fword ptr cs:[oldint31]
	jmp cs:[oldint31]
is203:
is212:
	cmp bl,1
	jz @F
	cmp bl,3
	jz @F
	cmp bl,0Dh
	jz @F
	cmp bl,0Eh
	jnz notinterested
@@:
;	jmp execiret
intr31pm endp
endif

;--- fall thru!

execiret:
patchiretpm db 66h		; iretd
	iret

i23pm:
i24pm:
	clc
patchfarretpm db 66h
	retf 2
patchfarretpmval equ byte ptr ($ - 2)

	.8086

endif	;?DPMI

if CATCHINT41
 if ?DPMI
intr41pm:
 endif
intr41 proc
	cmp ax, 004Fh
	jz is4f
 if ?DPMI
patchint41pm db 66h
 endif
	jmp cs:[oldint41]
is4f:
	mov ax, 0F386h
 if ?DPMI
	jmp execiret
 else
	iretd
 endif
intr41 endp
endif

if INT22

;   intr22dbg - INT 22 (Program terminate) interrupt handler.
;   This is for DEBUG itself:  it's a catch-all for the various INT 23
;   and INT 24 calls that may occur unpredictably at any time.
;   What we do is pretend to be a command interpreter (which we are,
;   in a sense, just a different sort of command) by setting the PSP of
;   our parent equal to our own PSP so that DOS does not free our memory
;   when we quit.  Therefore control ends up here when Control-Break or
;   an Abort in Abort/Retry/Fail is selected.

intr22dbg:
	cld			;reestablish things
	mov ax,cs
	mov ds,ax
	mov ss,ax
elseif RING0
 if 0
entercmd:
	mov ds, cs:[wDgroup]
	push ds
	pop ss
 endif
endif

;--- fall through to cmdloop!

;--- Begin main command loop.

cmdloop proc
if FLATSS
	mov esp,[top_sp]	;restore stack (this must be first)
else
	mov sp,[top_sp]		;restore stack (this must be first)
endif
	mov [errret],offset cmdloop
	push ds
	pop es

	cmp [bInDbg], 1
	jz @F
	mov ax, 0e07h
	int 10h
@@:

if LCMDFILE
	call isdebuggeeloaded
	jnz @F
	call createdummytask	;if no task is active, create a dummy one
@@:
endif
	mov cx,1
ife ?PM
	mov dx,offset prompt1
else
 if ?DPMI or ( RING0 and V86M )
	mov dx,offset prompt1
	call ispm_dbe			; debuggee in rm/pm?
	jz @F
 endif
	mov dx,offset prompt3
@@:
endif
ife (BOOTDBG or RING0)
	call InDos
	jz @F
 ife VXCHG
	mov ah, 0Fh
	int 10h
	mov [vpage], bh ;ensure [vpage] is initialized if InDos is set
 endif
	dec dx          ;if inside DOS, display a '!' before the real prompt
	inc cx
@@:
endif
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
	mov ah,[si-2]	; v2.0: for easily detecting 2-byte cmds
	or ah, TOLOWER
cmd4:
	sizeprfX		;clear ecx - needed for cmds that call getrange
	xor cx,cx
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
if REDIRECT
	test [fStdin], AT_DEVICE	;stdin a file?
	jz nowait
	test [fStdout], AT_DEVICE	;stdout a file?
	jz nowait
endif
	push ds
ife RING0
	mov ax,40h		;0040h is a bimodal segment/selector
	mov ds,ax
	cmp byte ptr ds:[84h],30	;rows >= 30?
else
	mov ds, [wFlat]
	cmp byte ptr ds:[484h], 30
endif
	pop ds
	jnc nowait
	mov dx,offset presskey
	mov cx,sizeof presskey
	call stdout
;	mov ah,8		;use DOS
;	int 21h
	mov ah,0		;v1.27: use BIOS
if RING0
	.386
	call cs:[int16vec]
	.8086
else
	int 16h
endif
	mov al,CR
	call stdoutal
nowait:
	ret
waitkey endp

@movs macro dst, src
if RING0 and V86M
	push src
	call v86setofs
	pop dst
else
	mov dst, src
endif
endm

@dispsegm macro segm
	mov ax,segm
if RING0 and V86M
	call chkdispsegm
else
	call hexword
endif
endm

	include lineasm.inc

if ?PM
;--- called by c_cmd, e_cmd, f_cmd, m_cmd, s_cmd
IsOfs32 proc
	cmp cs:[bAddr32],0
	ret
IsOfs32 endp
endif

;--- C command - compare bytes.

c_cmd proc
	call parsecm		;parse arguments (sets DS:e/si, ES:e/di, e/cx)
;--- note: DS unknown here
if ?PM
	call IsOfs32
	jz $+3
	db 66h	;inc ecx
endif
	inc cx
cc1:			;<--- continue compare
if INT2324
	push ds
	push ss		;ds=DGROUP
	pop ds
	call dohack	;set debuggee's int 23/24
	pop ds
endif
if ?PM
	call IsOfs32
	jz $+3
	db 67h	;repe cmpsb ds:[esi],es:[edi]
endif
	repe cmpsb
	lahf

;--- v2.0: "mov dl,[si-1]" and "mov dl,[esi-1]" differ not just in the prefix!
;--- mov dl, [si-1]:    8A 54 FF
;--- mov dl,[esi-1]: 67 8A 56 FF

if ?PM
	call IsOfs32
	jz @F
	.386
	mov dl,[esi-1]
	mov dh,es:[edi-1]
	.8086
	jmp c_cont
@@:
endif
	mov dl,[si-1]	;save the possibly errant characters
	mov dh,es:[di-1]
c_cont:
if INT2324
	push ds
	push ss
	pop ds
	call unhack	;set debugger's int 23/24
	pop ds
endif
	sahf
	jne @F
	jmp cc2		;if we're done
@@:
	push cx
	push es

;--- set ES to dgroup ( needed for output routines )
	@RestoreSeg es
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
	call IsOfs32
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
;--- set DS to dgroup
	@RestoreSeg ds
	push bx
	call putsline
	pop di
	pop ds

	pop es
	pop cx
if ?PM
	call IsOfs32
	jz $+3
	db 67h	;jecxz cc2
endif
	jcxz cc2
	jmp cc1		;if not done yet
cc2:
	@RestoreSeg ds
	push ds
	pop es
	ret
c_cmd endp

if DPCMD or DPCMDR0

dp_cmd proc

 if DPCMDR0

	.386
 
CONST segment
szCr3 db "CR3=",0
szMappedCr3 db ", mapped at ",0
CONST ends

	mov si, offset szCr3
	call copystring
	mov eax, cr3
	call hexdword
	mov esi, cr3
	and si, 0F000h	;esi=physical address
	mov cx, 4	; cx=size in bytes
	mov ax, 2	; return linear address (in esi) of physical region

;--- callout int 22h requires to set the host ring0 stack!

	mov bp, sp
	mov dx, ss
	lss esp, [r0SSEsp]
	int 22h		; win396 debugger interface
	mov ss, dx
	mov sp, bp

	cmp ax, 1
	jnz exit
	push esi
	mov si, offset szCr3
	call copystring
	pop eax
	call hexdword
exit:
	call putsline
	ret

 else

;--- DP disk - display partition table of a fixed disk

	call getbyte		;get byte into DL
	call chkeol			;expect end of line here
	mov bp, sp
	mov al, dl
	mov dx, offset szNoHD
	and al, al
	jns error
	sub sp, 512
	mov word ptr packet.secno+0, 0
	mov word ptr packet.secno+2, 0
	mov packet.numsecs, 1
	mov packet.dstofs, sp
	mov packet.dstseg, ds
	call readsect
	jc error
	add sp, 1BEh	; offset PT
	mov si, sp
	mov cx, 4
nextp:
	push cx
	mov di, offset line_out
	mov ax, ' 4'
	sub al, cl
	stosw
	mov al, [si+4]	; partition type
	call hexbyte
	mov al, ' '
	stosb
	mov ax, [si+10]	; hiword start LBA
	call hexword
	mov ax, [si+8]	; loword start LBA
	call hexword
	mov al, ' '
	stosb
	mov ax, [si+14]	; hiword size LBA
	call hexword
	mov ax, [si+12]	; loword size LBA
	call hexword
	call putsline
	pop cx
	add si, 16
	loop nextp
	mov sp, bp
	ret
error:
	mov sp, bp
	call int21ah9
	ret
 endif
dp_cmd endp
endif

if RING0

;--- get base of descriptor table for selector in BX
;--- out: NC, eax=base, dx=limit
;---       C if error
;--- other registers preserved

	.386

getlinearbaseDT proc
if FLATSS
	sub esp, 6
	sgdt [esp]
else
	push bp
	mov bp, sp
	sub sp, 6
	sgdt [bp-6]
endif
;	mov dx, [bp-6]
;	mov eax, [bp-4]	; get linear address GDT
	@dprintf "getlinearbaseDT: bx=%X", bx
	pop dx
	pop eax
	test bl, 4
	jz isgdt
	push bx
	sldt bx
	@dprintf "getlinearbaseDT: ldt=%X", bx
	call getlinearbaseBX
	@dprintf "getlinearbaseDT: eax=%lX", eax
	pop bx
isgdt:
	push ax
	lar ax, bx
	setnz al
	shr al,1
	pop ax
ife FLATSS
	pop bp
endif
	ret
getlinearbaseDT endp

;--- get linear base of descriptor in BX
;--- in: BX=selector, EAX=base of descriptor table
;--- out: EAX=base of descriptor, DX=limit of descriptor

getlinearbaseBX proc
	movzx edx, bx
	and dl, 0f8h
	add eax, edx	; now eax -> GDT/LDT descriptor
	push ds
	mov ds, [wFlat]
	mov dl, [eax+4]
	mov dh, [eax+7]
	shl edx, 16
	mov dx, [eax+2]
	mov ax, [eax+0]
	xchg eax, edx	; base to eax, limit to dx
	pop ds
	ret
getlinearbaseBX endp

endif

if DGCMD or DLCMD

 if RING0
CONST segment
szldtr db "LDTR=",0
szgdtr db "GDTR=",0
CONST ends
 endif

;--- DG/DL commands
;--- ah = 'l' or 'g'

CONST segment
descbase db ' base=???????? limit=???????? attr=????',0
CONST ends

dgl_cmd proc

	push ax
	call getword	;get word into DX
	pop cx
	mov bx, dx

	and bl, 0f8h
 if DGCMD
	cmp ch, 'g'
	jz @F
 endif
	or bl, 4
@@:
	call skipcomm0
	mov dx,1
	cmp al,CR
	jz @F
	call getword
	and dx,dx
	jnz @F
	inc dx
@@:
	mov si, dx		;save count
if RING0
 if FLATSS
	mov ebp, esp
 else
	mov bp, sp
 endif
	call getlinearbaseDT	; get linear base & limit of descriptor table for BX
	.386
	push eax
	push dx
	pushf         ; save error flag of getlinearbase
	push si
	test bl,4
	jz @F
	mov si, offset szldtr
	call copystring
	sldt ax
	call hexword
	jmp ldtrdone
@@:
	mov si, offset szgdtr
	call copystring
 if FLATSS
	mov ax,[ebp-6]
 else
	mov ax,[bp-6]
 endif
	call hexword
	mov al,'.'
	stosb
 if FLATSS
	mov eax,[ebp-4]
 else
	mov eax,[bp-4]
 endif
	call hexdword
ldtrdone:
	call putsline
	pop si
	popf
	jnc @F
	test bl,4
	jz @F
	jmp done
@@:
endif
if ?DPMI
	.286
	call ispm_dbg
	jnz nextdesc
	mov si,offset nodesc	; error "not accessible in real-mode"
	call copystring
	jmp putsline
endif

nextdesc:
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
 if ?DPMI
	mov ax,6
	int 31h
	jc @F
 elseif RING0
	.386
  if FLATSS
	cmp bx, [ebp-6]	;beyond limit?
  else
	cmp bx, [bp-6]	;beyond limit?
  endif
	jae nogdt
	push ds
	movzx eax, bx
	and al, 0F8h
  if FLATSS
	add eax, [ebp-4]
  else
	add eax, [bp-4]
  endif
	mov ds, [wFlat]
	mov dx, [eax+2]
	mov cl, [eax+4]
	mov ch, [eax+7]
	.286
	pop ds
	stc
nogdt:
	jnc done
	lar ax, bx
	jnz desc_out
 endif
	add di, 6	; render base
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
	call hexdword; limit 32-bit
	jmp desc_o2
@@:
	call hexword; limit 16-bit
	mov ax,"  "
	stosw
	stosw
desc_o2:
	mov di,offset line_out+25+14
	mov ax,dx
	call hexword; attr   
desc_out:
	mov di,offset line_out+25+14+4 ; position to end of line
	call putsline	; add cr/lf, then print
	add bx,8
	dec si
	jnz nextdesc
done:
if RING0
 if FLATSS
	.386
	mov esp, ebp
 else
	mov sp, bp
 endif
endif
	ret
dgl_cmd endp

endif

if DICMD

 if RING0
CONST segment
szidtr db "IDTR=",0
CONST ends
 endif

 if RING0
GATE struct
wOfsLo dw ?
wSeg   dw ?
wAttr  dw ?
wOfsHi dw ?
GATE ends
 endif

;--- DI command

di_cmd proc
	call getbyte	;get byte into DL
	mov bx,dx
	call skipcomm0
	mov dx,1
	cmp al,CR
	jz @F
	call getword	;get word into DL ( max is 100h )
	call chkeol
	and dx,dx
	jnz @F
	inc dx			;ensure that count is at least 1
@@:
	mov si,dx		;save count
if RING0
	sidt [real_end-6]
	push si
	mov si, offset szidtr
	call copystring
	pop si
	mov ax,word ptr [real_end-6]
	call hexword
	mov al,'.'
	stosb
	.386
	mov eax,dword ptr [real_end-4]
	call hexdword
	call putsline
endif
	call prephack
gateout_00: 		;<--- next int/exc
	mov di,offset line_out
	mov al,bl
	call hexbyte
	mov al,' '
	stosb
if ?PM
 if ?DPMI
	call ispm_dbe
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
	test [dpmi32],1
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
 else
	.386
	push bx
	movzx ebx, bl
 if V86M
	mov dl, bl
 endif
 if LMODE
	shl bx, 4
 else
	shl bx, 3
 endif
	cmp bx, word ptr [real_end-6]
	ja di_done
	add ebx, dword ptr [real_end-4]
	push ds
	mov ds, [wFlat]
	mov ax, [ebx].GATE.wSeg
	call hexword
	mov al, ':'
	stosb
	mov ax, [ebx].GATE.wOfsHi
	call hexword
	mov ax, [ebx].GATE.wOfsLo
	call hexword
	mov eax, '=ta '
	stosd
	mov ax, [ebx].GATE.wAttr
	call hexword
 if V86M
	mov eax, "=vi "
	stosd
	movzx ebx, dl
	mov ax, [ebx*4+2]
	call hexword
	mov al,':'
	stosb
	mov ax, [ebx*4+0]
	call hexword
 endif
	.8086
	pop ds
	pop bx
 endif
else
	jmp gaterm
endif
gate_exit:
	call putsline
	inc bl
	jz di_done
	dec si
	jnz gateout_00
di_done:
	ret
if ?DPMI
gatefailed:
	mov di,offset line_out
	mov si,offset gatewrong
	call copystring
	mov si,1
	jmp gate_exit
endif
gaterm:
	call dohack		;set debuggee's int 23/24
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
	call unhack		;set debugger's int 23/24
	call hexword
	mov al,':'
	stosb
	mov ax,dx
	call hexword
	jmp gate_exit
di_cmd endp

endif

	.8086

if DMCMD

;--- dm cmd: display list of MCBs
;--- DI=lineout

dm_cmd proc
;	mov di,offset line_out
	mov ax,"SP"
	stosw
	mov ax,":P"
	stosw
	mov ax,[pspdbe]
	call hexword
	call putsline	;destroys cx,dx,bx

	mov si,[wMCB]
	push ds
nextmcb:
	mov di,offset line_out
	call setds2si
	mov ax,si
	call hexword	;segment address of MCB
	mov al,' '
	stosb
	mov al,ds:[0000];'M' or 'Z'
	cmp al,'Z'
	jz @F
	cmp al,'M'
	jnz mcbout_done
@@:
	call hexbyte
	mov al,' '
	stosb
	mov ax,ds:[0001];MCB owner
	mov bx,ax
	call hexword
	mov al,' '
	stosb
	mov ax,ds:[0003];MCB size in paragraphs
	mov dx,ax
	call hexword
	mov al,' '
	stosb
	and bx,bx
	jz mcbisfree
	push si
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
	pop si
mcbisfree:
	add si,dx
	jc mcbout_done
	inc si
	pop ds
	push ds
	call putsline	;destroys cx,dx,bx
	jmp nextmcb
mcbout_done:
	pop ds
	ret

setds2si:
	mov bx,si
setds2bx:
if ?DPMI
	call ispm_dbe
	jz sd2s_ex
	mov dx,bx
	call setrmsegm
sd2s_ex:
endif
	mov ds,bx
	ret
dm_cmd endp

endif

if DTCMD

 ife LMODE

;--- "legacy TSS"

TSS struct
dwLink	dd ?	;+00 selector
_Esp0	dd ?	;+04
_SS0    dd ?
dqStk1	dq ?	;+0C
dqStk2	dq ?	;+14
_CR3	dd ?	;+1C
_Eip	dd ?	;+20
_Efl	dd ?	;+24
_Eax	dd ?	;+28
_Ecx	dd ?	;+2C
_Edx	dd ?	;+30
_Ebx	dd ?	;+34
_Esp	dd ?	;+38
_Ebp	dd ?	;+3C
_Esi	dd ?	;+40
_Edi	dd ?	;+44
_ES		dd ?	;+48
_CS		dd ?	;+4C
_SS		dd ?	;+50
_DS		dd ?	;+54
_FS		dd ?	;+58
_GS		dd ?	;+5C
_LDT	dd ?	;+60
wFlags  dw ?	;+64
wOffs   dw ?	;+66
TSS ends

 else

;--- long mode TSS

TSS struct
		dd ?	;+00
_Rsp0	dq ?	;+04
_Rsp1	dq ?	;+0C
_Rsp2	dq ?	;+14
		dd ?	;+1C
_Ist1	dq ?	;+24
_Ist2	dq ?	;+2C
_Ist3	dq ?	;+34
_Ist4	dq ?	;+3C
_Ist5	dq ?	;+44
_Ist6	dq ?	;+4C
_Ist7	dq ?	;+54
		dq ?	;+5C
		dw ?	;+64
wOffs   dw ?	;+66
TSS ends
 endif

CONST segment
if LMODE
szPL0Stk db " RSP0=",0
else
szPL0Stk db " R0 SS:ESP=",0
endif
szIOPB db " IOPB=",0
szTrapped db "trapped ports:",13,10,'$'
CONST ends
 
dt_cmd proc
	.386
	xor dx, dx
	cmp al,CR
	jz @F
	call getword	;get word into DX
	call skipcomm0
	cmp al,CR
	jz cmd_error
	mov bp, dx
	call getword	;get word into DX
	call skipcomm0
	cmp al,CR
	jnz cmd_error
@@:
	mov si, dx
	mov ax,"RT"
	stosw
	mov al,'='
	stosb
	str ax
	mov bx, ax
	call hexword
	cmp bx,0
	jz done
	call getlinearbaseDT	;TSS is always in GDT
	jc done
	call getlinearbaseBX	;ret: eax=linear addr, dx=limit
	@dprintf "dt: bx=%X eax=%lX, limit=%X", bx, eax, dx
	mov ebx, eax
	push si
	mov si, offset szPL0Stk
	call copystring
	pop si
	push ds
	mov ds, [wFlat]
if LMODE
	mov eax, dword ptr [ebx].TSS._Rsp0+4
	call hexdword
	mov eax, dword ptr [ebx].TSS._Rsp0+0
	call hexdword
else
	mov ax, word ptr [ebx].TSS._SS0
	call hexword
	mov al,':'
	stosb
	mov eax, [ebx].TSS._Esp0
	call hexdword
endif

;--- display trapped ports;

;--- check if TSS does indeed include an IO permission bitmap.
;--- DX=limit TSS
;--- BP=port to start with
;--- SI=number of ports to check

	mov ax, bp
	add ax, si
	add ax, 8-1
	shr ax, 3
	add ax, [ebx].TSS.wOffs
	cmp dx, ax
	jc done

	movzx eax, [ebx].TSS.wOffs
	pop ds
	add eax, ebx
	push ax
	push si
	mov si, offset szIOPB
	call copystring
	pop si
	pop ax
	mov ebx, eax
	call hexdword
	cmp si, 0
	jz done
	@dprintf "dt_cmd: start port=%X cnt=%X", bp, si
	call putsline
	mov di, offset line_out
	mov dx, offset szTrapped
	call int21ah9
	mov cx, si
	movzx ebp, bp
	mov dl,0
nextport:
	push ds
	mov ds, [wFlat]
	bt [ebx], ebp
	pop ds
	jnc @F
	@dprintf "dt_cmd: found trapped port=%X", bp
	mov ax, bp
	call hexword
	mov al,' '
	stosb
	inc dl
	test dl, 7
	jnz @F
	pusha
	call putsline
	popa
	mov di, offset line_out
@@:
	inc bp
	loopnz nextport
done:
	call putsline
	ret
dt_cmd endp

endif

;--- DX command. Display extended memory
;--- works for 80386+ only.

if DXCMD

if USEUNREAL

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
	cli
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
	sti
	ret

	.386

;--- exception 0D: 

int0d:
if 1
	push ax         ; check for IRQ. If request, jmp to previous handler
	mov al, 0Bh
	out 20h, al
	in al, 20h
	test al, 20h	; real IRQ 5?
	pop ax
	jz @F
	db 0eah
oldint0d dd ?
@@:
endif
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

dx_cmd proc
	cmp [machine],3
	jb cmd_error
	.386
	mov dx,word ptr [x_addr+0]
	mov bx,word ptr [x_addr+2]
	cmp al,CR
	jz @F
	call getdword	;get linear address into bx:dx
	call chkeol		;expect end of line here
@@:
	mov [lastcmd],offset dx_cmd
	push bx
	push dx
	pop ebp

if USEUNREAL
;--- the dx cmd, when using int 15h,ah=87, has the
;--- side effect that unreal-mode most likely is disabled
;--- after the call. Setting USEUNREAL=1 avoids that,
;--- but has the disadvantange that DX won't work in v86-mode!

	smsw ax			; don't use ispm, since that won't detect v86! 
	test al,1
	jnz dx_exit
	push ds
	push cs
	push offset int0d
	pop eax
	xor ecx,ecx
	mov ds,cx
	mov ebx, ds:[0dh*4]
	mov cs:[oldint0d], ebx
	mov ds:[0dh*4], eax
	mov esi,ebp
	mov al,1
	mov cl,20h
	mov edi,offset line_out+128
	rep movsd es:[edi], ds:[esi]
	mov ds:[0dh*4], ebx
	dec al    ;has an exception occured?
	jz @F     ;if no, don't reset unreal mode!
	mov cx,SEL_DATA16
	call setdspm
@@:
	pop ds
else
;	mov di,offset line_out	;create a GDT for Int 15h, ah=87h
	xor ax,ax
	mov cx,6*4	;init 6 descriptors (48 bytes)
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
	movzx ebx,[wDgroup]
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
	mov si,offset line_out ;ds:si -> GDT
	mov cx,0040h	;number of words to copy
	mov ah,87h
 if ?DPMI
	call ispm_dbg
	jz @F
	invoke simrealmodeint, 15h, cs:[wDgroup]
	jmp i15ok
@@:
 endif
	int 15h
i15ok:
	jc dx_exit
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
dx_exit:
	ret
	.8086
dx_cmd endp

endif

if RING0 and V86M
chkdispsegm proc
	test byte ptr[regs.rFL+2],2
	jz @F
	cmp ax, [scratchsel]
	jnz @F
	mov ax, [scratchv86]
@@:
	jmp hexword
chkdispsegm endp
endif

;--- D command - hex/ascii dump.

d_cmd proc
	cmp al,CR
	jne dd1		; if an argument was given
	sizeprfX	; mov edx,[d_addr]
	mov dx,[d_addr]
	mov bx, [d_addr+4]
if RING0
	verr bx
	jz @F
	@movs bx, [regs.rDS]
	xor edx, edx
@@:
endif
	sizeprfX	; mov esi,edx
	mov si,dx

;--- ?PM: we don't know yet if limit is > 64kB
;--- so we stop at 64 kB in any case

	add dx,80h-1; compute range of 80h or until end of segment
	jnc dd2
	or dx, -1
	jmp dd2

DMPJT struct
pDispOfs dw ?	; display offset 16/32 
pGetB    dw ?	; get # of bytes to print in cx
pLoad    dw ?	; load a byte
pEnd     dw ?	; check if dump is done
DMPJT ends

CONST segment
dd16 DMPJT < hexword, getb16, load16, end16>
if ?PM
dd32 DMPJT <hexdword, getb32, load32, end32>
endif
CONST ends

ife DGCMD+DICMD+DLCMD+DPCMD+DTCMD+DXCMD	; if just the DM cmd exists (std debug)

dd1:
	cmp ah,'d'	; char 'd' just before g/i/l/m/p/t/x?
	jnz dd1_1
	or al,TOLOWER
 if DMCMD
	cmp al,'m'
	jz dm_cmd
 endif

else

@condcmd macro ifcond, byt_,ofs_
if ifcond
	db byt_
	dw offset ofs_
endif
endm

CONST segment
dcmds label byte
	@condcmd DGCMD,'g',dgl_cmd
	@condcmd DICMD,'i',di_cmd
	@condcmd DLCMD,'l',dgl_cmd
	@condcmd DMCMD,'m',dm_cmd
	@condcmd DPCMD or DPCMDR0,'p',dp_cmd
	@condcmd DTCMD,'t',dt_cmd
	@condcmd DXCMD,'x',dx_cmd
size_dcmds equ ($ - offset dcmds) / 3
CONST ends

d_subcmd:
	mov ah, al
	call skipwhite
	jmp word ptr [bx+1]
dd1:
	cmp ah,'d'	; char 'd' just before g/i/l/m/p/t/x?
	jnz dd1_1
	or al,TOLOWER
	mov bx, offset dcmds
	mov cx, size_dcmds
@@:
	cmp al,[bx]
	jz d_subcmd
	add bx, 3
	loop @B
endif

if FLATSS
DMPPFX textequ <cs:>
else
DMPPFX textequ <>
endif

dd1_1:
	mov cx,80h		;default length
	call getrangeDS	;get address range into bx:(e)dx ... bx:(e)cx
	call chkeol		;expect end of line here

	sizeprfX	; mov esi,edx
	mov si,dx
	sizeprfX	; mov edx,ecx (14.2.2021)
	mov dx,cx	; dx = end address
    
;--- Parsing is done.  Print lines.
;--- BX=segment/selector
;--- E/SI=src offset, E/DX=end src

dd2:
	mov [d_addr+4], bx	;save segment/selector (offset is saved later)
	mov [lastcmd], offset d_cmd
	mov bp, offset dd16
if ?PM
	call getseglimit	;Z flag set if segment limit is <= 64 kB
	jz @F
	mov bp, offset dd32
@@:
endif
	@dprintf "d: bx:esi=%X:%lX edx=%lx", bx, esi, edx
	call prephack	;set up for faking int vectors 23 and 24

nextline:
	mov di,offset line_out
	@dispsegm [d_addr+4]
	mov al,':'
	stosb
	sizeprfX		; mov eax, esi
	mov ax, si
	and al, 0f0h
	mov cx, si
	sub cx, ax
	call DMPPFX[bp].DMPJT.pDispOfs
;--- blank the line
	mov ax,'  '
	stosw
	lea bx, [di+3*16]
	add bx, cx
	push cx
	push di
	mov cx, bx
	sub cx, di
	rep stosb
	pop di
	pop cx
	mov byte ptr [di+3*8-1],'-'
	add di,cx
	add cx,cx
	add di,cx

	call DMPPFX[bp].DMPJT.pGetB

	call dohack		;set debuggee's int 23/24
	mov ds,[d_addr+4]
nextbyte:
	call DMPPFX[bp].DMPJT.pLoad
	push ax
	call hexbyte
	inc di
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
	loop nextbyte

	push es		;restore ds
	pop ds

	call unhack	;set debugger's int 23/24
	mov di,bx
	push dx
	call putsline
	pop dx
	call DMPPFX[bp].DMPJT.pEnd
	jc nextline
	sizeprfX	;mov [d_addr],esi
	mov [d_addr],si
	ret

if ?PM
load32:
	db 67h			;lodsb [esi] 
endif
load16:
	lodsb
	ret
getb16:
	mov cx,si
	or cl,0fh
	cmp cx,dx		;compare with end address
	jb @F			;if we write to the end of the line
	mov cx,dx
@@:
	sub cx,si
	inc cx			;cx = number of bytes to print this line
	ret
end16:
	dec si
	cmp si,dx
	inc si
	ret

if ?PM
	.386
getb32:
	mov ecx, esi
	or cl, 0fh
	cmp ecx, edx
	jb @F
	mov ecx, edx
@@:
	sub ecx, esi
	inc ecx
	ret
end32:
	dec esi
	cmp esi, edx
	inc esi
	ret
	.8086
endif

d_cmd endp

if RING0 and V86M

v86setofs:
	test byte ptr [regs.rFL+2], 2	; v86-mode
	jz nov86
	.386

;--- either use scratch selector or flat selector
;--- both variants have their pros and cons.
;--- still to decide...

 if 0

V86OFSFR struct
	dd ?	;edx
	dw ?	;return addr
wSegm dw ?	;src/dst register
V86OFSFR ends

	push edx
	movzx edx, [esp].V86OFSFR.wSegm
	shl edx, 4
	mov [dwV86Ofs], edx
	mov dx, [wFlat]
	mov [esp].V86OFSFR.wSegm, dx
	pop edx
 else

V86OFSFR struct
	dw ?	;dx
	dw ?	;bx
	dw ?	;return addr
wSegm dw ?	;src/dst register
V86OFSFR ends

	push dx
	push bx
	mov dx, [esp].V86OFSFR.wSegm
	call setscratchsel  
	mov [esp].V86OFSFR.wSegm, bx
	pop bx
	pop dx
 endif
nov86:
	ret
endif

errorj4:
	jmp cmd_error

;--- E command - edit memory.

e_cmd proc
	call prephack
	@movs bx,[regs.rDS]
	call getaddr	;get address into bx:(e)dx
	call skipcomm0
	cmp al,CR
	je ee1			;if prompt mode
	push dx			;save destination offset
	call getstr		;get data bytes SI -> line_out
	mov cx,di
	mov dx,offset line_out
	sub cx,dx		;length of byte string
	pop di
	mov ax,cx
	dec ax
if ?PM
	call IsOfs32	;v1.29: if limit is > 64kB, skip test
	jnz @F
endif
	add ax,di
	jc errorj4		;if it wraps around
@@:
	call dohack		;set debuggee's int 23/24
	mov si,dx
if ?PM
	call IsWriteableBX
endif
	mov es, bx
if ?PM
	call IsOfs32
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
	@RestoreSeg ds
	push ds			;restore es
	pop es
if INT2324
;--- store2324 is called after debuggee memory has been written (just e cmd)
	mov di,offset run2324	;debuggee's int 23/24 values
	call store2324	;copy IVT 23/24 to di ( real-mode only )
	call unhack		;set debugger's int 23/24
endif
	ret

;--- Prompt mode. BX:E/DX=addr, DI=line_out

ee1:
	@dprintf "e: bx:edx=%X:%lX", bx, edx
if REDIRECT
	mov [bufnext], si  ; update buffer ptr in case stdin is file
endif
	mov bp,offset hexword
if ?PM
	call IsOfs32
	jz @F
	mov bp,offset hexdword
@@:
endif

;--- Begin loop over lines.

e_nextl:			;<--- next line
	@dispsegm bx	;print out segment part
	mov al,':'
	stosb
	sizeprfX		;mov eax,edx
	mov ax,dx
	call bp

;--- Begin loop over bytes.

e_nextb:			;<--- next byte
	push bx
	push dx
	mov ax,'  '
	stosw
	call dohack		;set debuggee's int 23/24
	call readmem	;read byte at BX:(E)DX
	call unhack		;set debugger's int 23/24
	call hexbyte	;print old value of byte
	mov al,'.'
	stosb
	call puts
	pop dx
	pop bx
	mov si,offset line_out+16	;address of buffer for characters
	xor cx,cx		;number of characters so far

;--- get a byte (2 chars)
;--- this is a simple "editor" that allows max 2 chars as input:
;--- + 0-9 or A-F
;--- + control chars SPACE, CR, BS, '-'

e_nextc:			;<--- get next char
if REDIRECT
	test [fStdin], AT_DEVICE
	jnz ee9			;jmp if it's a tty
	push si
	mov si,[bufnext]
	cmp si,[bufend]
	jb @F			;if there's a character already
	call fillbuf	;fill buffer with a new line; init SI
	mov al,CR
	jc ee8			;if eof
@@:
	lodsb			;get the character
ee8:
	mov [bufnext],si
	pop si
	jmp ee10
endif
ee9:
ife RING0
	call InDos      ;v1.27: use BIOS if InDOS
	jnz @F
	mov ah,8		;console input without echo
;	int 21h         ;v1.29: don't use INT instruction;
	call doscall	;might make debuggee run if int 21h is intercepted
	jmp ee10
@@:
endif
	mov ah,0h
if RING0
	.386
	call cs:[int16vec]
	.8086
else
	int 16h
endif

ee10:
	cmp al,' '
	je e_spcr		;if done with this byte
	cmp al,CR
	je e_spcr		;ditto
	cmp al,BS
	je e_bs			;if backspace
	cmp al,'-'
	je e_minus		;if '-'
	cmp cx,2		;otherwise, it should be a hex character
	jae e_nextc		;if we have a full byte already
	mov [si],al
	call getnyb
	jc e_nextc		;if it's not a hex character
	inc cx
	lodsb			;get the character back
	call stdoutal
	jmp e_nextc
e_bs:
	jcxz e_nextc	;if nothing to backspace over
	dec cx
	dec si
	call fullbsout
	jmp e_nextc
e_minus:
	call stdoutal
	call storebyte
	sizeprfX		;dec edx
	dec dx			;decrement offset part
	mov di,offset line_out
e_newline:
	mov ax,LF * 256 + CR;terminate this line
	stosw
	jmp e_nextl		;back for another line

e_spcr:
	call storebyte	;store byte if CX != 0
	sizeprfX		;inc edx
	inc dx			;increment offset
	mov di,offset line_out
	cmp al,CR
	je e_done
	test dl,7
	jz e_newline
	not cx
	add cx,4		;compute 3 - cx
	mov al,' '
	rep stosb		;store that many spaces
	jmp e_nextb		;back for more

e_done:
	jmp putsline	;call putsline and return

;--- byte has been entered (1 or 2 chars)
;--- si->behind byte
;--- cx=#chars
;--- bx:e/dx: address to store byte
;--- ax preserved

storebyte:
	jcxz sb_done	;if no change for this byte
	mov [si],al		;terminate the string
	sub si,cx		;point to beginning
	push ax			;v1.29: save/restore value of AL to avoid stop if 'D' is entered
	push cx
	push dx
	lodsb
	call getbyte	;convert byte to binary (DL)
	mov al,dl
	pop dx
	pop cx
	call dohack		;set debuggee's int 23/24
if ?PM
	push bx			;bx may be changed by writemem in pm
endif
	call writemem	;write AL at BX:(E)DX
if ?PM
	pop bx
endif
if INT2324
	mov di,offset run2324	;debuggee's int 23/24
	call store2324	;copy IVT 23/24 to di ( real-mode only )
	call unhack		;set debugger's int 23/24
endif
	pop ax
sb_done:
	ret
e_cmd endp

;--- F command - fill memory
;--- entry: SI=line, CX=0, AL=last char

f_cmd proc
	call getrangeDS	;get address range into bx:(e)dx/(e)cx
if ?PM
	call IsOfs32
	jz @F
	.386
	sub ecx, edx
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
	mov cx, di
	sub cx, offset line_out
if ?PM
	call IsWriteableBX	; ensure BX is writeable
endif
	mov es, bx
if ?PM
	call IsOfs32
	jz fill_16
	.386
	movzx ecx, cx
	pop edi
	cmp ecx, 1
	je onebyte32
	pop eax			; eax=size ( of mem block )
;	@dprintf "f_cmd: eax=%lX, ecx=%lX, es:edi=%X:%lX", eax, ecx, es, edi
	cdq
	div ecx			; ecx=size of hex-string entered
	mov esi, offset line_out
	or eax, eax
	jz partial32
nextcopy32:
	push ecx
	push esi
	rep movsb es:[edi], ds:[esi]
	pop esi
	pop ecx
	dec eax
	jnz nextcopy32
partial32:
	mov ecx, edx
;	jecxz exit		;rep with ecx=0 is a nop
	rep movsb es:[edi], ds:[esi]
	jmp exit
onebyte32:
	pop ecx
	mov al,byte ptr [line_out]
	rep stosb es:[edi]
	jmp exit
fill_16:
	.8086
endif
	pop di
	cmp cx,1
	je onebyte16;a common optimization
	pop ax		;get size
	xor dx,dx	;now size in DX:AX
	cmp ax,1
	adc dx,0	;convert 0000:0000 to 0001:0000
	div cx		;compute number of whole repetitions
	mov si,offset line_out
	or ax,ax
	jz partial16;if less than one whole rep
nextcopy16:
	push cx
	push si
	rep movsb
	pop si
	pop cx
	dec ax
	jnz nextcopy16	;if more to go
partial16:
	mov cx,dx
;	jcxz exit	;rep with cx=0 is a nop
	rep movsb
	jmp exit
onebyte16:
	pop cx
	mov al,byte ptr [line_out]
	stosb		;cx=0 -> 64 kB
	dec cx
	rep stosb
exit:
	push ds
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
	jcxz setbps_ex
nextbp:
	sizeprfX		;lodsd
	lodsw
	sizeprfX		;xchg edx,eax
	xchg dx,ax		;mov dx,ax
	lodsw
	xchg bx,ax		;mov bx,ax
	call di			;call setbp1/resetbp1
	inc si
	loop nextbp		;next bp
setbps_ex:
	ret
setbp1::
	mov al,0CCh
	call writemem	; write byte at bx:e/dx, C if write was unsuccessful (ROM)
	mov [si],ah		; save the current contents
	jnc @F
	call bp			; either ignore error (g cmd) or abort with msg (p cmd)
@@:
	retn
resetbp1::
	mov al,[si]
	cmp al,0CCh
	jz @F
	call writemem	; write byte at bx:e/dx
@@:
	retn

setbps endp

if ?DPMI

;--- with DEBUGX: when a mode switch did occur in the debuggee,
;--- the segment parts of the breakpoint addresses are no
;--- longer valid in the new mode. To enable the debugger to reset the
;--- breakpoints, it has to switch temporarily to the previous mode.
;--- in: DX=old value of regs.msw

resetbpsEx proc

	cmp dx,[regs.msw]
	jz resetbps			; mode didn't change, use normal reset routine
if INT22
	cmp [run_int], INT22MSG	;skip reseting bps if debuggee terminated
	jz @F
endif
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
	call ispm_dbg
	jnz is_pm
	mov ax,[dssel]	;switch rm -> pm
	mov si,[cssel]
	mov dx,ax  
	mov cx,ax
	jmp [dpmi_rm2pm]
is_pm:
	mov ax,[wDgroup]	;switch pm -> rm
	mov si,ax
	mov dx,ax
	mov cx,ax
patchrmswitch db 66h		;jmp fword ptr [dpmi_pm2rm]
	jmp dword ptr [dpmi_pm2rm]
back_after_switch:
	xor [regs.msw],-1
	retn

;--- save/restore task state in ES:(E)DI

sr_state::
	sizeprf		;xor edi,edi
	xor di,di	;clears hiword EDI if cpu >= 386
	mov di,sp
	add di,2	;the save space starts at [sp+2]
	call ispm_dbg
	jnz @F
	call [dpmi_rmsav]
	retn
@@:
patchsrstate db 66h		;call fword ptr [dpmi_pmsav]
	call dword ptr [dpmi_pmsav]
	retn

resetbpsEx endp

endif

if FMTEXE
;--- problem is that [pspdbg] is always a segment value
 if ?DPMI
mypsp:
	call ispm_dbg
	jnz @F
	mov ds, [pspdbg]
	ret
@@:
	mov ds, [pspdbgpm]
	ret
@ds_mypsp textequ <call mypsp>
 else
@ds_mypsp textequ <mov ds, [pspdbg]>
 endif
endif

;--- G command - go.

g_cmd proc

	call parseql	;get optional <=addr> argument; always writes [eqladdr+4]

;--- Parse the rest of the line for breakpoints

	mov di,offset line_out 
	xor ax,ax		; init bp cnt to 0
	stosw
if USEHWBP
	mov bp, [wStoreBP]
endif
nextbp:
	dec si
	call skipcomma
	cmp al,CR		;end of line?
	je gg_parsebp_done

;--- calling getaddr was a bug in protected-mode up to v1.29.
;--- ( it was a different getaddr than now, one that ensured the
;--- segment part is a writeable selector in pm; with 2.0, getaddr
;--- does this no longer ).
;--- Anyway,  multiple BPs with different segment parts all used
;--- the very same "scratch" selector, resulting in "random" mem writes.

	@movs bx,[eqladdr+4]	;default segment ( either CS or segm of '=' )
	call getaddr	;get address into bx:(e)dx
if RING0 and V86M
	test byte ptr [regs.rFL+2],2
	jz @F
	cmp bx, [scratchsel]
	jnz @F
;--- if v86-mode, don't store the scratch selector in the list of BPs
;--- instead, use linear addresses (and the flat selector)
	.386
	movzx ebx, [scratchv86]
	shl ebx, 4
	add edx, ebx
	mov bx, [wFlat]
@@:
endif
	@dprintf "g_cmd: bp=%X:%lX", bx, edx
if USEHWBP
	call bp
else
	call storebpdef
endif
	jmp nextbp		;next bp

if USEHWBP
storebpdef2:
	mov bp, offset storebpdef
endif
storebpdef::
	@dprintf "std int3 bp, cs:eip=%X:%lX di=%X lo=%X", bx, edx, di, offset line_out
	sizeprfX		;xchg eax,edx
	xchg ax,dx		;mov ax,dx
	sizeprfX		;stosd
	stosw
	xchg ax,bx		;mov ax,bx
	stosw
	inc di			; reserve to store byte at bp location
	inc byte ptr line_out	;use [line_out+0] to count bps
	retn
if USEHWBP
storebpx::
	call sethwbptmp
	jc storebpdef2
	retn
endif

gg_parsebp_done:

;--- Store breakpoint bytes in the given locations.

;--- v2.50: abort g as in t/p if bp can't be written
;	mov bp, offset _ret	; ignore write errors for g
	mov bp, offset bp_writeerr
gg_1::				; <--- called by p/t ( run an int/call/... - set 1 bp )
	mov di,offset setbp1
	call setbps		; may cause a GPF in protected-mode if location is read-only
	@dprintf "g_cmd: calling run"

if ?DPMI
	push [regs.msw]	;save old MSW
endif
	call run		;run the program
if ?DPMI
	pop dx			;get old MSW
endif

ife RING0
 if FMTEXE
	push ds
	@ds_mypsp
 endif
	@dprintf "g_cmd: run returned, [spadjust]=%X, [spsav]=%X:%X", cs:[spadjust], word ptr ds:[PSPS.SPSAV+2], word ptr ds:[PSPS.SPSAV]
 if FMTEXE
	pop ds
 endif
endif

if ?PM
	call getcsattr
	mov [bCSAttr],al	; must be set for getcseipbyte()
endif

if 0
;--- this is inactive since v2.0;
;--- not needed for soft/hard bp detection?
;--- see comment below - no safe detection for soft BPs anymore!

	mov cx,-1
	call getcseipbyte	;get byte at [cs:eip-1], set E/BX to E/IP-1
	push ax
endif

;--- Restore breakpoint bytes.

if ?DPMI
;--- if debuggee has terminated ( [run_int] == INT22MSG ),
;--- nothing will be done if mode has changed ( see resetbpsEx() ).
	call resetbpsEx		;reset BPs ( expects DX=old msw ), may switch tmp. to previous mode
else
	call resetbps
endif
	@dprintf "g_cmd: resetbps done"

;--- Finish up.  Check if it was one of _our_ breakpoints.
;--- if yes, decrement (E)IP 

if 0 ; v2.0: not needed for soft/hard bp detection?
	pop ax
	cmp al,0CCh		; was a CC at CS:[EIP-1]?
	jnz gg_exit
endif

if USEHWBP
	cmp bBPhit, 0
	jnz gg_ok
endif

	cmp [run_int], EXC03MSG
	jnz gg_exit
	mov cx,  -1
	call getcseipbyte	; get byte [cs:eip-1], sets E/BX
	cmp al, 0CCh		; still a INT3 at [cs:eip-1] ?
	jz gg_exit

;--- here E/IP is decremented because DEBUG assumes an INT3 has been restored.
;--- it's not always true, though - the INT3 may have been routed from protected-mode;
;--- or anything else has just jumped to the vector for INT3.
if ?PM
	test [bCSAttr], CS32
	jz $+3
	db 66h	;mov [regs.rIP],ebx
endif
	mov [regs.rIP], bx	; decrement (E)IP
if RING0
	mov [run_int], -1	; v2.0: reset entry ( so SK cmd won't accept soft bps )
endif
gg_ok:
	call dumpregs	; then just display register dump
_ret:
	ret				; and done ( no "unexpected breakpoint" msg )
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

if ?DPMI

LoadSDA:
	call ispm_dbg
	mov si,word ptr [pSDA+0]
	mov ds,[SDASel]
	jnz @F
	mov ds,word ptr cs:[pSDA+2]
@@:
	ret

ispm_dbe:	; debuggee in protected-mode?
ispm_dbg:	; debugger in protected-mode
	cmp cs:[regs.msw],0 	;returns: Z=real-mode, NZ=prot-mode
	ret

elseif RING0 and V86M
ispm_dbe:	; return Z if debuggee in v86-mode
	push ax
	mov ax, [regs.rFL+2]
	and al, 2	; VM bit  
	xor al, 2
	pop ax
	ret
endif

if LCMDFILE

setpspdbg:		; set debugger's PSP
 if FMTEXE
	mov bx,[pspdbg]
  if ?DPMI
	call ispm_dbg
	mov ah, 50h
	jz setpsp_rm
	jmp simrealmodeint21
  endif
 else
	mov bx,cs
 endif
setpsp proc		; <--- entry to set debuggee's PSP
	mov ah,50h
 if ?DPMI
	call ispm_dbg
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
	call simrealmodeint21
	pop bx
	pop dx
	pop cx
	ret
	.8086
  else
	jmp doscall_rm
  endif
setpsp_rm::
 endif

 if USESDA
  if ?DPMI
	cmp word ptr [pSDA+2],0
	jz doscall_rm
  endif
	push ds
	push si
  if ?DPMI
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

endif

ife (BOOTDBG or RING0)

getpsp proc
	mov ah,51h
if ?DPMI
	call ispm_dbg
	jz getpsp_rm
 if NOEXTENDER
	call simrealmodeint21
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
 if ?DPMI
	cmp word ptr [pSDA+2],0
	jz doscall_rm
 endif
	push ds
	push si
 if ?DPMI
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

endif

ife RING0
doscall:
 if NOEXTENDER
	call ispm_dbg
	jz doscall_rm
	.286
simrealmodeint21:
	invoke simrealmodeint, 21h, cs:[wDgroup]
	ret
	.8086
 endif
doscall_rm:
	int 21h
	ret
endif

if ?DPMI

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

;--- call DPMI simulate real-mode interrupt (0x300) function

simrealmodeint proc stdcall uses es intno:word, dataseg:word

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
simrealmodeint endp
	.8086
endif

if ?DPMI

;--- this proc is called in pmode only
;--- DS is unknown!
;--- called by L/W cmds.

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

if LCMDFILE

isdebuggeeloaded:
	mov ax,[pspdbe]
	cmp ax,[pspdbg]
	ret

;--- ensure a debuggee PSP exists;
;--- set SI:DI to CS:IP, preserve AX, BX, DX

ensuredebuggeeloaded proc
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
	ret
ensuredebuggeeloaded endp

endif
if BOOTDBG or DPCMD

;--- abs disk read, arguments in [packet]
;--- al = disk
;--- out: C=error
;--- modifies all std regs except sp, bp

	.errnz RING0, <int 13h not yet supported>

readsect proc
	@dprintf "readsect: disk=%X", ax
	mov dl, al
	and al, al
	jns nolba
	mov bx, 055AAh
	mov ah, 41h
	int 13h
	jc nolba
	cmp bx, 0AA55h
	jnz nolba
	test cl, 1
	jz nolba
	xor cx, cx
	mov bx, offset packet
	@dprintf "readsect: lba access, dx=%X, secno=%lX", dx, [bx].PACKET.secno
	push cx
	push cx
	push word ptr [bx].PACKET.secno+2
	push word ptr [bx].PACKET.secno+0
	push [bx].PACKET.dstseg
	push [bx].PACKET.dstofs
	push [bx].PACKET.numsecs
	mov cl, 16
	push cx
	mov si, sp
	mov ah, 42h
	int 13h
	lea sp, [si+8*2]
	jc disk_err
done:
	ret
nolba:
	push dx
	mov ah, 8
	int 13h
	pop ax
	jc disk_inval
	mov bx, offset packet
	push ax
	call lba2chs
	pop ax
	mov dl, al
	@dprintf "l: chs access, dx=X, cx=%X", dx, cx
	mov ah, 2
	mov al, byte ptr [bx].PACKET.numsecs
	push es
	les bx, dword ptr [bx].PACKET.dstofs
	int 13h
	pop es
	jc disk_err
	ret
disk_err:
	mov dx, offset dskerrb
	jmp @F
disk_inval:
	mov dx, offset dskerr1
@@:
	stc
	ret
lba2chs:
	mov si, cx
	and si, 3Fh
	mov al, dh
	inc al
	mov ah, 0
	mov di, ax
	mov cx, word ptr [bx].PACKET.secno+0
	mov ax, word ptr [bx].PACKET.secno+2
	xor dx, dx
	div si
	xchg ax, cx
	div si
	inc dx
	xchg cx, dx
	div di
	mov dh, dl
	mov ch, al
	ror ah, 1
	ror ah, 1
	or cl, ah
	retn
readsect endp

endif

if BOOTDBG

;--- L command - absolute disk read.

l_cmd proc
	call parselw	;returns AL=drive, BX=packet
	jz cmd_error	;Z means max 1 arg; must be a full command
	call readsect
	jnc @F
	call int21ah9
@@:
	ret
l_cmd endp

elseife RING0

;--- L command - read a program, or disk sectors, from disk.

l_cmd proc
	call parselw	;parse it, addr in bx:(e)dx
 if LCMDFILE
	jz ll1			;Z if max 1 argument (read program)
 else
	jz cmd_error
 endif
 if NOEXTENDER
	call ispm_dbg
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
	add cl,[dpmi32]	;5/6=far16/far32 ptr
	DispatchCall
	jmp ll0_2
 endif
ll0_1:
	int 25h
ll0_2:
	mov cx,"er"		;CX:DX="read"
	mov dx,"da"
	jmp disp_diskresult

 if LCMDFILE

;--- For .com or .exe files, we can only load at cs:100.  Check that first.

ll1:
	test [fileext], EXT_COM or EXT_EXE
	jz loadfile		;if not .com or .exe file
	cmp bx,[regs.rCS]
	jne l_err		;if segment is wrong
	cmp dx,100h
	je loadfile		;if address is OK (or not given)
l_err:
	jmp cmd_error	;can only load .com or .exe at cs:100

 endif

l_cmd endp

endif

if LCMDFILE

;--- load (any) file (if not .EXE or .COM, load at BX:DX)
;--- open file and get length.
;--- in protected-mode, this will work with a DOS extender only.

loadfile proc
	mov si,bx		;save destination address, segment
	mov di,dx		;and offset
	mov ax,3d00h	;open file for reading
 if FMTEXE
	push ds
	mov ds, [pspdbg]
 endif
	mov dx,PSPS.DTA	;n cmd has stored file spec at DTA!
	call doscall
 if FMTEXE
	pop ds
 endif
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

 if ?DPMI
;--- dont load a file in protected mode,
;--- the read loop makes some segment register arithmetic
	call ispm_dbg
	jz @F
	mov dx,offset nopmsupp
	call int21ah9
	jmp cl_exit	; close file and exit
@@:
 endif

;--- Load it ourselves.
;--- For non-.com/.exe files, we just do a read, and set BX:CX to the
;--- number of bytes read.

	call ensuredebuggeeloaded	;make sure a debuggee PSP exists
	mov es, [pspdbe]

;--- Check the size against available space.

	push si
	push bx

	cmp si,es:[PSPS.ALASAP]
	pushf
	neg si
	popf
	jae ll6				;if loading past end of mem, allow through ffff
	add si,es:[PSPS.ALASAP]	;si = number of paragraphs available
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
	jmp cl_exit

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

cl_exit:
	mov ah,3eh		;close file
	int 21h
	push ss			;restore ds
	pop ds
	ret				;done

loadfile endp

endif

if LCMDFILE

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
;--- bx=file handle, dx:ax=file size

	push ax
	mov ah,3eh		;close file
	int 21h
	pop bx			;dx:bx is the file length

 if 1

;--- adjust .exe size by 200h (size of header? who knows )

	test [fileext],EXT_EXE
	jz @F		;if not .exe
	sub bx,200h
	sbb dx,0
@@:
 endif

	@dprintf "loadpgm, dx:bx=%X:%X", dx, bx
	push bx
	push dx

;--- cancel current process (unless there is none)
;--- this will also put cpu back to real-mode!!!

	call isdebuggeeloaded
	jz @F
	call freemem
@@:

	@dprintf "loadpgm, init regs, ds=%X, es=%X", ds, es

;--- Clear registers

	mov di, offset regs
	mov cx, sizeof regs / 2
	xor ax, ax
	rep stosw

	pop word ptr [regs.rBX]
	pop word ptr [regs.rCX]

if FMTEXE
	push ds
	mov ds, [pspdbg]
endif

;--- Fix up interrupt vectors in PSP

if INT2324
	mov si,PSPS.CCIV		;address of original INT 23 and 24 (in PSP)
	mov di,offset run2324
	movsw
	movsw
	movsw
	movsw
endif

;--- Actual program loading.  Use the DOS interrupt.

	mov dx,PSPS.DTA			;file to load in DS:SI
	mov bx,offset execblk	;parameter block in ES:BX
	mov ax,4b01h			;load program, don't execute
	int 21h
if FMTEXE
	pop ds
endif
	jnc @F
	jmp io_error	;if error
@@:
	call setespefl

;--- we calculate the stack space used by previous dos call (ax=4b01)
;--- and use the result (in spadjust) to adjust the field PSP:[2Eh]
;--- in the debugger's PSP whenever the debuggee is to be executed ("run").
	mov ax,sp
if FMTEXE
	mov es, [pspdbg]
	sub ax,word ptr es:[PSPS.SPSAV]
else
	sub ax,word ptr ds:[PSPS.SPSAV]
endif
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
	mov dx,offset intr22
	int 21h
	mov es,[pspdbe]
	mov word ptr es:[PSPS.TPIV+0],dx
	mov word ptr es:[PSPS.TPIV+2],cs

	push ss
	pop es

;--- Set up initial addresses for a/d/u commands.
;--- out: ax=regs.rCS

setup_adu::
	mov di,offset a_addr
	mov si,offset regs.rIP
	mov ax,[regs.rCS]
	push di
	movsw		; write a_addr eip
	movsw
	stosw		; write a_addr cs
	pop si
	mov cx, 2*3
	rep movsw	; copy a_addr to d_addr and u_addr
	ret

loadpgm endp

endif

;--- 'm'achine command:  set machine type.

mach proc
;	dec si
;	call skipwhite
;	cmp al,CR
;	je mach_query		;if just an 'm' (query machine type)
	mov al,[si-1]     
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
mach endp

errorj3:
	jmp cmd_error

;--- 'mc' command:  set coprocessor.
;--- optional arguments:
;--- N: no coprocessor
;--- 2: 80287 with 80386

mc_cmd proc
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
mc_cmd endp

;--- M command - move/copy memory.
;--- 1. check if there's no argument at all: mach_query, display cpu
;--- 2. check for MC cmd: mc_cmd, set/reset coprocessor 
;--- 3. check if there's just 1 argument:  mach, set cpu

m_cmd proc
	cmp al,CR
	jz mach_query
	mov ah,[si-2]
	or ax,TOLOWER or (TOLOWER shl 8)
	cmp ax,'mc'			; mc cmd?
	jz mc_cmd
if ?PM
	cmp al,'0'			; is there a '$' or '%' modifier?
	jb ismove			; ( would throw an error in getdword )
endif
	push si
	call getdword
	cmp al,CR
	jz @F
	call skipwhite
@@:
	pop si
	cmp al,CR
	je mach				; jump if 1 argument only
ismove:
	dec si
	lodsb
	call parsecm		;parse arguments: src=DS:(E)SI, dst=ES:(E)DI, length-1=(E)CX
;--- note: DS unknown here

	push cx
if ?PM
 if ?DPMI
	call ispm_dbg
	jz @F
 endif
;--- TODO: do overlapping check in protected-mode

	@dprintf "m_cmd: ds:esi=%X:%lX, es:edi=%X:%lX, ecx=%lX", ds, esi, es, edi, ecx
	clc
	jmp m3
@@:
endif
	mov cl,4
	shr dx,cl		; BX:DX=dst seg:ofs
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
if INT2324
	push ds
	push ss		;ds = dgroup
	pop ds
	call dohack	;set debuggee's int 23/24
	pop ds
endif
if ?PM
;--- v2.0: ensure ES is writeable ( parsecm does that no longer )
	mov bx, es
	push ds
	@RestoreSeg ds
 if ?DPMI
	push ds
	pop es
 endif
	call IsWriteableBX	; expects DS(,ES)=dgroup
	call IsOfs32
	pop ds
	mov es, bx
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
	jmp ee0a		;restore ds and es and undo the int2324 pointer hack
m_cmd endp

;--- M without argument - display machine type.

mach_query proc
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
mach_query endp

if LCMDFILE or WCMDFILE

;--- N command - change the name of the program being debugged.
;--- modifies the debugger's PSP; actually, both the program name
;--- and the tail are stored in the DTA.

;--- Actually, the current N cmd is NOT compatible with MS Debug. MS Debug's
;--- N cmd modifies the debuggee's PSP. So it's an easy way to modify
;--- the program's arguments. OTOH, it removes the file_spec only on entry.

;--- possible fix: copy debug's PSP:5C-7B and DTA:xx-7F (xx=strlen(file_spec) + 1)
;--- to the debuggee PSP as soon as it has been created.

CONST segment
exts label byte
	db ".HEX",EXT_HEX
	db ".EXE",EXT_EXE
	db ".COM",EXT_COM
extsend label near
CONST ends

n_cmd proc
	mov di,PSPS.DTA		;destination address
if FMTEXE
	mov es, [pspdbg]
endif

;--- Copy and canonicalize file name.
;--- v2.50: check max. length to ensure that debug's _TEXT segment isn't modified.
;--- out: [fileext]=0 if no file spec at all
;---      [execblk.cmdtail] -> behind file spec

	mov cx, sizeof PSPS.DTA - 1
nextc:
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
	loop nextc	;back for more

nn3:
	mov al,0		;null terminate the file name string
	stosb
	mov word ptr [execblk.cmdtail],di	;save start of command tail

;--- file name stored as asciiz at psp:80h;
;--- now set [fileext];
;--- AL=0

	push cx
	push di
	push si
	cmp di,PSPS.DTA+1
	je nn3d			;if no file name at all
	cmp di,PSPS.DTA+5
	jb nn3c			;if no extension (name too short)
	lea dx,[di-5]
	mov bx,offset exts	;check for .EXE, .COM and .HEX
@@:
	mov si,bx
	mov di,dx
	add bx,5
	mov cx,4
	repz cmpsb
	mov al,[si]
	jz nn3d
	cmp bx, extsend
	jb @B
nn3c:
	mov al,EXT_OTHER
nn3d:
	mov [fileext],al
	pop si

;--- Finish the N command
;--- 1. copy what's left behind the file spec to line_out

if FMTEXE
	push es
	push ds
	pop es
endif

	mov di,offset line_out
	push di
	dec si
@@:
	lodsb			;copy the remainder to line_out
	stosb
	cmp al,CR
	jne @B
	pop si

if FMTEXE
	pop es
endif

;--- Set up FCBs. src is line_out

	mov di,PSPS.FCB1
	call DoFCB		;first FCB: parse name DS:SI into FCB es:di
	mov byte ptr [regs.rAX+0],al
	mov di,PSPS.FCB2
	call DoFCB		;second FCB
	mov byte ptr[regs.rAX+1],al

;--- Copy command tail from line_out to
;--- PSP, just behind zero-terminated file spec.

	mov si,offset line_out
	pop di
	pop cx
	jcxz notail	; if no more space left behind file spec
	push di
	inc di		; skip byte used for byte cnt
@@:
	lodsb
	stosb
	cmp al,CR
	loopne @B	;if not end of string
	pop ax		;recover old DI
	dec di
	dec di
	xchg ax,di
	sub ax,di	;compute length of tail
	stosb
notail:
	ret
n_cmd endp

;--- Subroutine to process an FCB.
;--- di->FCB
;--- si->file name

DoFCB proc
@@:
	lodsb
	cmp al,CR
	je nn7		;if end
	call ifsep
	je @B		;if separator
	cmp al,[swchar]
	je nn10		;if switch character
nn7:
	dec si
	mov ax,2901h;parse filename into FCB
	call doscall
	push ax		;save AL
@@:
	lodsb		;skip till separator
	cmp al,CR
	je @F		;if end
	call ifsep
	je @F		;if separator character
	cmp al,[swch1]
	jne @B		;if not swchar (sort of)
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

endif

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

if ?PM

;--- ensure segment in BX is writeable.
;--- if it isn't, BX may be set to an alias (scratchsel)
;--- expects DS,SS=dgroup ( for ?DPMI, also ES=dgroup )
;--- out: Carry=1 if segment not writeable
;--- called by:
;---   setcseipbyte(); write at regs.cs:e/ip + cx
;---   writemem(): write byte at bx:e/dx 
;---   e, f, m cmds
;---   parselw()

IsWriteableBX proc
 if ?DPMI
	call ispm_dbg
	jz is_rm
	.286
	push ax
	sizeprf				; push edi
	push di
	sub sp, 8
	mov di, sp
	sizeprf				; lea edi,[di] (synonym for movzx edi,di), 3 bytes long
	lea di,[di]
	mov ax,000Bh		;get descriptor
	int 31h
	jc @F
	test byte ptr [di+5],8	;code segment?
	jz @F
	and byte ptr [di+5],0F3h;reset CODE+conforming attr
	or byte ptr [di+5],2	;set writable
	mov bx, [scratchsel]
	mov ax, 000Ch
	int 31h
@@:
	lea sp, [di+8]
	sizeprf				; pop edi
	pop di
	pop ax
	.8086
is_rm:
 elseif RING0
	.386
	verw bx
	jz isok
	pushad
	call getlinearbaseDT
	jc error
	cmp bx, dx
	ja error
	mov esi, eax
  if FLATSS
	sub esp, 6
	sgdt [esp]
  else
	mov bp, sp
	sub sp, 6
	sgdt [bp-6]
  endif
	pop di
	pop edi
	and bl, 0F8h
	movzx ebx, bx
	lea esi, [esi+ebx]
	movzx eax, [scratchsel]
	add edi, eax
	@dprintf "IsWriteableBX: esi=%lX, edi=%lX", esi, edi
	push ds
	mov ds, [wFlat]
	lodsd ds:[esi]
	mov ds:[edi+0], eax
	lodsd ds:[esi]
	and ah, 0F7h	; data
	or ah, 2		; writable
	mov ds:[edi+4], eax
	pop ds
	popad
	mov bx, [scratchsel]
isok:
 else
    clc
 endif
	ret

 if RING0
error:
	popad
	stc
	ret
 endif

IsWriteableBX endp

 if RING0

;--- in: DX=real-mode segment
;--- out: BX=scratch sel, base modified to match the segment in DX

setscratchsel proc
  if V86M
	mov [scratchv86], dx
  endif
	pushad
  if FLATSS
	mov ebp, esp
	sub esp, 6
	sgdt [esp]
  else
	mov bp, sp
	sub sp, 6
	sgdt [bp-6]
  endif
	pop ax
	pop eax
	movzx ebx, [scratchsel]
	add ebx, eax
  if FLATSS
	movzx eax, word ptr [ebp+5*4]	;get DX
  else
	movzx eax, word ptr [bp+5*4]	;get DX
  endif
	shl eax, 4
	push ds
	mov ds, [wFlat]
	mov word ptr [ebx+0], -1
	mov word ptr [ebx+2], ax
	shr eax, 16
	mov byte ptr [ebx+4], al
	mov word ptr [ebx+5], 0093h	; data, writeable, present, 16-bit
	mov byte ptr [ebx+7], ah
	pop ds
	popad
	mov bx, [scratchsel]
	ret
setscratchsel endp
 endif

 if ?DPMI
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
 endif

;--- out: AL= HiByte of attributes of current CS
;--- out: ZF=1 if descriptor's default-size is 16bit
;--- called by P, T, U
;--- modifies EAX, BX

getcsattr proc
	@movs bx,[regs.rCS]
getseldefsize::	;<--- any selector in BX
 if ?DPMI
	mov al,00
	cmp [machine],3
	jb @F
	call ispm_dbe
	jz @F
 endif
	.386
	lar eax,ebx
	shr eax,16
	.8086
@@:
	test al,40h
	ret
getcsattr endp

;--- in: segment/selector in BX
;--- out: ZF=1 if in real-mode or segment limit is <= 64 kB

getseglimit proc
	push ax
 if ?DPMI
	xor ax,ax
	cmp [machine],3
	jb is16
	call ispm_dbg
	jz is16
 endif
	.386
	lar eax,ebx		; v2.0: first check if expand down
	and ah,0Ch
	cmp ah,4
	jnz @F
	bt eax, 22		; if yes, is default bit set?
	jc is32ed
@@:
	lsl eax,ebx
	shr eax,16
	.8086
is32ed:
is16:
	and ax,ax
	pop ax
	ret
getseglimit endp

endif ; ?PM

;--- read [EIP+x] value 
;--- in:  CX=x 
;---      [regs.rCS]=CS
;---      [regh_(e)ip]=EIP
;--- out: AL=[CS:(E)IP]
;---      [E]BX=[E]IP+x 
;--- called by T and G

getcseipbyte proc
	push es
	@movs es, [regs.rCS]
	sizeprfX		;mov ebx,[regs.rIP]
	mov bx,[regs.rIP]
if ?PM
	test [bCSAttr], CS32
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
	@movs bx,[regs.rCS]
if ?PM
	call IsWriteableBX	; checks descriptor only, can't detect r/o pages
	jc scib_1
endif
	mov es, bx
	sizeprfX
	mov bx, [regs.rIP]
if ?PM
	test [bCSAttr], CS32
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
;--- used by A, E, G (breakpoints)

writemem proc
if ?PM
 if ?DPMI
	call ispm_dbg
	jz weip16
 endif
	call IsWriteableBX		;ensure that bx has a writeable selector
;	jc err					;v2.0: don't exit silently, better to cause a GPF
	call getseglimit
	jz weip16
	@dprintf "writemem: bx:edx=%X:%lX", bx, edx
	.386
	push ds
	mov ds, bx
	mov ah, [edx]
	mov [edx], al
	cmp al, [edx]
	jmp done
	.8086
weip16:
endif
	@dprintf "writemem: bx:dx=%X:%X", bx, dx
	push ds
	mov ds,bx
	push bx
	mov bx,dx
	mov ah,[bx]
	mov [bx],al
	cmp al,[bx]
	pop bx
done:
	pop ds
	jnz err
	ret
err:
	stc
	ret
writemem endp

;--- read byte from memory
;--- in:  BX:(E)DX=address
;--- out: AL=byte
;--- used by e_cmd prompt mode
;--- BX may be modified

readmem proc
if ?PM
	call getseglimit	;attribute of selector in BX, Z if limit is <= 0ffffh
endif
	push ds
	mov ds,bx
if ?PM
	jz @F
	.386
	mov al,[edx]
	.8086
	pop ds
	ret
@@:
endif
	mov bx, dx
	mov al,[bx]
	pop ds
	ret
readmem endp

;--- P command - proceed (i.e., skip over call/int/loop/string instruction).

p_cmd proc
	call parse_pt	;process arguments

;--- Do it <CX=count> times.  First check the type of instruction.

instrloop:			; <--- next instruction
	push cx			; save cx
	mov dx,15		; DL = number of bytes to go; DH = prefix flags.
if ?PM
	call getcsattr
	mov [bCSAttr],al
	jz @F
	mov dh,PP_ADRSIZ + PP_OPSIZ
@@:
endif
	sizeprfX		; mov esi,[regs.rIP]
	mov si,[regs.rIP]
nextprf:			; <- get next prefix byte
	call getnextb	; AL=[cs:(e)ip], eip++
	mov di,offset ppbytes
	mov cx,PPLEN
	repne scasb
	jne pp5			; if not one of these

	mov al,[di+PPLEN-1]	; get corresponding byte in ppinfo
	test al,PP_PREFIX
	jz @F			; if not a prefix
	xor dh,al		; update the flags
	dec dl
	jnz nextprf		; if not out of bytes
	jmp dotrace		; more than 15 prefixes will cause a GPF
@@:
	test al,40h
	jz @F			; if no size dependency
	and al,3fh
	and dh,PP_OPSIZ	; for CALL, operand size 2->4, 4->6
	add al,dh
@@:
	cbw
	call addeip	; add ax to instruction pointer in (E)SI
	jmp proceed0; we have a skippable instruction here

pp5:
	cmp al,0ffh	; indirect call?
if 0
	jz @F
	jmp dotrace	; just an ordinary instruction
@@:
else
	jnz dotrace
endif
	call getnextb	; get MOD REG R/M byte
	and al,not 8	; clear lowest bit of REG field (/3 --> /2)
	xor al,10h	; /2 --> /0
	test al,38h
if 0
	jz @F
	jmp dotrace	; if not ff/2 or ff/3
@@:
else
	jnz dotrace	; if not ff/2 or ff/3
endif
	cmp al,0c0h
	jae proceed0; if just a register
	test dh,PP_ADRSIZ
	jnz pp6		; if 32 bit addressing
	cmp al,6
	je proceed2	; if just plain disp16
	cmp al,40h
	jb proceed0	; if indirect register
	cmp al,80h
	jb proceed1	; if disp8[reg(s)]
	jmp proceed2; it's disp16[reg(s)]
back2top:
	jmp instrloop; back for more

pp6:
	cmp al,5
	je proceed4	; if just plain disp32
	xor al,4
	test al,7
	jnz @F		; if no SIB byte
	call inceip
@@:
	cmp al,40h
	jb proceed0	; if indirect register
	cmp al,80h
	jb proceed1	; if disp8[reg(s)]
				; otherwise, it's disp32[reg(s)]
proceed4:
	call inceip
	call inceip
proceed2:
	call inceip
proceed1:
	call inceip
proceed0:
	call doproceed2
	jmp pp13

;--- Ordinary instruction.  Just do a trace.

dotrace:
	or byte ptr [regs.rFL+1],1	;set single-step mode
	call run
	cmp [run_int], EXC01MSG
	jne pp15		; stop if some other interrupt
	call dumpregs
pp13:				;<--- Common part to finish up.
	pop cx
	loop back2top	;back for more
	ret
pp15:
	jmp ue_int		;print message about unexpected interrupt and quit

inceip::
if ?PM
	test [bCSAttr], CS32
	jz $+3
	db 66h		;inc esi
endif
	inc si
	retn

addeip:
if ?PM
	test [bCSAttr], CS32
	jz @F
	.386
	movzx eax,ax
	.8086
	db 66h		;add esi,eax
@@:
endif
	add si,ax
	retn

;--- getnextb - Get next byte in instruction stream.
;--- [e]si = eip

getnextb:
	push ds
	@movs ds,[regs.rCS]
if ?PM
	test cs:[bCSAttr], CS32
	jz $+3
	db 67h		;lodsb [esi]
endif
	lodsb
	pop ds
	retn

doproceed2:
	@movs bx, [regs.rCS]

;--- Special instruction.  Set a breakpoint and run until we hit it.
;--- BX:(E)SI == address where a breakpoint is to be set.

doproceed1::	;<--- used by T if an INT is to be processed
	@dprintf "doproceed1: bx:esi=%X:%lX", bx, esi
	mov di,offset line_out	;use the same breakpoint structure as in G
if USEHWBP
	xor ax, ax
	stosw
	sizeprfX	; mov edx, esi
	mov dx, si
	call [wStoreBP]	; optionally use 386 debug register for auto breakpoints?
else
	mov ax, 1	;bp cnt
	stosw
	sizeprfX	;xchg eax,esi
	xchg ax,si
	sizeprfX	;stosd
	stosw
	xchg ax, bx
	stosw
endif
	mov bp, offset bp_writeerr	; abort if bp couldn't be written
	call gg_1	; use g_cmd to write bp, run program, reset bp
	retn
bp_writeerr::
	mov dx, offset cantwritebp
	call int21ah9
	jmp cmdloop

p_cmd endp

if ?DPMI
exitdpmi proc

	push ax
if LPMINTS
	mov bp, [wOfsSize]
	mov si, offset pmvectors
	mov di, offset pmints
	mov cx, LPMINTS
nextpmint:
	push cx
	mov bl, [di]
	sizeprf	; mov edx, [si]
	mov dx, [si]
	mov cx, ds:[si+bp]
	mov ax, 205h
	int 31h
	add di, 3
	add si, sizeof fword
	pop cx
	loop nextpmint
endif
	pop ax
	ret
exitdpmi endp
endif

if QCMD

;--- Q command - quit.

q_cmd proc

 if RING0

;--- the ring0 debugger core doesn't really know how to "quit";
;--- that's why the Q cmd isn't active as default.
;--- If activated, this code checks if current debuggee's CS is
;--- non-priviledged - if yes, it pokes a "dos exit" at the current
;--- instruction pointer. That's rather hackish, the current OS may
;--- not have implemented an int 21h API at all. However, it will work
;--- in many cases and hence seems better than nothing.

	@movs bx, [regs.rCS]
	.386
	lar ax, bx
	and ah, 60h
	jz @F		; can't exit in ring 0
	call IsWriteableBX
	mov edx, dword ptr [regs.rIP]
	push ds
	mov ds, bx
	mov dword ptr [edx], 21CD4CB4h	; mov ah,4ch , int 21h
	pop ds
	call run
	ret
@@:
	mov dx, offset plerr
	jmp int21ah9
	.8086
 else

  if ?DPMI
	mov byte ptr [dpmidisable+1],0	;disble DPMI hook
	inc [bNoHook2F]					;avoid a new hook while terminating
  endif

;--- cancel child's process if any
;--- this will drop to real-mode if debuggee is in pmode
  if ?DPMI
;--- v1.29: debugx: if debuggee is in pm, 'q' will try to terminate it - else it really quits
	call ispm_dbe
	jz realquit
	and al,TOUPPER
	cmp al,'Q'		;"qq" entered?
	jnz @F
	call exitdpmi
@@:
	call freemem
	jmp ue_int
realquit:
  endif
	call freemem

  if VDD
	mov ax,[hVdd]
	cmp ax,-1
	jz @F
	UnRegisterModule
@@:
  endif

  if VXCHG
   ifndef VXCHGFLIP
	mov dx,[xmsmove.dsthdl]
	and dx, dx
	jz @F
	push dx
   endif
	mov al,0             ; restore debuggee screen
	call swapscreen
   ifndef VXCHGFLIP
	pop dx
	mov ah,0Ah           ; and free XMS handle
	call [xmsdrv]
@@:
   endif
  endif
  if ALTVID
	call setscreen
  endif

;--- Restore interrupt vectors.

	mov di,offset intsave
	mov si,offset inttab
  if ?DPMI
	mov cx,NUMINTS+1
  else
	mov cx,NUMINTS
  endif
nextint:
	lodsb
	push ds
;	add si,2	; skip rest of INTITEM (now done below)
	lds dx, [di]
	add di,4
	cmp al,22h
	jz norestore
	mov bx, ds
	and bx, bx
	jz norestore
	mov ah,25h
	int 21h
norestore:
	pop ds
	lodsw		; skip rest of INTITEM (16-bit offset)
	loop nextint

  if INT22
;--- Restore termination address.
   if FMTEXE
	mov es, [pspdbg]
   endif
	mov si,offset psp22	;restore termination address
	mov di,PSPS.TPIV
	movsw
	movsw
	mov di,PSPS.PARENT	;restore PSP of parent
	movsw
  endif

;--- Really done.

;--- int 20h sets error code to 0.
;--- might be better to use int 21h, ax=4Cxxh
;--- and load the error code returned by the debuggee
;--- into AL.

  if FMTEXE
	mov ax, 4C00h
	int 21h
  else
	int 20h
  endif
	jmp cmdloop		;returned? then something is terribly wrong.

 endif

q_cmd endp

endif

if MMXSUPP
rm_cmd proc
	cmp [has_mmx],1
	jnz @F
	jmp dumpregsMMX
@@:
	ret
rm_cmd endp
endif

;--- RX command: toggle mode of R command (16 - 32 bit registers)

rx_cmd proc
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
;	mov al,0	; v2.0: removed
;	stosb
	call putsline
rx_exit:
	ret
rx_cmd endp

;--- RN command: display FPU status

rn_cmd proc
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
rn_cmd endp

;--- R command - manipulate registers.

r_cmd proc
	cmp al,CR
	jne @F		;if there's an argument
	jmp dumpregs
@@:
	cmp ah,'r'
	jnz @F
	and al,TOUPPER
	cmp al,'X'
	je rx_cmd
if MMXSUPP
	cmp al,'M'
	je rm_cmd
endif
	cmp al,'N'
	je rn_cmd
@@:

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

if RING0

CONST segment

exctab label byte	; ring 0 exc table used by SK, VC, VT
	db 0,1,3
 if CATCHINT06
	db 6
 endif
 if CATCHINT07
	db 7
 endif
 if CATCHINT0C
	db 0Ch
 endif
 if CATCHINT0D
	db 0Dh
 endif
	db 0Eh
SIZEEXCTAB equ $ - offset exctab

noskip db "No exception to skip",13,10,'$'
yesskip db "Exception skipped",13,10,'$'

CONST ends

;--- skip exception.
;--- actually, the only exceptions that cannot be skipped
;--- are breakpoints set by the debugger itself.

sk_cmd proc
	.386
	mov dl, [run_int+1]
	and dl, 1Fh
	mov cx, SIZEEXCTAB
	mov si, offset exctab
	mov bx, offset intsave
@@:
	lodsb
	cmp dl, al
	jz found
	add bx, sizeof INTVEC
	loop @B
	mov dx, offset noskip
	jmp int21ah9
found:
	xchg si, bx
	mov ebx, dword ptr [regs.rSP]
	mov dx, [regs.rSS]
 if V86M
	test byte ptr [regs.rFL+2], 2
	jnz isv86
 endif
	lar ax, [regs.rCS]
	and ah, 60h				; exception occured in ring 0?
	jz @F					; then there's no stack switch.
isv86:
	mov ebx, [regs.r0Esp]	; no, use saved r0 stack
	mov dx, [regs.r0SS]
	@dprintf "sk: r3 exc, old r0 ss:esp=%X:%lX, vec=%X", dx, ebx, si
	sub ebx, 2*4			; and correct esp for saved r3 ss:esp
 if V86M
	test byte ptr [regs.rFL+2], 2
	jz isv86_2
	sub ebx, 4*4			; for v86-mode, space for saved r3 regs es,ds,fs,gs
	and byte ptr [regs.rFL+2], not 2	; reset VM flag   
	xor ax, ax
	mov [regs.rDS], ax
	mov [regs.rES], ax
	mov [regs.rFS], ax
	mov [regs.rGS], ax
isv86_2:
 endif
@@:
;--- dx=ss, ebx=esp, esi -> intsave entry for exception
	bt [run_intw], 15	; exc with error code?
	jnc @F
	sub ebx, 1*4	; correct error code
@@:
	sub ebx, 3*4	; correct cs:eip & efl
	mov dword ptr [regs.rSP], ebx
	mov [regs.rSS], dx
	lodsd
	mov dword ptr [regs.rIP], eax
	mov dword ptr [u_addr], eax
	lodsw
	mov [regs.rCS], ax
	mov [u_addr+4], ax

	pushf
	pop ax
	mov byte ptr [regs.rFL+1], ah

	mov [run_int+1], -1		; reset run_int, so skip is "deactivated" for this time
	mov dx, offset yesskip
	jmp int21ah9

sk_cmd endp

endif

;--- S command - search for a string of bytes.

s_cmd proc
if RING0
	cmp ah,'s'
	jnz @F
	or al,TOLOWER
	cmp al, 'k'
	jz sk_cmd
@@:
endif
	call getrangeDS	;get address range into BX:(E)DX..BX:(E)CX
	call skipcomm0
	push cx
	push dx
	call getstr		;get string of bytes, size: di - (lineout+1)
	pop dx
	pop cx

	sub di,offset line_out	;di = number of bytes to look for
	dec di			;     minus one
if ?PM
	call IsOfs32
	jz @F
	.386
	@dprintf "s_cmd: bx:edx=%X:%lX, ecx=%lX, di=%X", bx, edx, ecx, di
	sub ecx, edx
	movzx edi, di
	sub ecx, edi
	jb errorj9		;if none
	.8086
	jmp s_cont
@@:
	@dprintf "s_cmd: bx:dx=%X:%X, cx=%X, di=%X", bx, dx, cx, di
endif
	sub cx,dx		;cx = number of bytes in search range minus one
	sub cx,di		;number of possible positions of string minus 1
	jb errorj9		;if none
s_cont:
	call prephack
;	inc cx			;cx = number of possible positions of string
	sizeprfX		;xchg edx, edi
	xchg dx,di		;set (E)DI to offset
	call dohack		;set debuggee's int 23/24

sss1:				;<---- search next occurance
	mov es, bx		;set the segment
	mov si,offset line_out	;si = address of search string
	lodsb			;first character in al
if ?PM
	call IsOfs32
	jz sss1_16
;	@dprintf "s_cmd scasb: es:edi=%X:%lX, ecx=%lX ax=%X", es, edi, ecx, ax
	.386
	repne scasb es:[edi]
	je @F
	scasb es:[edi]
	jnz sss3
@@:
	push ecx
	push edi
	movzx ecx, dx
	movzx esi, si
;	@dprintf "s_cmd cmpsb: es:edi=%X:%lX, ecx=%lX, ds:esi=%X:%lX", es, edi, ecx, ds, esi
	repe cmpsb ds:[esi], es:[edi]
	pop edi
	jne @F			;if not equal
	call displaypos
@@:
	pop ecx
	inc ecx
	loop sss1
	jmp unhack
	.8086
sss1_16:
endif
	repne scasb		;look for first byte
	je @F
	scasb			;count in CX was cnt-1
	jne sss3		;if we're done
@@:
	push cx
	push di
	mov cx,dx
	repe cmpsb
	pop di
	jne @F			;if not equal
	call displaypos
@@:
	pop cx
	inc cx
	loop sss1		;go back for more
sss3:
	jmp unhack		;set debugger's int 23/24

;--- display position
;--- the search string is in line_out.
;--- so we have to write to [SI] ( which here points just behind search string )

displaypos:
	call unhack		;set debugger's int 23/24
	push dx
	sizeprfX		;xchg esi, edi
	xchg si,di		;render position right after search string
	push di			;v2.02 save pos on stack (in v2.0-v2.01, it was saved in CX)
	push ds			;v2.02 restore ES; needed for hex(d)word
	pop es
	@dispsegm bx
	mov al,':'
	stosb
if ?PM
	call IsOfs32
	jz @F
	.386
	lea eax,[esi-1]
	.8086
	call hexdword
	jmp s_cont3
@@:
endif
	lea ax,[si-1]
	call hexword
s_cont3:
	mov ax,( LF shl 8 ) or CR
	stosw
	pop dx			;get pos from stack
	mov cx, di
	sub cx, dx
	call stdout		;write cx chars from ds:dx to stdout
	pop dx
	sizeprfX		;mov edi, esi
	mov di,si
	jmp dohack		;set debuggee's int 23/24

s_cmd endp

tm_cmd proc
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
	mov si, offset tmode0
	mov al, [tmode]
	and al, 1
	jz @F
	mov si, offset tmode1
@@:
	push si
	add al, '0'
	mov [tmodes2], al
	mov si, offset tmodes
	call copystring
	pop si
	call copystring
	call putsline
	ret

tm_cmd endp

;--- T command - Trace.

t_cmd proc
	cmp al, CR
	jz tt0
	or al,TOLOWER
	cmp ax,'tm'
	jz tm_cmd
tt0:
;	mov [lastcmd], offset tt0
	mov [lastcmd], offset t_cmd
	call parse_pt	;process arguments
@@:
	push cx
	call trace1
	pop cx
	loop @B
	ret

t_cmd endp

;--- trace one instruction

trace1 proc
if ?PM
	call getcsattr
	mov [bCSAttr],al
endif
if ?DPMI
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
	call doproceed1
	ret
trace1_1:
endif
	xor cx,cx
	call getcseipbyte
	cmp al,0CDh			; an INT instruction?
	jnz isstdtrace
	inc cx
	call getcseipbyte
	cmp al,3			; 2-byte INT 3?
	jz isstdtrace
	test byte ptr [tmode], 1	;TM=1?
	jz trace_int
	cmp al,1			; INT 1?
	jnz step_int
isstdtrace:
	or byte ptr [regs.rFL+1],1h	;set single-step mode
	xor cx,cx
	call getcseipbyte
	push ax
	call run
	pop ax
	cmp al,9Ch			;was opcode "PUSHF"?
	jnz @F
	call clear_tf_onstack
@@:
	cmp [run_int], EXC01MSG
	je tt1_1
	jmp ue_int			;if some other interrupt ( is always "unexpected" )
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
if USEHWBP and ?DPMI
	call ispm_dbe		; in protected-mode?
	jnz useproceed		; then don't check, optionally use hw bp 
endif
if RING0 and USEHWBP	; no check for DebugR if USEHWBP is 1
else
	mov cx,2
	call iswriteablecseip	;is current CS:IP in ROM?
	jc isstdtrace			;then do standard trace
endif
useproceed:
	@movs bx,[regs.rCS]
	sizeprfX			; mov esi,[regs.rIP]
	mov si,[regs.rIP]
if ?PM
	call inceip
	call inceip
else
	add si, 2
endif
	call doproceed1		;set BP at BX:(E)SI and run debuggee
	ret

;--- current instruction is INT, TM is 1, single-step into the interrupt
;--- AL=int#

step_int:
	mov bl,al
if ?PM
 if ?DPMI
	call ispm_dbg
	jz step_int_rm
	mov  ax,204h
	int  31h			;get vector in CX:(E)DX
	mov  bx,cx
	test bl,4			;is it a LDT selector?
	jnz  @F
	jmp  isstdtrace
@@:
	sizeprf		;mov  esi,edx
	mov  si,dx
 elseif RING0
	.386
  if FLATSS
	sub esp, 6
	sidt [esp]
  else
   if V86M
	test byte ptr [regs.rFL+2],2
	jnz step_int_rm
   endif
	push bp
	mov bp, sp
	sub sp, 6
	sidt [bp-6]
  endif
	pop ax
	pop eax
  ife FLATSS
	pop bp
  endif
	push ds
	mov ds, [wFlat]
	movzx ebx, bl
  if LMODE
	shl bx, 4
  else
	shl bx, 3
  endif
	mov si, ds:[ebx+eax+6]
	shl esi, 16
	mov si, ds:[ebx+eax+0]
	mov bx, ds:[ebx+eax+2]
	pop ds
 endif
	call doproceed1	; expects bp to be set at BX:(E)SI
	ret
endif
if (RING0 eq 0) or V86M
step_int_rm:
	mov bh,0
	push ds
 if V86M
	mov ds, [wFlat]
	movzx ebx, bx
	movzx eax, word ptr [ebx*4+2]
	shl eax, 4
	movzx esi, word ptr [ebx*4+0]
	add esi, eax
	mov bx, ds
	pop ds
 else
	xor ax,ax
	mov ds,ax
	shl bx,1		;stay 8086 compatible in real-mode!
	shl bx,1
	cli
	lds si,[bx+0]	; check if IVT is R/O? What's the purpose?
	mov al,[si]
	xor byte ptr [si],0FFh
	cmp al,[si]
	mov [si],al
	sti
	jz isrom
	mov bx,ds
	pop ds
 endif
	call doproceed1	; set bp at BX:ESI, then GO
	ret
 ife V86M
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
 endif
endif

trace1 endp

;--- test if memory at CS:E/IP can be written to.
;--- return C if not
;--- used by T cmd.
;--- IN: CX=offset for (E)IP

if RING0 and USEHWBP	; remove if RING==1 and USEHWBP==1
else
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
endif

;--- clear TF in the copy of flags register onto the stack

clear_tf_onstack proc
	push es
	@movs es, [regs.rSS]
if ?PM
	mov bx,es
;	call getseglimit      ; v1.29: segment limit doesn't matter,
	call getseldefsize    ; check defsize if ESP is to be used.
	jz @F
	.386
	mov ebx,dword ptr [regs.rSP]
	and byte ptr es:[ebx+1],not 1
	jmp ctos_1
	.8086
@@:
	@dprintf "clear_tf_onstack: es=%X", es
endif
	mov bx,[regs.rSP]
	and byte ptr es:[bx+1],not 1
ctos_1:
	pop es
	ret
clear_tf_onstack endp

;--- Print message about unexpected interrupt, dump registers, and end
;--- command.  This code is used by G, P and T cmds.

ue_int:
	mov dl, [run_int]
if RING0 and CATCHSYSREQ
	.386
	btr word ptr [bFlagsPM], 1
	jnc notsysreq
	btr word ptr [bFlagsPM], 2	; was exc01 in v86-mode temporarily untrapped?
	.8086
	jnc @F
	and byte ptr [wTrappedExc+2], not 2	; then restore the state of exc 01
@@:
	mov dl, SYSRQMSG
	push ds
	mov ds, [wFlat]
	and word ptr ds:[417h], not ( 200h or 8)	;reset "Alt pressed" flags
	pop ds
notsysreq:
endif
	mov dh, 0
	add dx, offset int0msg
	call int21ah9	;print string
if INT22
	cmp dx, offset progtrm
	je @F			;if it terminated, skip the registers
endif
	call dumpregs
@@:
	jmp cmdloop		;back to the start

;--- "unexpected" exception in real-mode inside debugger

ife RING0
 if CATCHINT07 or CATCHINT0C or CATCHINT0D or SKIPBPINDBG
ue_intxx:
  if EXCCSIP
	pop cx
	pop dx
  endif
	push cs
	pop ss
	mov sp,cs:[top_sp]
	push cx	; ip
	push dx	; cs
	push ax	; msg

;--- fall thru

 endif
endif


if ?PM or CATCHINT07 or CATCHINT0C or CATCHINT0D

;--- "unexpected" exception occured inside debugger
;--- [SP] = msg, cs, [e]ip

ue_intx proc
	cld
	@RestoreSeg ds
	call unhack		;set debugger's int 23/24
if ?PM
	test [disflags], DIS_I_MEMACC
	jz @F
	mov [disflags], 0
	mov dx,offset crlf
	call int21ah9
@@:
endif
	pop dx
	add dx, offset int0msg
	call int21ah9	;print string
if EXCCSIP
	push ds
	pop es
	mov di,offset line_out
	mov si,offset excloc	; "CS:IP="
	call copystring
	pop ax
	call hexword
	mov al,':'
	stosb
 if EXCCSEIP
	.386
	pop eax
	.8086
	call hexdword
 else
	pop ax
	call hexword
 endif
	call putsline
endif
	jmp cmdloop
ue_intx endp

endif

;--- U command - disassemble.

u_cmd proc
	mov [lastcmd],offset u_cmd
	mov cx,20h		;default length
	cmp al,CR
	je uuloop		;if no address was given
	@movs bx,[regs.rCS]
	call getrange	;get address range into bx:(e)dx/(e)cx
	call chkeol		;expect end of line here
	sizeprfX		;mov [u_addr+0],edx
	mov [u_addr+0],dx
	mov [u_addr+4],bx
	sizeprfX		;inc ecx
	inc cx
	sizeprfX		;sub ecx, edx
	sub cx, dx
	@dprintf "u_cmd: u_addr=%X:%lX, ecx=%lX", bx, edx, ecx

;--- At this point, e/cx holds the size
;--- the disassembler won't use any registers as parameters,
;--- it always disassembles the code at [u_addr] and updates
;--- that variable accordingly.

uuloop:
	sizeprfX		;push ecx
	push cx
	call disasm1	;disassemble one instruction
	sizeprfX		;pop ecx
	pop cx
if ?PM
	mov bx, [dis_n]	;bytes disassembled
	sizeprfX		;movzx ebx, bx
	lea bx, [bx]   
	sizeprfX		;sub ecx, ebx
	sub cx, bx
else
	sub cx, [dis_n]
endif
	ja uuloop		;if we haven't reached the goal
	ret
u_cmd endp

if WCMD

lockdrive:          ;lock logical volume
	push ax
	push bx
	push cx
	push dx
	mov bl,al
	inc bl
	mov bh,0		;lock level (0 means what?)
	mov cx,084Ah	;isn't this for non-FAT32 drives only?
	mov dx,0001h	;permission flags (1=allow writes)
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
;	mov bh,0		;bh has no meaning for unlock
	mov cx,086Ah	;isn't this for non-FAT32 drives only?
;	mov dx,0001h
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
if WCMDFILE
	jz write_file	;if request to write program
else
	jz cmd_error	;no support to write program
endif
if NOEXTENDER
	call ispm_dbg
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
	mov cx,"rw"		;cx:dx="writ"
	mov dx,"ti"
;	jmp disp_diskresult	; fall thru to disp_diskresult

w_cmd endp

;--- display disk access result ( C if error )
;--- CX:DX="read"/"writ"

disp_diskresult proc
	mov bx,ss		;restore segment registers
	mov ds,bx
	mov sp,[top_sp]
	mov es, bx
	jnc ww3		;if no error
	mov word ptr [szDrive+1], cx
	mov word ptr [szDrive+3], dx
	add [driveno], 'A'
	cmp al,0ch
	jbe @F		;if in range
	mov al,0ch
@@:
	cbw
;	shl ax,1	; v2.0: removed - dskerrs is a byte offset table
	xchg si, ax
	mov al, [si+dskerrs]
	mov si, offset dskerr0
	add si, ax
	mov di, offset line_out
	call copystring
	mov si, offset szDrive
	call copystring
	call putsline
ww3:
	jmp cmdloop		;can't ret because stack is wrong

disp_diskresult endp

endif

if WCMDFILE

;--- Write to file.  First check the file extension.
;--- size of file to be written is in client's BX:CX, 
;--- default start address is DS:100h

write_file proc
	mov al,[fileext]	;get flags of file extension
	test al,EXT_EXE + EXT_HEX
	jz @F				;if not EXE or HEX
	mov dx,offset nowhexe
	jmp exitwithmsg
@@:
	cmp al,0
	jnz ww7		;if extension exists
	mov dx,offset nownull
exitwithmsg:
	jmp int21ah9

;--- File extension is OK; write it.  First, create the file.
;--- bx:e/dx = start address

ww7:
if ?DPMI
	call ispm_dbg
	jz @F
	mov dx,offset nopmsupp	;cmd rejected in protected-mode
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
if FMTEXE
	push ds
	mov ds, [pspdbg]
endif
	xor cx,cx		;no attributes
	mov dx,PSPS.DTA
	mov ah,3ch		;create file
	call doscall
if FMTEXE
	pop ds
endif
	jc io_error		;if error
	push ax			;save file handle

;--- Print message about writing.

	mov dx,offset wwmsg1
	call int21ah9	;print string
	mov ax,[regs.rBX]
	cmp ax,10h		;max size = 0fffffh
	jb @F			;if not too large
	xor ax,ax		;too large:  zero it out
@@:
	mov [bp+8],ax
	or ax,ax
	jz @F
	call hexnyb		;convert to hex digit and print
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
if FMTEXE
	push ds
	mov ds, [pspdbg]
endif
	mov dx,PSPS.DTA
	mov ah,41h		;unlink file
	call doscall
if FMTEXE
	pop ds
endif

;--- Close the file.

ww14:
	mov ah,3eh		;close file
	int 21h
	ret
write_file endp

endif

if LCMDFILE or WCMDFILE

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

;--- fall thru

endif

int21ah9:
ife RING0
 if 1 ;v2.0: check InDos, if set use stdout()
	call InDos
	jnz use_stdout
 endif
	mov ah,9
	call doscall
	ret
endif
if 1 ;v2.0: get size of $-string DS:DX, then call stdout; SI, CX not modified
use_stdout:
	push si
	push cx
	mov si, dx
@@:
	lodsb
	cmp al, '$'
	jnz @B
	dec si
	sub si, dx
	mov cx, si
	call stdout
	pop cx
	pop si
	ret
endif

if XCMDS

;--- X commands - manipulate EMS memory.

;--- XA - Allocate EMS.
;--- DX = pages

xa proc
	call chkeol		;expect end of line here
	mov bx,dx
	mov ah,43h		;allocate handle
	and bx,bx
	jnz @F
	mov ax,5A00h	;use the EMS 4.0 version to alloc 0 pages
@@:
	call emscall
	push dx
	mov si,offset xaans	; "Handle created: "
	call copystring
	pop ax
	call hexword
	jmp putsline	;print string and return
xa endp

;--- XD - Deallocate EMS handle.
;--- DX = handle

xd proc

	call chkeol		;expect end of line here
	mov ah,45h		;deallocate handle
	call emscall
	push dx
	mov si,offset xdans	; "Handle deallocated: "
	call copystring
	pop ax
	call hexword
	jmp putsline	;print string and return

xd endp

;--- x main dispatcher

x_cmd proc
	cmp al,'?'
	je xhelp	;if a call for help
	push ax
	call emschk
	pop ax
	or al,TOLOWER
	cmp al,'s'
	je xs		;if XS command
	push ax
	call skipcomma
	call getword
	pop cx
	cmp cl,'a'
	je xa		;if XA command
	cmp cl,'d'
	je xd		;if XD command
	cmp cl,'r'
	je xr		;if XR command
	cmp cl,'m'
	je xm		;if XM command
	jmp cmd_error

xhelp:
	mov dx,offset xhelpmsg
	mov cx,size_xhelpmsg
	jmp stdout	;print string and return
x_cmd endp

;--- XR - Reallocate EMS handle.
;--- DX = first argument (=handle)

xr proc
	mov bx,dx
	call skipcomma
	call getword		;get count argument into DX
	call chkeol			;expect end of line here
	xchg bx,dx
	mov ah,51h			;reallocate handle
	call emscall
	mov si,offset xrans	; "Handle reallocated: "
	call copystring
	jmp putsline		;print string and return

xr endp

;--- XM - Map EMS memory to physical page.
;--- DX = first argument [=logical page (FFFF means unmap)]

xm proc
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
	cmp ah,83h		; error "invalid handle"?
	je xs2			;if no such handle
	or ah,ah
	jz @F
	jmp ems_err		;if other error
@@:
	xchg ax,bx		;mov ax,bx
	call hndlshow
xs2:
	inc dl
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
;--- in case of error, return to cmd loop

emscall proc
if ?DPMI
	call ispm_dbg
	jz ems_rm
	.286
	invoke simrealmodeint, 67h, cs:[wDgroup]
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
	cbw			;80->ff80 ... 8B->ff8B
	mov bx,ax
	shl bx,1	;ff80->ff00 ... ff8B->ff16
	mov si,[emserrs+100h+bx]
	or si,si
	jnz ems_err3	;if there's a word there
ce2:
	mov di,offset emserrxa
	call hexbyte
	mov si,offset emserrx
ems_err3::
	mov di,offset line_out
	call copystring	;si->di
	call putsline
	jmp cmdloop

ems_err endp

;--- Check for EMS

emschk proc
if ?DPMI
	call ispm_dbg
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
	jmp ems_err3
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
	call trimhex			; ax ( skip leading zeros )
	mov si,offset xsstr3	; " of a total "
	call copystring
	xchg ax,dx				; mov ax,dx
	call trimhex
	mov si,offset xsstr3a	; " EMS "
	call copystring
	mov si,bx				; "pag"/"handl"
	call copystring
	mov si,offset xsstr3b	; "es have been allocated"
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

if LCMDFILE

;--- FREEMEM - cancel child process

freemem proc

;	@dprintf "freemem enter"
	mov [regs.rCS],cs
	mov [regs.rIP],offset fmem2
	mov [regs.rFL], 202h; v1.29: ensure TF is clear ( TF=1 may cause "memory corrupt" error if returning to DOS )
 if ?DPMI
	xor ax,ax
	mov [regs.rIP+2],ax
	mov [regs.rSP+2],ax
 endif
	mov [regs.rSS],ss
	push ax
	mov [regs.rSP],sp	; save sp-2
	pop ax
	call run
;	@dprintf "freemem back from run"
	cmp [run_int],INT22MSG	; v2.50: in case prog termination failed...
	jnz ue_int				; stop and display msg
	ret
fmem2:
 if ?DPMI
	mov ax,4cffh
 else
	mov ax,4c00h	;quit
 endif
	int 21h
freemem endp

 if INT2324

;--- setint2324 is called by "run", to set debuggee's INT 23/24.
;--- Don't use INT 21h here, DOS might be "in use".
;--- Registers may be modified - will soon be set to debuggee's...
;--- counterpart is getint2324().

setint2324 proc
	mov si,offset run2324
  if ?DPMI
	call ispm_dbg
	jnz si2324pm
  endif
	push es

	xor di,di
	mov es, di
	mov di,23h*4
	movsw
	movsw
	movsw
	movsw

  if ?DPMI
	call InDos
	jnz @F
	call hook2f
@@:
  endif

	pop es
	ret
  if ?DPMI
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

 endif	; INT2324

endif	; LCMDFILE

if RING0
	.386
checksegm proc
	lar ax, [regs.rCS]
	jnz error
	test ah, 8
	jz error
	lar ax, [regs.rSS]
	jnz error
	test ah, 8
	jnz error

	mov cx, 4
	mov si, offset regs.rDS
nextitem:
	lodsw
	and ax, 0fffch
	jz @F
	lar ax, ax
	jnz error
@@:
	loop nextitem
	ret
error:
	stc
	ret
checksegm endp

endif

if USEHWBP

WPENABLE equ 1	;local wp enable
;WPENABLE equ 2	;global wp enable

;--- DR6 (debug status register):
;--- bits 0-3: 1=bp# condition detected (must be cleared by software)
;--- bit 12: read as 0
;--- bit 13: BD, debug register access detected 
;--- bit 14: BS, bp single step
;--- bit 15: BT, bp task switch
;--- rest of bits read as 1
;--- DR7 (debug control register):
;--- bit 0-7: L0,G0 - L3,G3
;--- bit 8-9: LE,GE
;--- type ( optional 2. argument ) will be copied to bits 16-31 (RWx,LENx)
;--- bp0 bit 16-17: type (0=exec, 1=write, 2=I/O [if CR4.DE=1], 3=read or write)
;--- bp0 bit 18-19: len (0=1 byte, 1=2 byte, 2=8 byte, 3=4 byte )

;--- map (hard) breakpoints to debug registers
;--- entry will be patched to NOP NOP if hw bp enabled!

setHWBps proc
	clc
	ret
if ?DPMI
	mov bp, offset pmsethwbp
	call ispm_dbg
	jnz @F
endif
	mov bp, [wRMSetBP]
@@:
	xor cx, cx
	mov si, offset HWBps
	.386
nextbp:
	lodsd
	xchg eax, edx
	lodsb
	test al, BP_USED
	jz skipbp
	@dprintf "setHWBps %lX", edx
	xchg eax, edx
	push cx
	call bp
	pop cx
	jc error
	or byte ptr [si-1], BP_ACTIVE
;	or byte ptr [regs.rFL+2], 1	; set resume flag so a hwbp at cs:eip will be skipped (see comment below)
skipbp:
 if ?DPMI
	lodsw
 endif
	inc cx
	cmp cl, MAXHWBP
	jnz nextbp
;--- set resume flag generally - another debugger
;--- might have set a HW bp, and without RF=1 we would be stuck...
	or byte ptr [regs.rFL+2], 1
	ret
error:
	call resetHWBps
	stc
	ret
if ?DPMI
pmsethwbp: 
	push eax
	pop cx
	pop bx
	mov dh, dl
	shr dl, 2		; dl = size (was in bits 2-3)
	and dx, 303h	; dh = type (0=exec,1=read, 2=r/w)
	add dl, 1		; 0->1, 1->2, 3->4
	@dprintf "pmsethwbp bx:cx=%X%04X dx=%X", bx, cx, dx
	mov ax, 0b00h	; set watchpoint
	int 31h
	jc @F
	mov [si], bx
	@dprintf "pmsethwbp hdl=%X", bx
	mov ax, 0b03h	; clear status in dr6
	int 31h
@@:
	retn
endif

if 1; it's used both in ring0 and real-mode

r0sethwbp::
	call setdrreg
	mov eax, dr6
	btr ax, bx
	mov dr6, eax
	mov eax, dr7
	and edx, 0fh	; type in bits 0-3
	mov ebx, 0fffffff0h
	push cx
	shl cl, 2
	add cl, 16		; cl = 16|20|24 for bp0|1|2
	shl edx, cl
	rol ebx, cl
	pop cx
	and eax, ebx
	or eax, edx		; set type (RW0, LEN0 )
	mov bl, WPENABLE
	shl bl, cl
	shl bl, cl
	or al, bl		; set G|L0|1|2=1
	or ah, WPENABLE	; set G|LE=1 ("legacy")
	mov dr7, eax
  ifdef _DEBUG
	mov ebx, dr6
	@dprintf "r0sethwbp dr7=%lX dr6=%lX", eax, ebx
  endif
	retn
setdrreg::
	movzx bx, cl
	shl bx, 2
	add bx, offset setdrx
	jmp bx
setdrx:
	mov dr0, eax
	retn
	mov dr1, eax
	retn
	mov dr2, eax
	retn
	mov dr3, eax
	retn
endif
setHWBps endp

;--- unmap (hard) breakpoints from debug registers
;--- entry will be patched to NOP if hw bp enabled!

;--- todo: for ring0, it's probably a good idea not to just
;--- scan the bp table, but check the debug registers directly.
;--- they may have been set by another PL0 debugger and
;--- perhaps we want to cooperate by importing the bp?
;--- At the very least, it should be checked if the addresses
;--- in HWBps and DR0-3 do match. If no, a warning is to be
;--- emitted.

resetHWBps proc
	ret
	mov [bBPhit], 0
if ?DPMI
	mov bp, offset pmresethwbp
	call ispm_dbg
	jnz @F			; skip if in real/v86-mode
endif
	mov bp, [wRMResetBP]
@@:
	xor cx, cx
	mov dl, not 11b
	mov si, offset HWBps
nextbp:
	lodsd
	lodsb
	test al, BP_ACTIVE
	jz skipbp
	and al, not BP_ACTIVE
	test al, BP_TEMP
	jz @F
	mov al, 0
@@:
	and [si-1], al
	call bp
skipbp:
 if ?DPMI
	lodsw
 endif
	rol dl, 2
	inc cx
	cmp cl, MAXHWBP
	jb nextbp
	ret

 if ?DPMI
pmresethwbp:
	mov bx, [si]
	mov ax, 0b02h	; get status
	int 31h
	add [bBPhit], al
	mov ax, 0b01h	; clear watchpoint
	int 31h
	@dprintf "pmresetHWBps hdl=%X", bx
	retn
 endif
r0resethwbp::
	xor eax, eax
	call setdrreg
	mov eax, dr7
	and al, dl		; disable G0|1|2
	mov dr7, eax
  if 1
	mov eax, dr6
	btr ax, cx		; clear bit in DR6
	adc [bBPhit],ch
	mov dr6, eax
  endif
	@dprintf "r0resethwbp bp#=%X", cx
	retn
resetHWBps endp

	.8086

endif ; USEHWBP

;--- This is the routine that starts up the running program.

run proc

if RING0
;--- check segment values, since there's no stack switch if a GPF occurs.
 if V86M
	test byte ptr [regs.rFL+2], 2	;v86-mode?
	jnz @F
 endif
	call checksegm
	mov dx, offset segerr
	jc int21ah9
@@:
endif

if USEHWBP
	call setHWBps
	mov dx, offset cantwritebp
	jc int21ah9
endif

if RING0
	mov al, 0
	call srscratch	; restore scratch GDT entry
endif

	call seteq		;set CS:E/IP to '=' address

;--- set debuggee context
if VXCHG
	mov al, 0       ;restore debuggee screen
	call swapscreen
endif
if ALTVID
	call setscreen
endif
if LCMDFILE
	mov bx,[pspdbe]
	call setpsp		;set debuggee's PSP
 if INT2324
	call setint2324	;set debuggee's int 23/24
 endif
endif
if ?DPMI
	call setdbeexc0d0e
endif

if FLATSS
	.386
	mov [run_sp],esp	;save stack position
else
	mov [run_sp],sp		;save stack position
endif
ife (DRIVER or BOOTDBG or RING0)
	; 16.2.2021: check if saved SS is debugger's SS. If no, don't adjust saved SP.
	; SS may be != saved SS if debugger is stopped in protected-mode - then the
	; current DPMI real-mode stack may be stored in PSPS.SPSAV.
 if FMTEXE
	mov cx, ds
	@ds_mypsp
 endif
	mov ax,ss
	cmp ax,word ptr ds:[PSPS.SPSAV+2]
	jnz @F
	sub sp,[spadjust]
	mov word ptr ds:[PSPS.SPSAV],sp
@@:
 if FMTEXE
	mov ds, cx
 endif
endif
ife RING0
	cli
endif
if FLATSS
	push ds
	pop ss
endif
if RING0
	@dprintf "r0 ss:esp=%X:%lX efl=%lX", word ptr [regs.r0SSEsp+4], dword ptr [regs.r0SSEsp], dword ptr [regs.rFL]
endif
	mov sp,offset regs
ife RING0
	cmp [machine],3
	jb @F
	.386
	popad
	pop es		;temporary load DS value into ES (to make sure it is valid)
	pop es		;now load the true value for ES
	pop fs
	pop gs
	jmp loadss
	.8086
@@:
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
	pop es	; that's DS
	pop es
	add sp,2*2	; skip places for FS,GS
else
	.386
 if 0;LMODE
;--- FS and GS might be "unset" ( still containing real-mode values )
;--- so check if value has changed and if not, don't write the regs
	mov ax, fs
	cmp ax, [regs.rFS]
	jz @F
	mov fs, [regs.rFS]
@@:
	mov ax, gs
	cmp ax, [regs.rGS]
	jz @F
	mov gs, [regs.rGS]
@@:
 endif
 if V86M
	test byte ptr [regs.rFL+2], 2
	jz @F
	popad
	lss esp, [regs.r0SSEsp]
	mov [bInDbg],0
	push 0
	push [regs.rGS]
	push 0
	push [regs.rFS]
	push 0
	push [regs.rDS]
	push 0
	push [regs.rES]
	push 0
	push [regs.rSS]
	push dword ptr [regs.rSP]
	push dword ptr [regs.rFL]
	push 0
	push [regs.rCS]
	push dword ptr [regs.rIP]
	iretd
@@:
 endif
	lar ax, [regs.rCS]
	and ah, 60h
	popad
	pop es
	pop es
 if 0;LMODE
	lea sp,[esp+2+2]
 else
	pop fs
	pop gs
 endif
	jz @F
	lss esp, [regs.r0SSEsp]		; debuggee runs in non-privileged mode, so
	push dword ptr [regs.rSS]	; create a full IRETD stack frame with SS:ESP
	push dword ptr [regs.rSP]
	jmp r0exit
@@:
endif
loadss:
	pop ss
patch_movsp label byte		;patch with 3Eh (=DS:) if cpu < 386
	db 66h				;mov esp,[regs.rSP]
	mov sp,[regs.rSP]	;restore program stack
r0exit:
	sizeprf				;push dword ptr [regs.rFL]
	push [regs.rFL]
	sizeprf				;push dword ptr [regs.rCS]
	push [regs.rCS]
	sizeprf				;push dword ptr [regs.rIP]
	push [regs.rIP]
	mov [bInDbg],0
if RING0
	mov ds,[regs.rDS]
else
	test byte ptr [regs.rFL+1],2	;IF set?
	mov ds,[regs.rDS]
	jz @F
	sti					; required for ring3 protected mode if IOPL==0
@@:
patch_iret label byte	; patch with CFh (=IRET) if cpu < 386
endif
	.386
	iretd				; jump to program
	.8086
run endp

;--- debugger entries

if RING0
 if LMODE
	include <TRAPPL.INC>
 elseif V86M
	include <TRAPPV.INC>
 else
	include <TRAPP.INC>
 endif
else
	include <TRAPR.INC>
endif

;--- fall thru
;--- also: entry DPMI protected-mode
;--- in: SS:SP=regs.rSS

intrtn proc

;--- DWORD pushs are safe here

	cmp cs:[machine],3
	jb @F
	.386
ife RING0
	pushfd
	popf		;skip LoWord(EFL)
	pop word ptr ss:[regs.rFL+2]
endif
	push 0
	pushf
	popfd		;clear HiWord(EFL) inside debugger (resets AC flag)
	push gs
	push fs
	push es
	push ds
	pushad
	jmp intrtn1
	.8086
@@:
	sub sp, 2*2	; skip space for GS, FS
	push es
	push ds
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
if RING0
	.386
 if FLATSS
	mov ss, cs:[wFlat]
	mov esp, cs:[run_sp]	;restore running stack
 else
	movzx esp,cs:[run_sp]	;restore running stack
 endif
else
	mov sp,cs:[run_sp]	;restore running stack
endif
	cld
	@RestoreSeg ds
ife RING0
	sti					;interrupts back on
endif

;if ?PM
 if ?DPMI
;--- calling int 2Fh here is a problem, since breakpoints aren't reset yet.
;--- this makes it impossible to trace this interrupt.
  if 0;DPMIMSW
	mov ax,1686h	; actually, fn 1686h tells if int 31h API is available
	int 2Fh
	cmp ax,1
	sbb ax,ax
  else
	mov ax,cs		;v2.50: adjusted so it works for both .COM and .EXE formats
	mov dx,ds
	sub ax,dx		;Z=rm,NZ=pm
	cmp ax,1		;C=rm,NC=pm
	cmc             ;NC=rm,C=pm
	sbb ax,ax		;0=rm,-1=pm
  endif
	mov [regs.msw],ax	;0000=real-mode, FFFF=protected-mode
 endif
;endif

ife (BOOTDBG or RING0)
	call getpsp
	mov  [pspdbe],bx
endif

	push ds
	pop es
	mov [bInDbg],1		; v2.0: must be set before setdbgexc0d0e

;--- set debugger context

if INT2324
	call getint2324		;save debuggee's int 23/24, set debugger's int 23/24
endif
if ?DPMI
	call setdbgexc0d0e
endif
if RING0
	cmp [run_int], EXC0EMSG
	jnz @F
	call rendercr2		; add value of CR2 to msg
@@:
	mov al, 1
	call srscratch		;save GDT scratch entry
endif

if USEHWBP
	call resetHWBps
endif

if LCMDFILE
	call setpspdbg		;set debugger's PSP
endif
	and byte ptr [regs.rFL+1],not 1	;clear single-step interrupt

;	mov [bInDbg],1		; v2.0: do this earlier ( see above )
if INT22
	cmp [run_int], INT22MSG
	jnz @F
 if ?DPMI
	mov [cssel],0		;reset flag 'initial switch has occured'
 endif
	mov ah,4Dh
	int 21h
	mov di,offset progexit
	call hexword
@@:
endif
ifdef FORCETEXT
	call checkgfx		; see if current mode is gfx, set to text if yet
endif
if VXCHG
	mov al, 1           ; restore debugger screen
	call swapscreen
 ifndef VXCHGFLIP
	push es
	mov ax, 0040h
	mov es, ax
	mov al, es:[84h]    ; did the number of screen rows change?
	mov bh, es:[62h]    ; BH=video page
	mov [vpage], bh
	cmp al, [vrows]
	mov [vrows], al
	jz @F
	mov dh, al          ; yes. we cannot fully restore, but at least clear
	mov dl, 0           ; bottom line to ensure the debugger displays are seen.
	mov ah, 2           ; set cursor pos
	int 10h
	mov bl, 07h         ; BL=attribute, BH=video page
	mov cx, 80          ; CX=columns
	mov ax, 0920h       ; AL=char to display
	int 10h
@@:
	pop es
 else
;--- with page flips, there are problems with many BIOSes:
;--- the debugger displays may get the color of the debuggee!
;--- if there's any trick to convince the BIOS not to do this,
;--- implement it here!
    mov [vpage], 1
 endif
endif
if ALTVID
	call setscreen
endif
	@dprintf "debug entered"
	ret

ifdef FORCETEXT
checkgfx:
	mov dx, 3CEh 			; see if in graphics mode
	in al, dx
	mov bl, al
	mov al, 6
	out dx, al
	inc dx
	in al, dx
	xchg bl, al
	dec dx
	out dx, al
	test bl, 1
	jz @F
	mov ax, 0003h
	int 10h
@@:
	retn
endif
intrtn endp

if USEHWBP

;--- set a hw bp at bx:edx;
;--- bx and edx must be preserved.
;--- this proc is called only if cpu is 80386+
;--- and hw debug registers are accessible.
;--- modifies DI!

	.386

sethwbptmp proc
	push di
	push edx
	call findfreehwbp
	pop edx
	jc @F
	add eax, edx
	@dprintf "sethwbptmp: linear=%lX (cs:eip=%X:%lX)", eax, bx, edx
	stosd
	mov al, BP_CODE or BP_USED or BP_TEMP
	stosb
@@:
	pop di
	ret
sethwbptmp endp

;--- find a free place in hw bp table
;--- bx=segment/selector
;--- out: C if error
;---     NC ok, then
;---     EAX= bx base
;---     DI = free entry in hw bp table

	.386

findfreehwbp proc
	mov di, offset HWBps
	mov cx, MAXHWBP
@@:
	test [di].HWBPSTRUCT.bType, BP_USED
	jz @F
	add di, sizeof HWBPSTRUCT
	loop @B
	stc
	ret
@@:
 if RING0
	call getlinearbaseDT	; eax=base of descriptor table for BX
	jc @F
	call getlinearbaseBX	; eax=base of BX
@@:
 else
  if ?DPMI
	call ispm_dbg		; in protected-mode?
	jz rmbase
	mov ax, 6
	int 31h
	jc @F				; can't get base of BX
	push cx
	push dx
	pop eax
@@:
	ret
rmbase:
  endif
	movzx eax, bx
	shl eax, 4
v86patch::
	nop
 endif
	ret
findfreehwbp endp
	
	.8086

endif

if BCMD

CONST segment
no_free_bp db "All BPs used",CR,LF,'$'
bp_not_set db "BP isn't set",CR,LF,'$'
b_inactive db "cmd inactive",CR,LF,'$'
CONST ends

;--- handle BP/BC cmds.
;--- this code will only run if cpu is 80386+.

	.386

b_cmd proc
	cmp ah, 'b'
	jnz b_err
	or al, TOLOWER
	cmp al, 'c'     ; is it BC?
	jz bc_cmd
	cmp al, 'p'     ; or BP?
	jz bp_cmd
b_err:
	jmp cmd_error   ; anything else is unknown
bc_cmd:
	call skipwhite
	cmp al,CR       ; no argument given? then just display status...
	jz b_err
	call getbyte	; get byte into DL
	call chkeol
	movzx ax, dl
	cmp al, MAXHWBP
	jnb b_err
	imul ax, sizeof HWBPSTRUCT
	mov bx, ax
	mov al, 0
	xchg al,[bx][HWBps].bType
	test al, BP_USED
	mov dx, offset bp_not_set
	jz b_errmsg
	ret
bp_cmd:
	call skipwhite
	cmp al,CR       ; no argument given? then just display status...
	jz bp_disp
	@movs bx,[regs.rCS];default segment to use
	call getaddr	; get address into bx:e/dx
	call skipwh0
	push edx
	mov dl, 0		; default type: 0=exec (1=write,2=io,3=rw)
	cmp al,CR       ; second argument (=type) given?
	jz @F
	call getbyte	; get byte into DL
	call chkeol
@@:
	push dx
	call findfreehwbp
	pop dx		; restore type
	pop ecx		; get offset
	jc @F
	add eax, ecx
	stosd
	mov al, dl
	and al, 30h
	and dl, 03h
	shr al, 2
	or  al, dl
	and al, 0fh		; real type is 4 bits only
	or al, BP_USED
	stosb
	ret
@@:
	mov dx, offset no_free_bp
b_errmsg:
	jmp int21ah9
b_cmderr::
	mov dx, offset b_inactive
	jmp b_errmsg

bp_disp:
	mov si, offset HWBps
	xor cx, cx
nextbp:
	lodsd
	xchg edx, eax
	lodsb
	@dprintf "bp: cx=%X, edx=%lX, al=%X", cx, edx, ax
	test al, BP_USED
	jz skipbp
	mov di, offset line_out
	push cx
	push ax
	mov ax,"pB"
	stosw
	mov al, cl
	add al, '0'
	mov ah, ':'
	stosw
	mov eax, edx
	call hexdword
	mov al, ' '
	stosb
	pop ax
	mov ah, al
	shl ah, 2
	and al, 3
	and ah, 30h
	or al, ah
	call hexbyte
	call putsline
	pop cx
skipbp:
if ?DPMI
	lodsw
endif
	inc cx
	cmp cl, MAXHWBP
	jnz nextbp
	ret
b_cmd endp

	.8086

endif

if VXCMD

	.386

CONST segment
notrappedexc db "No exc to (un)trap",13,10,'$'
CONST ends

getexc proc
	call skipwhite
	call getbyte		; get byte into DL
	call skipcomm0
	mov bl,1+2			; default: 0 & 3
	cmp al, CR
	jz both
	push dx
	call getbyte
	call chkeol			;expect end of line here
	mov bl, 1
	cmp dl, 0
	jz @F
	mov bl, 2
	cmp dl, 3
	jnz cmd_error
@@:
	pop dx
both:
	mov si, offset exctab
	mov cx, SIZEEXCTAB
nextitem:
	lodsb
	cmp al, dl
	loopnz nextitem
	jz @F
	pop ax
	mov dx, offset notrappedexc
	jmp int21ah9
@@:
	mov dh, 0
	ret
getexc endp

;--- clear trapped vector: VC exc#

vc_cmd proc
	call getexc
	test bl, 1
	jz @F
	btr [wTrappedExc], dx
@@:
	test bl, 2
	jz @F
	btr [wTrappedExc+2], dx
@@:
	ret
vc_cmd endp

;--- trap vector: VT exc#

vt_cmd proc
	call getexc
	test bl, 1
	jz @F
	bts [wTrappedExc], dx
@@:
	test bl, 2
	jz @F
	bts [wTrappedExc+2], dx
@@:
	ret
vt_cmd endp

;--- list trapped vectors: VL

vl_cmd proc
	call skipwhite
	call chkeol			; expect end of line here
	mov si, offset exctab
	mov bx, offset intsave
	mov cx, SIZEEXCTAB
nextitem:
	mov di, offset line_out
	push cx
	lodsb
	movzx dx, al
	call hexbyte
	mov al, ' '
	stosb
	mov ax, [bx+4]
	call hexword
	mov al, ':'
	stosb
	mov eax, [bx+0]
	call hexdword
	bt [wTrappedExc], dx
	jnc @F
	mov ax, "0 "
	stosw
@@:
	bt [wTrappedExc+2], dx
	jnc @F
	mov ax, "3 "
	stosw
@@:
	call putsline
	pop cx
	add bx, sizeof INTVEC
	loop nextitem
	ret
vl_cmd endp

	.8086

endif

if VXCHG

;--- show debuggee screen, wait for a keypress, then restore debugger screen

v_cmd proc
 if VXCMD
 	cmp ah, 'v'
	jnz @F
	or al, TOLOWER
	cmp al, 'c'
	jz vc_cmd
	cmp al, 'l'
	jz vl_cmd
	cmp al, 't'
	jz vt_cmd
@@:
 endif
	cmp al,CR
	jnz cmd_error
	mov al,0
	call swapscreen
 if 0;ndef VXCHGBIOS   ; v2.0: no longer needed, swapscreen has set cursor
;--- swapscreen has restored screen and cursor pos, but we want
;--- the cursor be shown on the screen - so set it thru BIOS calls.
	mov ah, 0Fh        ; get current mode (and video page in BH)
	int 10h
	mov ah, 3          ; get cursor pos of page in BH
	int 10h
	mov ah, 2          ; set cursor pos of page in BH
	int 10h
 endif
	mov ah, 10h
if RING0
	.386
	call cs:[int16vec]
	.8086
else
	int 16h
endif
	mov al, 1
	call swapscreen
	ret
v_cmd endp

;--- AL=0: save debugger screen, restore debuggee screen
;--- AL=1: save debuggee screen, restore debugger screen

swapscreen proc
 ifndef VXCHGFLIP
	.errnz BOOTDBG or RING0,<v cmd with XMS swap not supported>
	mov si, offset xmsmove
	cmp [si].XMSM.dsthdl,0
	jz done
	.286
	shl ax, 14      ; 0->0000, 1 -> 4000h
	mov word ptr [si].XMSM.dstadr, ax

;--- use offset & size of current video page as src/dst for
;--- xms block move. Also toggle cursor pos debuggee/debugger.

	push 0040h  ; 0040h is used because it also works in protected-mode
	pop es
	mov ax, es:[4Ch]
	mov word ptr [si].XMSM.size_, ax
	mov ax, es:[4Eh]
	mov word ptr [si].XMSM.srcadr+0, ax

;--- get/set cursor pos manually for speed reasons.
	mov bl, es:[62h]
	mov bh, 0
	shl bx, 1
	mov dx, es:[bx+50h]  ; get cursor pos of current page
	xchg dx, [csrpos]
if 0
	mov es:[bx+50h], dx
else
	mov bh, es:[62h]
	mov ah, 2
	int 10h
endif

	push ds
	pop es

	mov ah,0Bh           ; save video screen to xms
	call runxms
	call swapsrcdst

	xor byte ptr [si].XMSM.srcadr+1, 40h

	mov ah,0Bh           ; restore video screen from xms
	call runxms
	call swapsrcdst
 else
    mov ah, 05h          ; just use BIOS to activate video page
  if RING0
	.386
	call cs:[int10vec]
	.8086
  else
	int 10h
  endif
 endif
done:
	ret

 ifndef VXCHGFLIP
	.8086
swapsrcdst:
	mov ax, [si].XMSM.srchdl
	mov cx, word ptr [si].XMSM.srcadr+0
	mov dx, word ptr [si].XMSM.srcadr+2
	xchg ax, [si].XMSM.dsthdl
	xchg cx, word ptr [si].XMSM.dstadr+0
	xchg dx, word ptr [si].XMSM.dstadr+2
	mov [si].XMSM.srchdl, ax
	mov word ptr [si].XMSM.srcadr+0, cx
	mov word ptr [si].XMSM.srcadr+2, dx
	ret
runxms:
  if ?DPMI
	call ispm_dbg
	jnz @F
  endif
	call [xmsdrv]
	ret
  if ?DPMI
@@:
	.286
	xor cx, cx
	push cx          ; ss:sp
	push cx
	push word ptr [xmsdrv+2]    ; cs
	push word ptr [xmsdrv+0]    ; ip
	push cx          ; fs,gs
	push cx
	push [wDgroup]   ; ds
	push 0           ; es
	pushf
	sub sp, 8*4
	sizeprf        ;mov edi, esp
	mov di, sp
	mov es:[di].RMCS.rSI, si
	mov es:[di].RMCS.rAX, ax
	mov bh, 0
	mov ax,301h
	int 31h
	add sp, sizeof RMCS
	.8086
	ret
  endif
 endif
swapscreen endp

elseif VXCMD
v_cmd proc
	cmp ah, 'v'
	jnz @F
	or al, TOLOWER
	@dprintf "v_cmd: ax=%X", ax
	cmp al, 'c'
	jz vc_cmd
	cmp al, 'l'
	jz vl_cmd
	cmp al, 't'
	jz vt_cmd
@@:
	jmp cmd_error
v_cmd endp
endif

if ALTVID

;--- switch to debugger/debuggee screen with option /2.
;--- since DOS/BIOS is used for output, there's no guarantee that it will work.
;--- this code assumes that page 0 is set. 

setscreen proc
	ret	;will be patched to "push ds" if "/2" cmdline switch and second adapter exists
	mov dx, [oldcrtp]
	mov bx, [oldcols]
	mov ax, [oldmr]
	mov cx, 0040h         ; 0040h is supposed to work in both rm/pm
	mov ds, cx
	mov cx, cs:[oldcsrpos]
	and byte ptr ds:[10h], not 30h
	cmp dl, 0b4h
	jnz @F
	or  byte ptr ds:[10h], 30h
@@:
	xchg bx,ds:[4Ah]
	xchg cx,ds:[50h]
	xchg dx,ds:[63h]
	xchg al,ds:[49h]
	xchg ah,ds:[84h]
	pop ds
	mov [oldcrtp], dx
	mov [oldcsrpos], cx
	mov [oldcols], bx
	mov [oldmr], ax
	ret
setscreen endp

endif

if INT2324

;--- this is low-level, called on entry into the debugger.
;--- the debuggee's registers have already been saved here.
;--- 1. save IVT vectors 23/24 ("debuggee's") to [run2324]
;--- 2. restore IVT vectors 23/24 ("debugger's") from PSP:[CCIV]
;--- DS, ES = DGROUP
;--- Int 21h should not be used here!

getint2324 proc
	mov di,offset run2324
 if ?DPMI
	call ispm_dbg
	jnz getint2324pm
 endif

	xor si,si
	mov ds,si
	mov si,23h*4
	push si
	movsw		;save interrupt vector 23h
	movsw
	movsw		;save interrupt vector 24h
	movsw
	pop di
 if FMTEXE
	mov ds,cs:[pspdbg]
 else
	push es
	pop ds
 endif
	xor si,si
	mov es, si
	mov si,PSPS.CCIV	;move from debugger's PSP to IVT
	movsw
	movsw
	movsw
	movsw
 if FMTEXE
	push ss
	pop ds
 endif
	push ds
	pop es
	ret
 if ?DPMI
getint2324pm:
	mov bx, 0223h
	mov si, offset dbg2324
@@:
	mov ax, 204h
	int 31h
	sizeprf		;mov [di+0],edx
	mov [di+0], dx
	mov [di+4], cx

	sizeprf		;xor edx, edx
	xor dx, dx
	lodsw
	mov dx, ax
	mov cx, cs
	mov ax, 205h
	int 31h

	add di, 6
	inc bl
	dec bh
	jnz @B
	ret
	.8086

 endif

getint2324 endp

endif

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

;--- for protected-mode, this whole procedure with prepare-do-undo is
;--- pretty useless - hence all three procs are dummies while in pm. 
;--- OTOH, it might be useful, to adjust the DI cmd in protected-mode
;--- to return the debuggee's vectors for 23h/24h.

;   PREPHACK - Set up for interrupt vector substitution.
;   save current value of Int 23/24 (debugger's) to sav2324
;   Entry   es = cs

prephack proc
if INT2324
	cmp [hakstat],0
	jnz @F					;if hack status error
	push di
	mov di,offset sav2324	;debugger's Int2324
	call store2324			;copy IVT 23/24 to di (real-mode only)
	pop di
	ret
@@:                         ;this is actually a programming error!
	push ax
	push dx
	mov dx,offset ph_msg	;'error in sequence of calls to hack'
	call int21ah9			;print string
	pop dx
	pop ax
endif
	ret

prephack endp

if INT2324

CONST segment
ph_msg	db 'Error in sequence of calls to hack.',CR,LF,'$'
CONST ends

;--- get current int 23/24, store them at ES:DI
;--- DI is either sav2324 (debugger's) or run2324 (debuggee's)

store2324 proc
 if ?DPMI
	call ispm_dbg
	jnz _ret		;nothing to do if in PM
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
_ret:
	ret
store2324 endp

endif

;   DOHACK - set debuggee's int 23/24
;   Entry   ds = dgroup

;   DOHACK/UNHACK: It's OK to do either of these twice in a row.
;   In particular, the 's' command may do unhack twice in a row.

dohack proc
if INT2324
	mov [hakstat],1
 if ?DPMI
	call ispm_dbg	; v2.0: dohack is dummy in protected-mode
	jnz _ret
 endif
	push si
	mov si,offset run2324	;debuggee's interrupt vectors
	jmp hak1

endif

;--- UNHACK - set debugger's int 23/24
;--- Entry   ds = dgroup

unhack::
if INT2324
	mov [hakstat],0
 if ?DPMI
	call ispm_dbg
	jnz _ret		; v2.0: unhack is dummy now
 endif
	push si
	mov si,offset sav2324	;debugger's interrupt vectors
hak1:
	push di
	push es
	xor di,di
	mov es, di
	mov di,4*23h
	movsw
	movsw
	movsw
	movsw
	pop es
	pop di
	pop si
_ret:
endif
	ret

dohack endp

;--- InDos: return NZ if DOS cannot be used

InDos:
if ( BOOTDBG or RING0 )
	push ax
	or al,-1
	pop ax
else
	push ds
	push si
 if ?DPMI
	call ispm_dbg
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
endif
	ret

stdoutal:
	push cx
	push dx
	push ax
	mov cx,1
if FLATSS
	mov [bChar], al
	mov dx, offset bChar
else
	mov dx,sp
endif
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
	call stdout ;write prompt (string DX, size CX)
if REDIRECT
	test [fStdin], AT_DEVICE
	jnz gl5		;jmp if tty input

	mov [lastcmd], offset dmycmd

;   This part reads the input line from a file (in the case of
;   'debug < file').  It is necessary to do this by hand because DOS
;   function 0ah does not handle EOF correctly otherwise.  This is
;   especially important for debug because it traps Control-C.

	call fillbuf
	jc q_cmd
	mov [bufnext], si
	mov cx,[bufend]
	mov dx,offset line_in + 2
	sub cx,dx
	call stdout	;print out the received line
	jmp gl6		;done
gl5:
endif

;--- input a line if stdin is a device (tty)
	mov dx,offset line_in
	call InDos
	jnz rawinput
ife RING0
	mov ah,0ah		;buffered keyboard input
	call doscall
endif
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
if RING0
	.386
	call cs:[int16vec]
	.8086
else
	int 16h
endif
	cmp al,0
	jz rawnext
	cmp al,0E0h
	jz rawnext
	cmp al,08h
	jz del_key
	cmp al,7Fh
	jz del_key
	stosb
if RING0
	cmp al, 20h
	jnc @F
	cmp al, 0Dh
	jz @F
	cmp al, 08h
	jz @F
	push ax
	mov al, '^'
	call stdoutal
	pop ax
	or al, 40h
@@:
endif
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

if REDIRECT

;   FILLBUF - Fill input buffer, read from a file.
;   called by getline & within 'e' cmd in interactive mode.
;   Exit    SI  Next readable byte
;       Carry flag is set if and only if there is an error (e.g., eof)
;   Uses    None.

fillbuf proc
	push ax
	push bx
	push cx
	push dx
	mov si, offset line_in+2
	push si

;--- read input bytewise until LF.
;--- note that debug expects CR/LF pairs -
;--- lines with just LF as EOL marker won't do.

@@:
	mov dx, si
	cmp dx, offset line_in+LINE_IN_LEN ; "line too long" is treated as EOF
	jz fb1
	mov cx, 1
	xor bx, bx
	mov ah, 3fh	; read file
	call doscall
	jc fb1
	and ax,ax
	jz fb1		; if eof
	mov al,[si]
	inc si
	cmp al,LF
	jnz @B
	dec si      ; the LF itself should NOT be handled by the cmds.
	jmp fb2
fb1:
	stc
fb2:
	mov [bufend], si
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret
fillbuf endp

endif

;   PARSECM - Parse arguments for C and M commands.
;   Entry   AL          First nonwhite character of parameters
;           SI          Address of the character after that
;   Exit    DS:(E)SI    Address from first parameter
;           ES:(E)DI    Address from second parameter
;           (E)CX       Length of address range minus one
;   m cmd in real-mode expects dst segm:ofs in BX:DX

parsecm proc
	call prephack
	xor cx,cx
	call getrangeDS	;get address range into bx:(e)dx bx:(e)cx
	push bx			;save segment first address ( src for m cmd )
if ?PM
	call IsOfs32
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
if RING0 and V86M
;--- there's just one scratch selector
;--- but m & c may require another one for the addr argument behind the range.
;--- so if the range's segment is scratchsel,
;--- change it to FLAT
	test byte ptr [regs.rFL+2], 2	;v86-mode?
	jz @F
	cmp bx, [scratchsel]
	jnz @F
	pop bx
	push [wFlat]
	mov [bAddr32], 1
	.386
	movzx ebx, [scratchv86]
	shl ebx, 4
	movzx edx, dx
	movzx ecx, cx
	add edx, ebx
	push edx
	push ecx
	jmp pc_01
@@:
endif
	push dx
	push cx
pc_01:
	call skipcomm0

;--- get the second ( destination ) address

	@movs bx,[regs.rDS]	; DS = default for "destination"
if ?PM
	call IsOfs32
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
	mov es, bx
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
	mov es, bx
	pop si
	pop ds
	ret
parsecm endp

errorj7:
	jmp cmd_error

if LCMD or WCMD

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
;       [usepacket] == 0:
;       AL  Drive number
;       CX  Number of sectors to read
;       DX  Beginning logical sector number
;       DS:BX   Transfer address
;
;       [usepacket] != 0:
;       AL  Drive number
;       BX  Offset of packet
;       CX  0FFFFh

parselw proc
	mov bx,[regs.rCS]	;default segment
	mov dx,100h		;default offset
	cmp al,CR
	je plw2			;if no arguments
;--- v2.0: added IsWriteableBX since getaddr will no longer translate BX
;--- to a writeable selector.
	call getaddr	;get buffer address into bx:(e)dx
if ?PM
	call IsWriteableBX
endif
	call skipcomm0
	cmp al,CR
	je plw2			;if only one argument
	push bx			;save segment
	push dx			;save offset
	mov bx,80h		;max number of sectors to read
	neg dx
	jz @F			;if address is zero
	mov cl,9
	shr dx,cl		;max number of sectors which can be read
	mov di,dx
@@:
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
	call ispm_dbg
	jz @F
 if ?DPMI
	test [dpmi32],1
	jz @F
 endif
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

endif

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

	mov bx,[regs.rCS]	;default segment
	mov [eqflag],al
	cmp al,'='
	jne peq1		;if no '=' operand
	call skipwhite
if ?DPMI
	sizeprf			;xor edx, edx
	xor dx,dx
endif
if RING0 and V86M
	@movs bx,[regs.rCS]
endif
	call getaddr	;get address into bx:(e)dx
	sizeprfX		;mov [eqladdr+0],edx
	mov [eqladdr+0],dx
if RING0 and V86M
	test byte ptr [regs.rFL+2],2
	jz @F
	mov bx,[scratchv86]	; don't store the scratch selector in eqladdr - must be a segment value in v86
@@:
endif
peq1:
	mov [eqladdr+4],bx
	ret
parseql endp

;   SETEQ - Copy the = arguments to their place, if appropriate. This
;   is not done immediately, because the g/p/t cmds may have syntax errors.
;   Uses AX.

seteq proc
	cmp [eqflag],'='	;'=' argument given?
	jnz @F
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
;--- in: BX=segment/selector
;--- out: offset in (E)DX

getofsforbx proc
if ?PM
	call getseglimit
	jz gofbx_2
	mov [bAddr32],1
	push bx
	call getdword
	push bx
	push dx
	.386
	pop edx
	pop bx
	ret
	.8086
gofbx_2:
endif
	sizeprfX		; v2.0: xor edx,edx
	xor dx, dx
	call getword
;	@dprintf "getofsforbx: edx=%lX", edx
	ret
getofsforbx endp

errorj10:
	jmp cmd_error

;--- a range is entered with the L/ength argument
;--- get a valid length for segment in BX
;--- L=0 means 64 kB (at least in 16bit mode)
;--- return with NC if value ok.

getlenforbx proc
if ?PM
	call getseglimit
	jz glfbx_1
	push dx
	push bx
	call getdword
	push bx
	push dx
	.386
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

;--- get range with default segment DS

getrangeDS proc
	@movs bx,[regs.rDS]
;--- fall thru!
getrangeDS endp

;   getrange - Get address range from input line.
;    a range consists of:
;       1. a start address: [segment:]start-offset
;       2. an end-offset or a 'L' followed by a length.
;   Entry   AL  First character of range
;       SI  Address of next character
;       BX  Default segment to use
;       (E)CX  Default length to use (or 0 if not allowed)
;   Exit    AL  First character beyond range
;       SI  Address of the character after that
;       BX:(E)DX    First address in range
;       BX:(E)CX    Last address in range
;   Uses    AH

getrange proc		; used by c, d, m, s, u cmds
	push cx
	call getaddr	;get address into bx:(e)dx (sets bAddr32 if ?PM)
	push si
	call skipcomm0
	cmp al,' '
	ja gr2
	pop si			;restore si and cx
	pop cx
	jcxz errorj10	;if a range is mandatory
if ?PM
	call IsOfs32	;can be NZ only on a 80386+
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

;   getaddr - Get address from input line.
;   Entry   AL  First character of address
;       SI  Address of next character
;       BX  Default segment to use
;   Exit    AL  First character beyond address
;       SI  Address of the character after that
;       BX:(E)DX    Address found
;   Uses    AH,CX

getaddr proc
if ?PM
	mov [bAddr32],0
 if ?DPMI
	cmp al, '$'			; a real-mode segment?
	jnz @F
	lodsb
	call ispm_dbg
	jz @F
	call getword
	cmp al,':'
	jnz errorj2
	mov bx,dx
	mov ax,2
	int 31h
	mov bx,ax
	mov dx,ax
	jc errorj2
	jmp ga3
@@:
 elseif RING0
	cmp al, '%'			; a linear address?
	jnz @F
	mov bx, cs:[wFlat]
	jmp ga3
@@:
;--- hack for a/u cmds: allow to enter a real-mode address.
;--- since DebugR[L] cannot handle v86-mode exceptions,
;--- this hack allows to at least (dis)assemble real-mode code parts.
	cmp al, '$'
	jnz normseg
  if V86M
;--- in v86-mode, '$' is unknown
	test byte ptr [regs.rFL+2],2	; syntax NOT valid in v86-mode
	jnz errorj2
  else
	cmp [lastcmd], offset u_cmd	; u cmd?
	jz @F
	cmp [errret], offset cmdloop; a cmd?
	jz normseg
@@:
  endif
	lodsb
	call getword
	cmp al,':'
	jnz errorj2
	call setscratchsel	; set BX to scratchsel
	jmp ga3
normseg:
  if V86M
	cmp al,'#'			; segment part is a selector?
	jnz @F
	test byte ptr [regs.rFL+2],2	; syntax valid only in v86-mode
	jz errorj2
	lodsb
	call getword
	@dprintf "getaddr: # detected, selector=%X ax=%X", dx, ax
	cmp al,':'
	jnz errorj2
	mov bx, dx
	jmp ga3
@@:
  endif
 endif
endif
	call getofsforbx
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
	@movs bx,dx	;mov segment into BX
ga3:
	call skipwhite	;skip to next word
if ?PM
	mov [bAddr32],0	;v2.0: init bAddr32, will be set if limit > 64k
endif
	call getofsforbx
if ?PM
	@dprintf "getaddr: bx:edx=%X:%lX, bAddr32=%X", bx, edx, word ptr [bAddr32]
endif
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
nextchar:
	lodsb
	call getnyb
	jc done
	test bh,0f0h
	jnz errorj6		;if too big
	mov cx,4
@@:
	shl dx,1		;double shift left
	rcl bx,1
	loop @B
	or dl,al
	jmp nextchar
done:
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

;--- disassembler code

	include <DISASM.INC>

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

;--- DUMPREGS - Dump registers and print 1 disassembled line at CS:EIP.

dumpregs proc
;	@dprintf "dumpregs"
	mov si,offset regnames
	mov di,offset line_out
	mov cx, 5
	mov bx,offset regfmt16
	test [rmode],RM_386REGS
	jz @F
	mov bx,offset regfmt32
@@:
nextgrp:
	push cx
	mov cl, [bx+0]
	and cx,7fh
	push bx
	call word ptr [bx+1]
	pop bx
	test byte ptr [bx],80h
	jz @F
	call putsline
	mov di, dx
@@:
	add bx, sizeof FMTITEM
	pop cx
	loop nextgrp

if RING0
 if DISPPL0STK
	call dmpr0ssesp
	call putsline
 endif
endif

;--- display 1 disassembled line at CS:[E]IP

	mov si, offset regs.rIP
	mov di, offset u_addr
	movsw
	movsw
	@movs ax,[regs.rCS]	; problem: if V86M and v86-mode, this will be the scratch sel
	stosw
	mov al, DIS_F_REPT or DIS_F_SHOW
	call disasm

;--- 'r' resets default setting for 'u' to CS:[E]IP

	sizeprf			; mov eax, [regs.rIP]
	mov ax,[regs.rIP]
	sizeprf			; mov [u_addr], eax
	mov [u_addr],ax
	ret

FMTITEM struct
bNum db ?
wAdr dw ?
FMTITEM ends

;--- 16bit: 8 std regs, NL, skip 2, 4 seg regs, IP, flags
;--- 32bit: 6 std regs, NL, 2 std regs+IP+FL, flags, NL, 6 seg regs

CONST segment
regfmt16 FMTITEM <88h,dmpr1w>,<2,skipregs>,<4,dmpr1w>,<1,dmpip>,<80h,dmpflags>
regfmt32 label FMTITEM
	FMTITEM <86h,dmpr1d>
	FMTITEM <4,dmpr1d>
	FMTITEM <80h,dmpflags>
	FMTITEM <0,prepsr>
	FMTITEM <86h,dmpr1w>
CONST ends

skipregs:
	rep lodsw
	ret
prepsr:
	mov si, offset regnames+10*2	; just position SI to segment regs
	ret

dmpip:
	mov si, offset regnames+8*2
;--- fall thru

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

if RING0
 if DISPPL0STK

CONST segment
pl0esp db "[PL0 SS:ESP="
CONST ends

dmpr0ssesp:
	.386
 if V86M
	test byte ptr [regs.rFL+2],2
	jnz isv86
 endif
	lar ax, [regs.rCS]
	and ah,60h
	jz @F
isv86:
	mov si, offset pl0esp
	mov cl, sizeof pl0esp
	rep movsb
	mov ax, [regs.r0SS]
	call hexword
	mov al,':'
	stosb
	mov eax, [regs.r0Esp]
	call hexdword
	mov al,']'
	stosb
@@:
	ret
 endif
endif


dumpregs endp

if USEFP2STR
 if RING0
	.386
 endif
	include <FPTOSTR.INC>
endif

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
;--- Note: value of CR0 bits 1=MP,2=EM,3=TS may have unwanted effects:
;--- 1. if MP=1 and TS=1, an fwait will raise exc 07
;--- 2. if EM=1, any fpu opcode will raise exc 07.

dumpregsFPU proc
if RING0
	.386
	mov dx, offset fpuemerr
	mov eax, cr0
	test al, 4		;CR0.EM=1?
	jnz int21ah9
	.8086
endif
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
if ?DPMI
	call ispm_dbg
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
if ?DPMI
	call ispm_dbg
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
	call hexnyb	;convert to hex digit and print
fppm:
	sizeprfX	;mov eax,edx
	mov ax,dx
if ?DPMI
	call ispm_dbg
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
	push si
	push cx
	mov ax,"TS"
	stosw
	mov al,cl
	mov ah,'='
	stosw

	mov ax,bp
	ror bp,1	;remain 8086 compatible here!
	ror bp,1
	and al,3	;00=valid,01=zero,02=NaN,03=Empty
	jz isvalid
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
	jmp regoutdone
isvalid:
if USEFP2STR
	call FloatToStr
else
	mov cl, 5
@@:
	lodsw
	push ax
	loop @B
	pop ax
	call hexword
	mov al,'.'
	stosb
	mov cl,4
@@:
	pop ax
	call hexword
	loop @B
endif
regoutdone:
	mov al,' '
@@:
	stosb
	cmp di, offset line_out+26
	jb @B
	pop ax
	push ax
	test al,1
	jz @F
	mov ax, 0A0Dh
	stosw
@@:
	call puts
	pop cx
	pop si
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
	jnz @F
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
;--- modifies SI, DI, AL

copystring proc
	lodsb
@@:
	stosb
	lodsb
	cmp al,0
	jne @B
	ret
copystring endp

;--- display 16/32-bit offset in E/AX

DispOfs proc
if ?PM
	test [bCSAttr], CS32
	jnz hexdword
endif
	jmp hexword
DispOfs endp

;   HEXDWORD - Print hex dword (in EAX).
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
if RING0
	.386
	shr al, 4
else
	push cx
	mov cl,4
	shr al,cl
endif
	call hexnyb
ife RING0
	pop cx
endif
	pop ax

hexnyb:
	and al,0fh
	add al,90h		;these four instructions change to ascii hex
	daa
	adc al,40h
	daa
	stosb
	ret

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
if RING0
	push bx
else
	call InDos
	push bx
	jnz @F
	mov bx,1		;standard output
	mov ah,40h		;write to file
	call doscall
	pop bx
	ret
@@:					;use BIOS for output
endif
	jcxz nooutput
	push si
	mov si,dx
nextchar:
	lodsb
	mov bh,[vpage]	;v2.0: use the current video page
	cmp al, TAB		;v2.0: handle tabs
	jz istab
	mov ah,0Eh
if RING0
	.386
	call [int10vec]
	.8086
else
	int 10h
endif
donetab:
	loop nextchar
	pop si
nooutput:
	pop bx
	ret

;--- interpret TAB in BIOS output

istab:
	push cx
	push dx
	mov ah, 3
if RING0
	.386
	call [int10vec]
	.8086
else
	int 10h
endif
	mov cl, dl
	and cx, 7	; 0  1  2  3  4  5  6  7
	sub cl, 8	;-8 -7 -6 -5 -4 -3 -2 -1
	neg cl		; 8  7  6  5  4  3  2  1
@@:
	mov ax, 0E20h
if RING0
	.386
	call [int10vec]
	.8086
else
	int 10h
endif
	loop @B
	pop dx
	pop cx
	jmp donetab

stdout endp

ifdef _DEBUG
	pushcontext cpu
	.386
 if RING0 and V86M
	include <DPRINTFR.INC>
 else
	include <DPRINTF.INC>
 endif
	popcontext cpu
endif

if LCMDFILE

createdummytask proc

	@dprintf "createdummytask"
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

	inc byte ptr [regs.rIP+1]	;set IP=100h

	call setespefl	; set regs.rSP/rFL

	push bx
	mov di,offset regs.rDS	;init regs.rDS,regs.rES
	stosw
	stosw
	mov di,offset regs.rSS	;init regs.rSS,regs.rCS
	stosw
	stosw
	call setup_adu	; setup default for a/d/u cmds
	xchg ax, bx		; bx = CS; bx:dx = where to load program
	mov es, bx
	pop ax			;get size of memory block
	mov dx,ax
	add dx,bx
	mov es:[PSPS.ALASAP],dx
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
	mov si,es:[PSPS.ALASAP]
	clc				;works around OS/2 bug
	int 21h
	mov word ptr es:[PSPS.TPIV+0],offset intr22
	mov word ptr es:[PSPS.TPIV+2],cs
	cmp [bInit],0
	jnz @F
	inc [bInit]
	mov byte ptr es:[100h],0C3h	;place opcode for 'RET' at CS:IP
@@:
	mov [pspdbe],es

;--- set owner and name to newly created PSP
	mov ax,es
	dec ax
	mov es, ax
	inc ax
	mov es:[0001],ax
	mov byte ptr es:[0008],0
	push ds			;restore ES
	pop es

	call getint2324	; v2.0 init [run2324]

	call setpspdbg	;set debugger's PSP
ct_done:
	ret

createdummytask endp

endif

if ?DPMI

;--- hook int 2Fh if a DPMI host is found
;--- for Win3x/9x and DosEmu host
;--- int 2Fh, ax=1687h is not hooked, however
;--- because it doesn't work. Debugging
;--- in protected-mode still may work, but
;--- the initial-switch to PM must be single-stepped
;--- modifies AX, BX, CX, DX, DI

hook2f proc
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
	@dprintf "hook2f: new int2F vector=%X:%X", ds, dx
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

if RING0
uninstall proc

	.386
	push ds
	push es
	mov ds, cs:[wDgroup]
	sub esp, 6
	sidt [esp]
	pop dx
	pop ebx
	mov es, [wFlat]
	mov cx, NUMINTS
	mov si, offset inttab
	mov di, offset intsave
@@:
	movzx edx, byte ptr [si]
	shl edx, 3
	mov eax, [di]
	mov es:[ebx+edx+0], ax
	shr eax, 16
	mov es:[ebx+edx+6], ax
	mov ax, [di+4]
	mov es:[ebx+edx+2], ax
	add si, sizeof INTITEM
	add di, sizeof INTVEC
	loop @B
	pop es
	pop ds
	retd
uninstall endp
endif

endoftext16 label byte

_TEXT ends

_DATA segment

;--- I/O buffers.  (End of permanently resident part.)

line_in		db 255,0,CR				;length = 257
line_out	equ line_in+LINE_IN_LEN+1;length = 1 + 263
real_end	equ line_in+LINE_IN_LEN+1+264

if USEHWBP

HWBP_ACTIVE equ 1
HWBP_V86    equ 2

 if RING0
bHWBPflgs db HWBP_ACTIVE
 else
bHWBPflgs db 0
 endif
endif

_DATA ends

_ITEXT segment

if RING0
	dd 0DEADBEEFh	; marker for start of _ITEXT, don't remove!
endif

;--- initcont is located at the start of _ITEXT because either
;--- a word is written into this segment ( the "mov [bx], ..." below )
;--- or SP has to be adjusted before memory is freed.
;--- ax,bx=top of memory

initcont:

if DRIVER or RING0 or BOOTDBG
	sub bx, 2
	mov [bx], offset ue_int	; make debug display "unexpected interrupt"
 if FLATSS
	.386
	movzx ebx, bx
	add ebx, [dwBase]
	mov [run_sp], ebx
 else
	mov [run_sp], bx
 endif
 if BOOTDBG
	mov cx, ax
	mov es, [wDgroup]		; copy debugger beyond conv. memory
	xor di, di
	xor si, si
	rep movsb
	pop es
	pop ds
	retf
 elseif RING0
	.386
	lss esp, [regs.r0SSEsp]		; switch stack back
	pushf
	and byte ptr [esp+1], 0BFh	; reset NT flag
	popf
	pop es
	pop ds
	retd
 else
	ret
 endif
else
	mov [bInDbg], 1	; v2.01: variable is set only when debug is entered via interrupt
 if FMTEXE
	mov es, [pspdbg]
	add bx, 100h
 else
	push ds
	pop es
 endif
	mov cl, 4
	shr bx, cl
	mov sp, ax
	mov ah, 4Ah
	int 21h			;free rest of DOS memory
	mov byte ptr [line_out-1],'0'	;initialize line_out?
	cmp [fileext],0
	jz @F
 if FMTEXE
	push ds		; loadfile expects ds=es=dgroup
	pop es
 endif
	call loadfile
@@:
if ALTVID
	call setscreen
endif
	jmp cmdloop
endif

;---------------------------------------
;--- Debug initialization code.
;---------------------------------------


ife (DRIVER or BOOTDBG or RING0)


imsg1 db DBGNAME,' version ',@CatStr(!',%VERSION,!'),CR,LF,LF
	db 'Usage: ', DBGNAME, ' '
 if ALTVID or USEHWBP
	db '[options] '
 endif
	db '[[drive:][path]progname [arglist]]',CR,LF
 if ALTVID or USEHWBP
	db ' options:',CR,LF
  if ALTVID
	db '  /2: use alternate video adapter for output if available',CR,LF
  endif
  if USEHWBP
	db '  /s: hardware breakpoints switched off',CR,LF
   ife RING0
	db '  /v: allow hardware breakpoints in v86 mode',CR,LF
   endif
  endif
 endif
	db ' progname: (executable) file to debug or examine',CR,LF
	db ' arglist: parameters given to program',CR,LF,LF
	db 'For a list of debugging commands, '
	db 'run ', DBGNAME, ' and type ? at the prompt.',CR,LF,'$'

imsg2	db 'Invalid switch - '
imsg2a	db 'x',CR,LF,'$'

endif

if ?DPMI
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
	db DBGNAME2, "g v",@CatStr(!',%VERSION,!')," is a device driver variant of Debug/X.",13,10
	db "It's supposed to be loaded in CONFIG.SYS via 'DEVICE=",DBGNAME2,"g.exe'.",13,10
	db "$"

endif

;--- initialization.
;--- BOOTDBG: no cmdline
;--- RING0: ESI -> cmdline ( linear address )
;--- DRIVER: cmdline in init_req.cmdline
;--- anything else: PSP:80h
;--- register (E)BP must be preserved!

if FMTEXE
start:
endif

initcode proc
	cld
if RING0

;--- in:
;--- loword(ax): dgroup selector
;--- hiword(ax): scratch selector
;---  cx: flat data selector
;---  bp: size dgroup ( also, value of SP during init )
;--- ebx: offset output routine (int 10h)
;--- edx: offset input routine (int 16h)
;--- es:edi=IDT

 if LMODE
CS64SEL equ 8	; to be fixed: 64-bit code selector for DebugRL is 8 (Dos32cm)
 endif

	push ds
	push es
	mov ds, ax
	mov [wFlat], cx
	shr eax, 16
	mov [scratchsel], ax
 if LMODE
	mov [jmpv161s], cs
	mov [jmpv162s], cs
 endif
	.386
 ife LMODE
	@checkss	; ensure hiword esp isn't trashed
 endif
	mov ax, [esp+2*2+4]	; get caller's CS
	mov dword ptr [int10vec+0], ebx
	mov word ptr [int10vec+4], ax
	mov dword ptr [int16vec+0], edx
	mov word ptr [int16vec+4], ax

;--- set ring0 stack so output is possible during init
	mov [regs.r0Esp], esp
	mov [regs.r0SS], ss

;--- invalidate a & d segment part ( will then be reinitialized )
	xor ax, ax
	mov [a_addr+4], ax
	mov [d_addr+4], ax

;--- set stack

 if FLATSS
	sub esp, 6
	sgdt [esp]
	pop ax
	pop edx
	movzx ebp, bp
	mov ebx, cs
	add ebx, edx
	push ds
	mov ds, cx
	mov al, [ebx+4]
	mov ah, [ebx+7]
	shl eax, 16
	mov ax, [ebx+2]
	pop ds
	add ebp, eax
	mov ss, cx
	mov esp, ebp
	mov [dwBase], eax
  if LMODE

;--- get [dwBase64] - linear address of _TEXT64
;--- depends on how _TEXT64 is aligned!
;--- currently align 16

TEXT64ALIGN equ 16

	mov edx, offset endoftext16
	add dx, TEXT64ALIGN-1
	and dx, not TEXT64ALIGN-1
	add eax, edx
	mov [dwBase64], eax
	@dprintf "initcode: dwBase64=%lX, start TEXT64=%X", eax, dx
  endif

 else
	mov ax, ds
	mov ss, ax
	mov sp, bp
 endif
	push es
	push edi	; addr IDT now at [e/bp-6]
	@dprintf "initcode: cs=%X, ds=%X, flat=%X, ebp=%lX, es:edi=%X:%lX, esi=%lX", cs, ds, cx, ebp, es, edi, esi

	mov ax, ds
	mov es, ax
	mov [machine], 3

elseif DRIVER
	mov ax, cs
elseif BOOTDBG
	push ds
	push es
	push cs
	pop ds
	mov ax, cs
else
	mov ax, cs
 if FMTEXE
	mov ds, ax
	mov [pspdbg], es
	mov dx, ss
	sub dx, ax
	mov cl, 4
	shl dx, cl
	mov ss, ax
	add sp, dx
	mov ax, es
 endif
	mov word ptr [execblk.cmdtail+2],ax
	mov word ptr [execblk.fcb1+2],ax
	mov word ptr [execblk.fcb2+2],ax
 if FMTEXE
	mov ax, ds
 endif
endif
	mov [wDgroup], ax	; this will set alias [pspdbg] if FMTEXE==0

;--- Check for console input vs. input from a file or other device.

if REDIRECT
	mov ax,4400h	;IOCTL--get info
	xor bx,bx       ;stdin
	int 21h
	jc @F
	mov [fStdin],dl
@@:
	mov ax,4400h	;IOCTL--get info
	mov bx,1        ;stdout
	int 21h
	jc @F
	mov [fStdout],dl
@@:
endif

ife RING0

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

	inc [machine]

;   It is now safe to use 32-bit opcode/operands.

 if USEHWBP
	inc [bHWBPflgs]	; bit 0=1 (HWBP_ACTIVE)
 endif

endif

	.386

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

;	inc [machine]	;it's a 486
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

ife RING0
	.8086		 	;back to 1980s technology
endif

;   Next determine the type of FPU in a system and set the mach_87
;   variable with the appropriate value.

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
ife RING0
	mov bp, sp
BPOFS equ <bp-2>
else
 if FLATSS
BPOFS equ <ebp-8>		; for RING0, there're already 6 bytes used
 else
BPOFS equ <bp-8>		; for RING0, there're already 6 bytes used
 endif
endif
	mov al,[machine]
	mov [mach_87],al	;by default, set mach_87 to machine
	inc [has_87]
	cmp al,5			;a Pentium or above always will have a FPU
	jnc init7
	dec [has_87]

	fninit				;reset FP status word
	mov ax,5a5ah		;init with non-zero value
	push ax
	fnstsw [BPOFS]		;save FP status word
	pop ax				;check FP status word
	cmp al,0
	jne init7			;if no FPU present

	push ax
	fnstcw [BPOFS]		;save FP control word
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
if RING0
	fstsw ax
else
	push ax
	fstsw [BPOFS]	;look at status from FCOMPP
	pop ax
endif
	sahf
	jnz init7		;if they are different, then it's a 387
	dec [mach_87]	;otherwise, it's a 287
init7:

;--- remove size and addr prefixes if cpu is < 80386

;	mov [machine], 2; activate to test non-386 code branches

ife RING0
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
endif

;--- Check DOS version

ife (BOOTDBG or RING0)
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
	cmp bx,3205h	; NTVDM?
	jnz @F
  if USEHWBP
	mov bHWBPflgs,0	; no hwbp for NTVDM
  endif
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
init2:
endif

;--- Interpret switches and erase them from the command line.

ife BOOTDBG

 ife RING0
	mov ax,3700h		;get switch character in DL
	int 21h
	mov [swchar],dl
	cmp dl,'/'
	jne @F
	mov [swch1],dl
@@:
 endif

 if RING0
	mov es, [wFlat] 
 elseif DRIVER
	les si, cs:[request_ptr]	; load address of request header
	les si, es:[si].init_req.cmdline
@@:
	lodsb es:[si]		; skip program name
	cmp al,13
	jz @F
	cmp al,' '
	jnz @B
@@:
 else
	mov si,PSPS.DTA+1
  if FMTEXE
I_SRC equ <es:[si]>
  else
I_SRC equ <>
  endif
 endif
contparse:
@@:
 if RING0
	.386
	lodsb es:[esi]
	.8086
 elseif DRIVER
	lodsb es:[si]
 else
	lodsb I_SRC
 endif
	cmp al,' '
	je @B
	cmp al,TAB
	je @B

;--- Process the /? switch (or the [swchar]? switch).
;--- If swchar != / and /? occurs, make sure nothing follows.

	cmp al,[swchar]
	je @F			;if switch character
	cmp al,'/'
	jne doneoptions	;if not the help switch
@@:
 if RING0
	.386
	lodsb es:[esi]
	.8086
 elseif DRIVER
	lodsb es:[si]
 else
	lodsb I_SRC
	cmp al,'?'
	jne @F
;helpexit:			; Print help message and exit
	mov dx,offset imsg1	;command-line help message
;	call int21ah9	;v2.0: int21ah9 cannot be used ( pInDOS not yet set )
	mov ah,9
	int 21h
	int 20h			;done
@@:
 endif

 if ALTVID
	cmp al,'2'
	jnz noopt2
	mov ax, 1A00h
  if RING0
	.386
	call [int10vec]
  else
	int 10h
  endif
	cmp al, 1Ah
	jnz noaltvid
	cmp bh, 0
	jz noaltvid
	mov byte ptr [setscreen], 1Eh	;"push ds"
	push ds
	mov ax, 40h		; segment value 40h even works in Jemm ring 0
	mov ds, ax
	mov dx, ds:[63h]
	pop ds
	xor dl, 60h
	mov [oldcrtp], dx
	mov al, 7
	cmp dl, 0B4h
	jz @F
	mov al, 3
@@:
	mov [oldmode], al

;--- to initially get the cursor pos of the alt screen, read the CRT.
;--- this code assumes that page 0 is active ( offset == 0 );
;--- could be fixed by reading CRT 0Ch/0Dh.

	mov al, 0eh
	out dx, al
	inc dx
	in al, dx
	mov ah, al
	dec dx
	mov al, 0fh
	out dx, al
	inc dx
	in al, dx
	mov bl, 80
	div bl
	xchg al, ah
	mov [oldcsrpos], ax
noaltvid:
	jmp contparse
noopt2:
 endif

;--- ||| Other switches may go here.

 if USEHWBP
	cmp al,'s'		; don't use debug registers in real-mode/protected-mode?
	jnz @F
	mov [bHWBPflgs],0
	jmp contparse
@@:
  ife RING0
	cmp al,'v'		; use debug registers in v86-mode?
	jnz @F
	or [bHWBPflgs],HWBP_V86
	jmp contparse
@@:
  endif
 endif

 if MCLOPT and ( CATCHINT0C or CATCHINT0D )
	cmp al, 'm'		; /m cmdline option?
	jnz @F
	mov [bMPicB], 20h
	jmp contparse
@@: 
 endif

 if RING0 and CATCHINT41
	cmp al, 'i'		; /i cmdline option?
	jnz noopti
	mov [itab41.bInt], -1; deactivate Int 41h hook   
	jmp contparse
noopti:
 endif

 if RING0 and V86M
	cmp al, 'b'		; set alternate v86-monitor bp?
	jnz nooptb
	mov [bV86Bp], 63h; assume v86 monitor bp is ARPL
	jmp contparse
nooptb:
 endif

 ife (DRIVER or RING0)	; those versions ignore invalid cmdline args
	mov [imsg2a],al
	mov dx,offset imsg2	;Invalid switch
;	call int21ah9	;v2.0: int21ah9 cannot be used ( pInDOS not yet set )
	mov ah,9
	int 21h
	mov ax,4c01h	;Quit and return error status
	int 21h
 endif

doneoptions:

 ife (DRIVER or RING0)
	dec si
  if FMTEXE
;--- if format is .EXE, the cmdline must be copied to DGROUP for n cmd.
	sub sp, 80h
	mov di, sp
	mov cx, es
	push ds
	pop es
	push ds
	mov ds, cx
	mov cx, 40h
	rep movsw
	pop ds
	mov si, sp
  endif
	lodsb
	call n_cmd		; Feed the remaining command line to the 'n' command.
  if FMTEXE
	add sp, 80h
  endif
 endif

endif ; ife BOOTDBG

if BOOTDBG

;--- get final address of debugger behind conv. memory

	push ds
	xor cx, cx
	mov ds, cx
	mov ax, offset real_end + STACKSIZ + (1024-1)
	mov cl, 10
	shr ax, cl
	sub ds:[413h], ax
	mov ax, ds:[413h]
	pop ds
	mov cl, 6
	shl ax, cl
	mov [wDgroup], ax	; BOOTDBG: wDgroup and pspdbg must be updated!

endif

if DMCMD
	mov ah,52h		;get list of lists
	int 21h
	mov ax,es:[bx-2]	;start of MCBs
	mov [wMCB],ax
endif

ife (BOOTDBG or RING0)
	mov ah,34h
	int 21h
	mov word ptr [pInDOS+0],bx
	mov word ptr [pInDOS+2],es
endif
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

if ?DPMI

;--- Windows 3x/9x and DosEmu are among those hosts which handle some
;--- V86 Ints internally without first calling the interrupt chain.
;--- This causes various sorts of troubles and incompatibilities.

 if WIN9XSUPP
	mov ax,1600h	;running in a win3x/win9x dos box?
	int 2Fh
	and al,al		;returns in AL 3=win3x, 4=win9x
	jnz no2fhook
 endif
 if DOSEMU
	mov ax,0F000h
	mov es, ax
	mov di,0FFF5h
	mov si,offset dDosEmuDate
	mov cx,4
	repe cmpsw		;running in DosEmu?
	jz no2fhook_dosemu
 endif
	jmp dpmihostchecked
no2fhook_dosemu:
 if USEHWBP
	mov [bHWBPflgs],0; disable hw bps for DosEmu
 endif
no2fhook:
	inc [bNoHook2F]
dpmihostchecked:

endif

;--- setup hardware bp usage

if USEHWBP 
	test [bHWBPflgs],HWBP_ACTIVE
	jz @F
	mov ax, 9090h
	mov word ptr [setHWBps], ax		; patch code to NOPs
	mov byte ptr [resetHWBps], al
	mov [wStoreBP], offset storebpx
 if BCMD
	mov [bcmdv], offset b_cmd	;activate b cmd (requires 80386)
 endif
 ife RING0
;--- debug register access in v86 may be supported by v86-monitor
;--- jemm & qemm are ok; MS emm386 & Win3x/9x are not.
	.286
	smsw ax
	.8086
	test al,1
	jz @F				; if in real-mode
	test [bHWBPflgs],HWBP_V86
	jnz @F				; if cmdline option /v
	mov byte ptr v86patch,0F9h	; patch to STC, disables hwbp in v86
 endif
@@:
endif

	push ds
	pop es

if INT22

 if FMTEXE
	push ds
	mov ds, [pspdbg]
 endif

;--- Save and modify termination address and the parent PSP field.

	mov si,PSPS.TPIV
	mov di,offset psp22
	movsw
	movsw
	mov word ptr [si-4],offset intr22dbg

	mov [si-2],cs
	mov si,PSPS.PARENT
	movsw
	mov [si-2],cs

 if FMTEXE
	mov es:[pspdbe], ds
	pop ds
 else
	mov [pspdbe],cs	;indicate there is no debuggee loaded yet
 endif

endif

if VXCHG
 ifndef VXCHGFLIP
	mov ax,4300h	; check if XMM is here
	int 2Fh
	cmp al,80h
	jnz noxmm		; no - no screen flip
	mov ax,4310h
	int 2Fh
	mov word ptr [xmsdrv+0],bx
	mov word ptr [xmsdrv+2],es
	.286
	mov dx,32		; alloc 32 kB EMB
	mov ah,9
	call [xmsdrv]
	cmp ax,1
	jnz noxmm
	mov si, offset xmsmove
	mov [si].XMSM.dsthdl, dx			; save the handle in block move struct.
	mov byte ptr [si].XMSM.dstadr+1, 40h; the XMS memory will be used to
	push 0								; save/restore 2 screens, with a max
	pop es								; capacity per screen of 16 kB
	mov ax,es:[44Ch]					; current screen size, might change!
	mov word ptr [si].XMSM.size_, ax
	mov ax, es:[44Eh]					; page start in video memory
	mov word ptr [si].XMSM.srcadr+0, ax
	mov ax, 0B000h
	cmp byte ptr es:[463h],0B4h
	jz @F
	or ah, 8
@@:
	mov word ptr [si].XMSM.srcadr+2, ax
	mov al, es:[484h]
	mov [vrows], al
	mov ah, 0Fh					; get active video page in BH
	int 10h
	mov ah, 3					; get cursor pos in DX of active page
	int 10h
	mov [csrpos], dx
	mov ah, 0Bh					; save current screen now
	call [xmsdrv]
	.8086
noxmm:
 else
;--- use BIOS to swap page 0/1, a simple approach
;--- that in theory would fit perfectly, but
;--- unfortunately in reality may have quirks.
  if RING0
	.386
	push ds
	mov ds, [wFlat]
	movzx esi, word ptr ds:[44Eh]
	movzx ecx, word ptr ds:[44Ch]
	mov dx, ds:[450h+0*1]
	mov ds:[450h+1*2], dx
	mov eax, 0B0000h
	cmp byte ptr ds:[463], 0B4h
	jz @F
	or ah, 80h
@@:
	mov edi, esi
	add edi, ecx
	add esi, eax
	add edi, eax
	push ds
	pop es
	rep movsb es:[edi], ds:[esi]
	pop ds
	.8086
  else
	xor ax, ax
	mov es, ax
	mov si, es:[44Eh]	; page offset curr page
	mov cx, es:[44Ch]	; page size
	shr cx, 1
	mov ax, 0501h	; debugger page is 1
  ife (DRIVER or BOOTDBG)
	mov [vpage], al		; std: init here since we'll jump right into the debugger
  endif
	int 10h
	mov di, es:[44Eh]	; page offset page 1
	mov dx, es:[450h+0*1]
	mov es:[450h+1*2], dx
	mov ax, 0B000h		; copy page contents to page 1
	cmp byte ptr es:[463h],0B4h
	jz @F
	or ah, 8
@@:
	push ds
	mov es, ax
	mov ds, ax
	rep movsw
	pop ds
  endif
 endif
	push ds
	pop es
endif

;--- Set up interrupt vectors.

	mov cx, NUMINTS
	mov si, offset inttab
	mov di, offset intsave
if RING0
	.386
	les ebx, [bp-6]   ; load address of GDT
	@dprintf "initcode: setup int vectors, es:ebx=%X:%lX", es, ebx
elseif BOOTDBG
	xor ax, ax
	mov es, ax
endif
@@:
	lodsb
if RING0
	cmp al, -1
	jz skipint
	movzx edx, al
 if LMODE
	shl edx, 1	; in long mode, vector size is 16
 endif
	mov ax, es:[ebx+edx*8+0]
	mov [di+0], ax
	mov ax, es:[ebx+edx*8+6]
	mov [di+2], ax
	mov ax, es:[ebx+edx*8+2]
	mov [di+4], ax
elseif BOOTDBG
	mov bl, al
	mov bh, 0
	shl bx, 1
	shl bx, 1
	mov ax, es:[bx+0]
	mov dx, es:[bx+2]
	mov [di+0], ax
	mov [di+2], dx
else
	mov ah, 35h
	int 21h
	mov [di+0], bx
	mov [di+2], es
	xchg ax, dx		;save int # in dl
endif
;	mov ax, [si]	;get address
	lodsw			;get address (16-bit offset)
if RING0
 if LMODE
	movzx eax, ax	;in long mode, IDT vectors must be 64-bit!
	add eax, [dwBase64]
	mov es:[ebx+edx*8+0], ax
	mov word ptr es:[ebx+edx*8+2], CS64SEL	; CS must be 64-bit
	shr eax, 16
 else
	mov es:[ebx+edx*8+0], ax
	mov es:[ebx+edx*8+2], cs
	xor ax, ax
 endif
	mov es:[ebx+edx*8+6], ax
skipint:
elseif BOOTDBG
	mov dx, [wDgroup]
	mov es:[bx+0], ax
	mov es:[bx+2], dx
else
	xchg ax, dx		;AL=int#, DX=offset
	mov ah, 25h		;set interrupt vector
	int 21h
endif
;	add si, 2
	add di, sizeof INTVEC
	loop @B

;--- prepare to shrink DEBUG and set its stack

	mov ax, offset real_end + STACKSIZ + 15
	and al, not 15		; debug's top of stack
	mov bx, ax
if FLATSS
	add eax, [dwBase]
	mov [top_sp], eax
	@dprintf "top_sp=%lX", eax
else
	mov [top_sp], ax
endif
	jmp initcont

initcode endp

_ITEXT ends

_IDATA segment
cntpatch = ($ - patches) / 2
_IDATA ends

	end start
