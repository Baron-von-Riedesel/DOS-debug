
;--- debugger entries for ring0 long-mode
;--- a) exceptions ( 0, 1, 3, 6, 7, C, D, E )
;--- b) sysreq pressed

;--- v2.0: code changed so [run_int] is set only if entry is from
;--- debuggee. If debugger is reentered because of an exception inside
;--- the debugger, this var must not be modified anymore.

SKIPINTGPF equ 1	; ignore GPFs caused by INT xx

	.386

FAULT64 struct
_errc   dd ?,?
_eip	dd ?,?
_cs		dd ?,?
_efl	dd ?,?
_esp	dd ?,?
_ss		dd ?,?
FAULT64 ends

EXCFR struct
wMsg    dw ?
wOfsOld dw ?
	FAULT64 <>
EXCFR ends

if CHKIOPL

CIIFR struct
dwESI	dd ?
wAX		dw ?
wDS		dw ?
wRet	dw ?
		EXCFR <>
CIIFR ends        

;--- check if at cs:(e)ip is an IOPL-sensitive instruction that
;--- caused a GPF.
;--- in: ESP = CIIFR
;--- out: C if yes

checkioplinstr proc
	push ds
	push ax
	push esi
	mov esi, [esp].CIIFR._eip
	mov ds, word ptr [esp].CIIFR._cs
	cld
	lodsb ds:[esi]
	cmp al, 0FAh	;CLI?
	jz isiopl
	cmp al, 0FBh	;STI?
	jz isiopl
if SKIPINTGPF
	cmp al, 0CDh	;INT XX? ( causes GPF if gate's DPL=0 )
	jz isiopl
endif
	jmp ci1
@@:
	lodsb ds:[esi]
ci1:
	cmp al, 0F3h	;REP?
	jz @B
	cmp al, 066h	;size prefix?
	jz @B

;--- E4/E5/E6/E7? IN AL/AX,XX - OUT XX,AL/AX
;--- EC/ED/EE/EF? IN AL/AX,DX - OUT DX,AL/AX
;--- 6C/6D/6E/6F? INSB/INSW   - OUTSB/OUTSW

	and al, 0FCh
	cmp al, 0E4h
	jz isiopl
	cmp al, 0ECh
	jz isiopl
	cmp al, 6Ch
	jz isiopl
	pop esi
	pop ax
	pop ds
	clc
	ret
isiopl:
	pop esi
	pop ax
	pop ds
	stc
	ret
checkioplinstr endp

endif

;--- store value of cr2 in exc msg
rendercr2:
	cld
	push es
	push di
	push eax
	mov es, cs:[wDgroup]
	mov di, offset exc0Ecr2
	mov eax, cr2
	call hexdword
	pop eax
	pop di
	pop es
	ret

;--- exceptions must be handled by 64-bit code.

	.x64

@DefEnt64 macro intno 
	pushw offset oldi&intno
if &intno&h ge 8
	pushw EXC&intno&MSG or ( intno&h shl 8 ) or 8000h
	jmp [jmpv162]
else
	pushw EXC&intno&MSG or ( intno shl 8 )
	jmp [jmpv161]
endif
endm

_TEXT64 segment

intr00:				; divide error
	@DefEnt64 00
intr01:				; single-step interrupt
	@DefEnt64 01
intr03:				; breakpoint interrupt
	@DefEnt64 03
if CATCHINT06
intr06:
	@DefEnt64 06
endif
if CATCHINT07
intr07:
	@DefEnt64 07
endif
if CATCHINT0C
intr0C:
	@DefEnt64 0C
endif
if CATCHINT0D
intr0D:
	@DefEnt64 0D
endif
intr0E:
	@DefEnt64 0E

_TEXT64 ends

	.386


if CATCHSYSREQ

 if SYSRQINT eq 15h
	.err <'SYSRQINT equ 15h' not implemented for RING0>
 endif

exitwithpopds:
	pop ds
@@:
	jmp cs:[oldisrq]
intrsrq:
	test cs:[bInDbg], 1
	jnz @B
;--- v2.50: changed strategy - instead of reading port 60h and see if
;--- SysRq was released, we check the BIOS variable only and if set, set
;--- TF=1, causing a single-step exception once the irq1 routine is done.
	push ds
	mov ds, cs:[wFlat]
	test byte ptr ds:[418h], 4	; sysreq pressed?
	jz exitwithpopds
	or byte ptr [esp+2].IRET32._efl+1, 1	; set TF=1
	mov ds, cs:[wDgroup]
	or [bFlagsPM], 2	; tell debugger that single-step is caused by SysReq
	jmp exitwithpopds
endif

;--- exceptions with error code

intrtnp2:
if MCLOPT
	cmp cs:[bMPicB], 20h
	jae intrtnp
endif

	push ax
if 1
;--- before checking the PIC, we check the status of EXCFR._cs
;--- Since IRQs don't push error codes, this would be the
;--- saved flags then. if IF and bit 1 aren't 1 (202h), it can't be
;--- an IRQ.
	mov ax, word ptr [esp+2].EXCFR._cs
	and ax, 202h
	cmp ax, 202h
	clc
	jnz @F
endif
	push cx
	mov al, 0Bh		; get ISR mask from PIC
	mov cl, byte ptr [esp+4].EXCFR.wMsg+1
	out 20h, al
	and cx, 7
	in al, 20h    
	bt ax, cx
	pop cx
@@:
	pop ax
	jnc intrtnp
	and byte ptr [esp].EXCFR.wMsg+1, 7Fh	; no error code on stack
nostop:
	push bx
	mov bx,[esp+2].EXCFR.wOfsOld
	push ds
	mov ds, cs:[wDgroup]
	push dword ptr [bx]
	pop  dword ptr [jmpv64]
	pop ds
	pop bx
	test byte ptr [esp].EXCFR.wMsg+1, 80h	; error code real or faked?
	lea esp, [esp+2+2]						; skip msg + oldvec addr
	jnz @F
	add esp, 8
@@:
	jmp cs:[jmpv64]

;--- exceptions without error code
intrtnp1:
	pushd 0		; add a fake "error code" to the stack frame
	push dword ptr [esp+4] ; ensure that msg + wOfsOld are on top of stack

;--- Common interrupt routine.

intrtnp proc

	cmp cs:[bInDbg],0
	jz int_dbgee
	pop ax		; get msg
  if EXCCSIP
	add esp, 2+8; skip wOfsOld + error code
	pop ecx
	add esp, 4	; skip high32 of rip
	pop dx
  endif
;	mov ss, cs:[wDgroup]
;	mov sp, cs:[top_sp]
	mov ss, cs:[wFlat]
	mov esp, cs:[top_sp]
  if EXCCSIP
   if EXCCSEIP
	push ecx	; eip
   else
	push cx		; ip
   endif
	push dx		; cs
  endif
	mov ah, 0
	push ax		; msg
	cmp al, EXC0EMSG
	jnz ue_intx
	call rendercr2
	jmp ue_intx

int_dbgee:
;--- check vector traps (set/reset by VT/VC)
	push ax
	mov al, byte ptr [esp+2].EXCFR.wMsg+1
	and ax, 1Fh
	bt cs:[wTrappedExc], ax	; exception trapped?
	pop ax
	jnc nostop

if CHKIOPL
;--- check if GPF caused by running CLI/STI/IN/OUT in IOPL=0
	cmp byte ptr [esp].EXCFR.wMsg, EXC0DMSG
	jnz @F
	test byte ptr [esp].EXCFR._efl+1, 30h	;IOPL==0?
	jnz @F
	push ax
	lar ax, word ptr [esp+2].EXCFR._cs
	test ah, 60h	; ring 0?
	pop ax
	jz @F
	call checkioplinstr
	jc nostop	; if yes, don't stop in debugger
@@:
endif

	push ds
	mov ds, cs:[wDgroup]
	pop [regs.rDS]
	pop [run_intw]

	add esp, 2		; skip wOfsOld

;--- the rest of the stack contents should be preserved ( for skip cmd )

	pop [regs.dwErrCode]
	add esp, 4
	pop dword ptr [regs.rIP]
	add esp, 4
	pop [regs.rCS]
	add esp, 4+2
	pop dword ptr [regs.rFL]
	add esp, 4
	pop dword ptr [regs.rSP]			; pop ss:esp
	add esp, 4
	pop [regs.rSS]
	add esp, 4+2

	mov [regs.r0Esp], esp
	mov [regs.r0SS], ss
	mov ss, [wDgroup]
	mov esp, offset regs.rSS
	mov ds, [regs.rDS]

	.8086

;--- fall thru to intrtn

intrtnp endp

