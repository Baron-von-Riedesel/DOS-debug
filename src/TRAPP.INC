
;--- debugger entries for ring0 protected-mode
;--- a) exceptions ( 0, 1, 3, 6, 7, C, D, E )
;--- b) sysreq pressed

;--- v2.0: code changed so [run_int] is set only if entry is from
;--- debuggee. If debugger is reentered because of an exception inside
;--- the debugger, this var must not be modified anymore.

SKIPINTGPF equ 1	; ignore GPFs caused by INT xx

	.386

IRET32 struct
_eip    dd ?
_cs     dd ?
_efl    dd ?
IRET32 ends

EXCFR1 struct
wMsg dw ?
wOld dw ?
	IRET32 <>
EXCFR1 ends

FAULT32 struct
_errc   dd ?
        IRET32 <>
FAULT32 ends

EXCFR2 struct
wMsg dw ?
wOld dw ?
	FAULT32 <>
EXCFR2 ends

if CHKIOPL

CIIFR struct
dwESI	dd ?
wAX		dw ?
wDS		dw ?
wRet	dw ?
		EXCFR2 <>
CIIFR ends        

;--- check if at cs:(e)ip is an IOPL-sensitive instruction that
;--- caused a GPF.
;--- in: ESP+2 = EXCFR2
;--- out: C if yes

checkioplinstr proc
	push ds
	push ax
	push esi
	lds esi, fword ptr [esp].CIIFR._eip
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
	cmp al, 0E4h	;IN AL, XX?
	jz isiopl
	cmp al, 0E6h	;OUT XX, AL?
	jz isiopl
	mov ah, al
	and al, 0FCh
	cmp al, 0ECh	;EC/ED/EE/EF? IN AL/AX,DX OUT DX,AL/AX
	jz isiopl
	cmp ah, 0F3h	;REP
	jnz @F
	lodsb ds:[esi]
@@:
	and al,0FCh		;6C/6D/6E/6F (INSB, INSW, OUTSB, OUTSW)   
	cmp al,6Ch
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
	mov es, cs:[pspdbg]
	mov di, offset exc0Ecr2
	mov eax, cr2
	call hexdword
	pop eax
	pop di
	pop es
	ret

NotOurInt00:
	jmp cs:[oldi00]
NotOurInt01:
	jmp cs:[oldi01]
NotOurInt03:
	jmp cs:[oldi03]
if CATCHINT06
NotOurInt06:
	jmp cs:[oldi06]
endif
if CATCHINT07
NotOurInt07:
	jmp cs:[oldi07]
endif
if CATCHINT0C
NotOurInt0C:
	jmp cs:[oldi0C]
endif
NotOurInt0D:
	jmp cs:[oldi0D]
NotOurInt0E:
	jmp cs:[oldi0E]


intr00:				; divide error
	push NotOurInt00
	push EXC00MSG or (0 shl 8)
	jmp intrtnp

intr01:				; single-step interrupt
	push NotOurInt01
	push EXC01MSG or (1 shl 8)
	jmp intrtnp

intr03:				; breakpoint interrupt
	push NotOurInt03
	push EXC03MSG or (3 shl 8)
	jmp intrtnp

if CATCHINT06
intr06:
	push NotOurInt06
	push EXC06MSG or (6 shl 8)
	jmp intrtnp
endif

if CATCHINT07
intr07:
	push NotOurInt07
	push EXC07MSG or (7 shl 8)
	jmp intrtnp
endif

if CATCHINT0C
intr0C:
	push NotOurInt0C
	push EXC0CMSG or (12 shl 8) or 8000h
	jmp intrtnp
endif

if CATCHINT0D
intr0D:
	push NotOurInt0D
	push EXC0DMSG or (13 shl 8) or 8000h
	jmp intrtnp
endif

intr0E:
	push NotOurInt0E
	push EXC0EMSG or (14 shl 8) or 8000h
	jmp intrtnp

if CATCHSYSREQ

 if SYSRQINT eq 15h
	.err <'SYSRQINT equ 15h' not implemented for RING0>
 endif

@@:
	jmp cs:[oldisrq]
intrsrq:
	test cs:[bInDbg], 1
	jnz @B
;--- no way to call the real-mode IRQ handler from here. we check the sysreq
;--- bit and, if set, read the kbd port direct, also sending EOI to the PIC.
;--- Not really nice, but it works.
	push ds
	mov ds, cs:[wFlat]
	test byte ptr ds:[418h], 4	; sysreq pressed?
	pop ds
	jz @B
	push ax
	in al, 60h
	cmp al, 54h+80h		; sysreq released?
	pop ax
	jnz @B
	push ds
	mov ds, cs:[wFlat]
	and byte ptr ds:[418h], not 4
	pop ds
	push ax
	mov al, 20h
	out 20h, al
	pop ax
	push 0
	push SYSRQMSG
	jmp intrtnp

endif

;--- Common interrupt routine.

intrtnp proc

	test byte ptr [esp].EXCFR1.wMsg+1, 08	; int 08-0F?
	jz @F
if MCLOPT
	cmp cs:[bMPicB], 20h
	jae @F
endif
	push ax
	push cx
	mov al, 0Bh		; get ISR mask from PIC
	mov cl, byte ptr [esp+4].EXCFR1.wMsg+1
	mov ch, 0
	out 20h, al
	and cl, 7
	in al, 20h
	bt ax, cx
	pop cx
	pop ax
	jnc @F
	add esp, 2
	ret
@@:
	test byte ptr [esp].EXCFR1.wMsg+1, 80h
	jnz witherrc
	test byte ptr [esp].EXCFR1._efl+2, 2	; VM set?
	jz nov86
nostop:
	add esp,2
	ret
witherrc:
	test byte ptr [esp].EXCFR2._efl+2, 2	; VM set?
	jnz nostop
nov86:

	cmp cs:[bInDbg],0
	jz int_dbgee
	pop eax		; get msg + old
	test ah, 80h
	jz @F
	pop ecx	; skip error code
@@:
  if EXCCSIP
	pop ecx
	pop edx
  endif
	mov ss, cs:[pspdbg]
	mov sp, cs:[top_sp]
  if EXCCSIP
	mov ss:[intexcip], cx 
	mov ss:[intexccs], dx 
  endif
	mov ah, 0
	push ax
	cmp al, EXC0EMSG
	jnz ue_intx
	call rendercr2
	jmp ue_intx

int_dbgee:

;--- check vector traps (set/reset by VT/VC)
	push ax
	mov al, byte ptr [esp+2].EXCFR1.wMsg+1
	and ax, 1Fh
	bt cs:[wTrappedExc], ax	; exception trapped?
	pop ax
	jnc nostop

if CHKIOPL
;--- check if GPF caused by running CLI/STI/IN/OUT in IOPL=0
	cmp byte ptr [esp].EXCFR2.wMsg, EXC0DMSG
	jnz @F
	test byte ptr [esp].EXCFR2._efl+1, 30h	;IOPL==0?
	jnz @F
	push ax
	lar ax, word ptr [esp+2].EXCFR2._cs
	test ah, 60h	; ring 0?
	pop ax
	jz @F
	call checkioplinstr
	jc nostop	; if yes, don't stop in debugger
@@:
endif

	push ds
	mov ds, cs:[pspdbg]
	pop [regs.rDS]
	pop [run_intw]
	add esp, 2		; skip offset to NotOur...

;--- the rest of the stack contents should be preserved ( for skip cmd )

	bt [run_intw], 15
	jnc @F
	pop [regs.dwErrCode]
@@:
	pop dword ptr [regs.rIP]
	pop [regs.rCS]
	add esp, 2
	pop dword ptr [regs.rFL]
	mov word ptr [regs.dwErrCode+2],ax	; used to store AX temporarily
	lar ax, [regs.rCS]
	test ah, 60h						; ring 0 exception?
	mov ax,word ptr [regs.dwErrCode+2]
	jz @F
	pop dword ptr [regs.rSP]			; pop ring3 ss:esp
	pop [regs.rSS]
	add esp, 2
	mov [regs.r0Esp], esp
	mov [regs.r0SS], ss
	jmp intrtn_r0
@@:
	mov dword ptr [regs.rSP], esp		; save ring0 stack in regs
	mov [regs.r0Esp], esp				; also store here ( for getr0stk() ) 
	mov [regs.rSS], ss
	mov [regs.r0SS], ss
intrtn_r0:
	mov ss, [pspdbg]
	mov esp, offset regs.rSS
	cmp [run_int], EXC0EMSG
	jnz @F
	call rendercr2
@@:
	.8086
	mov ds, [regs.rDS]

;--- fall thru to intrtn

intrtnp endp

