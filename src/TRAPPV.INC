
;--- debugger entries for ring0 protected-mode, with support for v86
;--- a) exceptions ( 0, 1, 3, 6, 7, C, D, E )
;--- b) sysreq pressed

;--- since the code is very low-level and modifies the IDT directly, there's
;--- a problem with the v86-monitor "breakpoints". They cause a GPF, but should
;--- be ignored by the debugger. Jemm, for example, uses the HLT opcode (F4) to
;--- switch out of v86-mode.

;--- v2.0: code changed so [run_int] is set only if entry is from
;--- debuggee. If debugger is reentered because of an exception inside
;--- the debugger, this var must not be modified anymore.

SKIPINTGPF equ 1	; 1=ignore GPFs caused by INT xx
JEMMPLEMU  equ 1	; 1=ignore GPFs for priviledged instructions that Jemm will emulate

;--- stack size problem: if "SAFESS equ 0" it's assumed that ring0 stack
;--- is 32-bit - which may not be true. if ring0 ss is 16-bit, but
;--- ring3 ss is 32-bit, hiword esp may be != 0 and the debugger will crash.

SAFESS equ 1

	.386

IRET32 struct
_eip	dd ?
_cs		dd ?
_efl	dd ?
IRET32 ends

FAULT32 struct
_errc   dd ?
    IRET32 <>
FAULT32 ends

EXCFR struct
_ret dw ?
wMsg dw ?
	FAULT32 <>
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
;--- for v86 mode, the instructions differ: it's
;--- CLI, STI, PUSHF, POPF, INT, IRET
;--- note: this proc is called in v86-mode even if IOPL == 3;

checkioplinstr proc
	push ds
	push ax
	push esi
	cld
	test byte ptr [esp].CIIFR._efl+2,2	;v86-mode?
	jz is_pm
	movzx esi, word ptr [esp].CIIFR._cs
	shl esi, 4
	add esi, [esp].CIIFR._eip
	mov ds, cs:[wFlat]

	mov al, byte ptr [esp].CIIFR._efl+1
	and al, 30h
	cmp al, 30h		; V86-mode with IOPL==3?
	jz check_io		; then check for IN/OUT only
;--- check for IOPL sensitive instructions in v86-mode
@@:
	lodsb [esi]
	cmp al, 66h		;size prefix
	jz @B
	cmp al, 9Ch		;PUSHF?
	jz isiopl
	cmp al, 9Dh		;POPF?
	jz isiopl
	cmp al, 0CDh	;INT?
	jz isiopl
	cmp al, 0CCh	;INT 3?
	jz isiopl
	cmp al, 0CFh	;IRET?
	jz isiopl
	jmp check_clisti
is_pm:
	lar ax, word ptr [esp].CIIFR._cs
	test ah, 60h	; ring 0 exception?
	jz done
	mov al, byte ptr [esp].CIIFR._efl+1
	and al, 30h
	cmp al, 30h		; IOPL==3 in protected-mode?
	jz done
@@:
	lds esi, fword ptr [esp].CIIFR._eip
	lodsb [esi]
check_clisti:
	cmp al, 0FAh	;CLI?
	jz isiopl
	cmp al, 0FBh	;STI?
	jz isiopl
if SKIPINTGPF
	cmp al, 0CDh	;INT XX? ( causes GPF if gate's DPL=0 )
	jz isiopl
endif
	jmp ci1
check_io:
@@:
	lodsb [esi]
ci1:
	cmp al, 0F3h	;REP?
	jz @B
	cmp al, 064h	; prefix?
	jz @B
	cmp al, 065h	; prefix?
	jz @B
	cmp al, 066h	; prefix?
	jz @B
	cmp al, 067h	; prefix?
	jz @B
	cmp al, 026h	; prefix?
	jz @B
	cmp al, 02Eh	; prefix?
	jz @B
	cmp al, 036h	; prefix?
	jz @B
	cmp al, 03Eh	; prefix?
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
done:
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

;--- see if an Exc 0D or 06 is caused by a monitor "breakpoint"
;--- this is called in v86 mode only.
;--- Jemm uses HLT (F4h) to switch out from v86-mode,
;--- Win9X uses ARPL (63h).
;--- Also, for exc 0D, it's checked here if the instruction causing the
;--- GPF is a mov to/from a special register. Those are
;--- emulated by Jemm and hence the debugger should route
;--- these exceptions to the previous handler.

CVMFR struct
dwESI	dd ?
wAX		dw ?
wDS		dw ?
wRet	dw ?
		EXCFR <>
CVMFR ends        

checkv86monitorbp proc
	push ds
	push ax
	push esi
	movzx esi, word ptr [esp].CVMFR._cs
	shl esi, 4
	add esi, [esp].CVMFR._eip
	mov ds, cs:[wFlat]
	cld
	lodsb [esi]
	cmp al, 0F4h	;HLT should never stop in debugger
	jz isv86mon
	cmp al, cs:[bV86Bp]	; may be HLT or ARPL
	jz isv86mon
	cmp byte ptr [esp].CVMFR.wMsg, EXC06MSG
	jz done
if JEMMPLEMU
	cmp al, 0Fh		;2 byte opcode? (0F 20, 0F 21, 0F 22, 0F 23)
	jnz done
	lodsb [esi]
	cmp al, 20h		;a mov to/from a "special reg" - that's emulated by Jemm
	jb done
	cmp al, 23h
	jbe isv86mon
endif
done:
	pop esi
	pop ax
	pop ds
	clc
	ret
isv86mon:
	pop esi
	pop ax
	pop ds
	stc
	ret
checkv86monitorbp endp

if SAFESS
checkss:
	push eax
	mov ax, ss
	lar eax, eax
	bt eax, 22
	jc @F
	movzx esp, sp
@@:
	pop eax
	ret
endif

@checkss macro
if SAFESS
	call checkss
endif
endm

;--- store value of cr2/cr3 in exc msg
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

;--- entries vectors 0,1,3,6,7,c,d,e

intr00:				; divide error
	push EXC00MSG or (0 shl 8)
	call intrtnp1
	jmp cs:[oldi00]

intr01:				; single-step interrupt/debug exception
	push EXC01MSG or (1 shl 8)
	call intrtnp1
	jmp cs:[oldi01]

if CATCHINT02
intr02:
	push EXC02MSG or (2 shl 8)
	call intrtnp1
	jmp cs:[oldi02]
endif

intr03:				; breakpoint interrupt
	push EXC03MSG or (3 shl 8)
	call intrtnp1
	jmp cs:[oldi03]

if CATCHINT06
intr06:
	push EXC06MSG or (6 shl 8)
	call intrtnp1
	jmp cs:[oldi06]
endif

if CATCHINT07
intr07:
	push EXC07MSG or (7 shl 8)
	call intrtnp1
	jmp cs:[oldi07]
endif

if CATCHINT0C
intr0C:
	push EXC0CMSG or (12 shl 8) or 8000h
	call intrtnp2
	jmp cs:[oldi0C]
endif

if CATCHINT0D
intr0D:
	push EXC0DMSG or (13 shl 8) or 8000h
	call intrtnp2
	jmp cs:[oldi0D]
endif

intr0E:
	push EXC0EMSG or (14 shl 8) or 8000h
	call intrtnp2
	jmp cs:[oldi0E]


if CATCHSYSREQ

 if SYSRQINT eq 15h
	.err <'SYSRQINT equ 15h' not implemented for RING0>
 endif

exitwithpopds:
	pop ds
@@:
	jmp cs:[oldisrq]
intrsrq:
	cmp cs:[bInDbg],0
	jnz @B
;--- no way to call the real-mode IRQ handler from here. we check the sysreq
;--- bit and, if set, set TF=1 - will trigger a single-step fault once the
;--- interrupt routine is done.
	push ds
	mov ds, cs:[wFlat]
	test byte ptr ds:[418h], 4	; sysreq pressed?
	jz exitwithpopds
	or byte ptr [esp+2].IRET32._efl+1, 1	; set TF=1
	mov ds, cs:[wDgroup]
	or [bFlagsPM], 2	; tell debugger that single-step is caused by SysReq
	bts [wTrappedExc+2], 1	; is exc 1 trapped?
	jc exitwithpopds
	or [bFlagsPM], 4		; if no, mark it in bFlagsPM   
	jmp exitwithpopds
endif

;--- exceptions with error code

intrtnp2:
	@checkss
if 0
	test byte ptr [esp].EXCFR.wMsg+1, 08	; int 08-0F?
	jz intrtnp
endif
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
	ret 2

;--- exceptions without error code
intrtnp1:
	@checkss
	push dword ptr [esp]	; add a fake "error code" to the stack frame

;--- Common interrupt routine.

intrtnp proc

	jmp novm86
nostop:
	test byte ptr [esp].EXCFR.wMsg+1, 80h	; error code real or faked?
	jnz @F
	ret 2+4				; skip msg + faked error code
@@:
	ret 2
novm86:
	cmp cs:[bInDbg],0
	jz int_dbgee

if 1
;--- if a callout is done to the v86 monitor for I/O, v86-monitor breakpoints will happen
;--- which the debugger has to ignore in any case.
	test byte ptr [esp].EXCFR._efl+2, 2		; v86mode?
	jz v86_check_done
	cmp byte ptr [esp].EXCFR.wMsg, EXC0DMSG
	jz @F
	cmp byte ptr [esp].EXCFR.wMsg, EXC06MSG	;in case ARPL is v86 monitor bp
	jnz v86_check_done
@@:
	call checkv86monitorbp
	jc nostop
	cmp byte ptr [esp].EXCFR.wMsg, EXC0DMSG
	jnz v86_check_done
	call checkioplinstr
	jc nostop
v86_check_done:
endif

	pop ax		; skip _ret
	pop ax		; get msg
	pop ecx		; skip error code
  if EXCCSIP
	pop ecx		; eip
	pop edx		; cs
  endif
	mov ss, cs:[wDgroup]
	movzx esp, cs:[top_sp]
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
	test byte ptr [esp+2].EXCFR._efl+2, 2		; v86mode?
	jz @F
	add al, 16
@@:
	and ax, 1Fh
	bt cs:[wTrappedExc], ax	; exception trapped in ring 0/3?
	pop ax
	jnc nostop

;--- check for v86-monitor bps

	test byte ptr [esp].EXCFR._efl+2, 2		; v86mode?
	jz nobpcheck
	cmp byte ptr [esp].EXCFR.wMsg, EXC0DMSG
	jz @F
	cmp byte ptr [esp].EXCFR.wMsg, EXC06MSG
	jnz nobpcheck
@@:
	call checkv86monitorbp
	jc nostop
nobpcheck:

if CHKIOPL
;--- check if GPF caused by an IOPL sensitive instruction in IOPL=0
	cmp byte ptr [esp].EXCFR.wMsg, EXC0DMSG
	jnz @F
	call checkioplinstr
	jc nostop		; IOPL sensitive instruction, don't stop!
@@:
endif

	push ds
	mov ds, cs:[wDgroup]
	pop [regs.rDS]
	add esp, 2		; skip return addr
	pop [run_intw]

;--- the rest of the stack contents should be preserved ( for skip cmd )

	pop [regs.dwErrCode]
	pop dword ptr [regs.rIP]
	pop [regs.rCS]
	add esp, 2
	pop dword ptr [regs.rFL]
	test byte ptr [regs.rFL+2],2		; v86?
	jnz intv86
	mov word ptr [regs.dwErrCode+2],ax	; used to store AX temporarily
	lar ax, [regs.rCS]
	test ah, 60h						; ring 0 exception?
	mov ax,word ptr [regs.dwErrCode+2]
	jz @F
	pop dword ptr [regs.rSP]			; pop ring3 ss:esp
	pop [regs.rSS]
	add esp, 2
	jmp intrtn_r0
intv86:
	pop dword ptr [regs.rSP]
	pop [regs.rSS]
	add esp, 2
	pop [regs.rES]
	add esp, 2
	pop [regs.rDS]
	add esp, 2
	pop [regs.rFS]
	add esp, 2
	pop [regs.rGS]
	add esp, 2
	jmp intrtn_r0
@@:
	mov dword ptr [regs.rSP], esp
	mov [regs.rSS], ss
intrtn_r0:
	mov [regs.r0Esp], esp		; in any case store here ( for "skip" and getr0stk() ) 
	mov [regs.r0SS], ss
	mov ss, [wDgroup]
	mov esp, offset regs.rSS
	test byte ptr [regs.rFL+2],2
	jz @F
	sub esp, 4*2	;skip GS, FS, ES, DS
	pushad
	jmp intrtn1
@@:
	mov ds, [regs.rDS]
	.8086

;--- fall thru to intrtn

intrtnp endp

