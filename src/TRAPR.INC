
;--- debugger entries for real-mode
;--- a) program termination
;--- b) exceptions ( 0, 1, 3, 6, 7, C, D, E )
;--- c) sysreq pressed

;--- v2.0: code changed so [run_int] is set only if entry is from
;--- debuggee. If debugger is reentered because of an exception inside
;--- the debugger, this must not be modified anymore.

if INT22
;--- debugger's int 22h (program termination) handler.
;--- there's no need to preserve registers.

intr22:
	cli
	mov cs:[run_int], INT22MSG	;remember interrupt type
	mov cs:[lastcmd], offset dmycmd
	jmp intrtn_progtrm

endif

;--- Interrupt 0 (divide error) handler.

intr00:
	mov cs:[run_int], EXC00MSG	;remember interrupt type
	jmp intrtnr		;jump to register saving routine


if CATCHINT01

;--- Interrupt 1 (single-step interrupt) handler.

intr01:
 if NOEXC01INDBG
	cmp cs:[bInDbg],0
	jnz @F
 endif
	mov cs:[run_int], EXC01MSG
	jmp intrtnr
 if NOEXC01INDBG
@@:
	iret			; just ignore the exception if in debug
 endif
 
endif

if CATCHINT06

intr06:
	mov cs:[run_int], EXC06MSG
	jmp intrtnr

endif

if CATCHINT07

intr07:
	cmp cs:[bInDbg],0
	jz @F
	mov ax, EXC07MSG
	jmp ue_intxx
@@:
	mov cs:[run_int], EXC07MSG
	jmp intrtnr

endif

if CATCHINT0C

NotOurInt0C:
	jmp cs:[oldi0C]

intr0C:
 if MCLOPT
	cmp cs:[bMPicB], 20h
	jae @F
 endif
	push ax
	mov al, 0Bh		; get ISR mask from PIC
	out 20h, al
	in al, 20h
	test al, 10h	; IRQ4 (int 0Ch) occured?
	pop ax
	jnz NotOurInt0C
@@:
	cmp cs:[bInDbg],0
	jz @F
	mov ax, EXC0CMSG
	jmp ue_intxx
@@:
	mov cs:[run_int], EXC0CMSG
	jmp intrtnr

endif

if CATCHINT0D

NotOurInt0D:
	jmp cs:[oldi0D]

intr0D:
 if MCLOPT
	cmp cs:[bMPicB], 20h
	jae @F
 endif
	push ax
	mov al, 0Bh		; get ISR mask from PIC
	out 20h, al
	in al, 20h
	test al, 20h	; IRQ5 (int 0Dh) occured?
	pop ax
	jnz NotOurInt0D
@@:
	cmp cs:[bInDbg],0
	jz @F
	mov ax, EXC0DMSG
	jmp ue_intxx
@@:
	mov cs:[run_int], EXC0DMSG
	jmp intrtnr

endif

if CATCHSYSREQ

@@:
	jmp cs:[oldisrq]
intrsrq:
	cmp cs:[bInDbg],0
	jnz @B
 if SYSRQINT eq 15h
	cmp ax, 8501h	;sysreq released?
	jnz @B
 else
	pushf
	push cs
	call @B
	push ds
	push ax
	xor ax, ax
	mov ds, ax
	pop ax
	test byte ptr ds:[418h], 4	;bit should be set while sysreq is pressed
	pop ds
	jnz @F
	iret
@@:
 endif
 if ?DPMI
	inc cs:[bNoHook2F]	; disable hooking
 endif
	mov cs:[run_int], SYSRQMSG	;remember interrupt type
	jmp intrtnr

endif

;--- Interrupt 3 (breakpoint interrupt) handler.

intr03:
if SKIPBPINDBG
	cmp cs:[bInDbg],0
	jz @F
	mov ax, EXC03MSG
	jmp ue_intxx
@@:
endif
	mov cs:[run_int], EXC03MSG	;remember interrupt type

intrtnr proc

	cli					;just in case
	pop cs:[regs.rIP]	;recover things from stack
if ?PM
	mov word ptr cs:[regs.rIP+2],0
endif
	pop cs:[regs.rCS]
	pop cs:[regs.rFL]
intrtn_progtrm::		;<--- int 22h
	mov cs:[regs.rSS],ss;save stack position
	sizeprf
	mov cs:[regs.rSP],sp
	mov sp,cs			; "push cs", "pop ss" without modifying [SP-2]
	mov ss,sp
	mov sp,offset regs.rSS

;--- fall thru to intrtn

intrtnr endp
