
;--- debugger entries for DPMI protected-mode
;--- exceptions ( 0, 1, 3, 6, 7, C, D, E )

;--- stack frames DPMI exception handlers 16/32-bit

EXFR16 struc
		dw 8 dup (?)	; pusha
wMsg	dw ?
		dw 2 dup (?)	; far16 return to DPMI
wErrC	dw ?
rIP		dw ?
rCS		dw ?
rFL		dw ?
rSP		dw ?
rSS		dw ?
EXFR16 ends

EXFR32 struc
		dd 8 dup (?)	; pushad
wMsg	dw ?
		dd 2 dup (?)	; far32 return to DPMI
dwErrC	dd ?
rEIP	dd ?
rCS		dw ?
		dw ?
rEFL	dd ?
rESP	dd ?
rSS		dw ?
		dw ?
EXFR32 ends

excxx_16:
	pusha
	mov bp,sp
	push ds
	mov ds,cs:[dssel]
	mov ax,[bp].EXFR16.rIP
	mov bx,[bp].EXFR16.rCS
	mov cx,[bp].EXFR16.rFL
	mov dx,[bp].EXFR16.rSP
	mov si,[bp].EXFR16.rSS
	mov di,[bp].EXFR16.wMsg
	mov [bp].EXFR16.rCS, cs
	mov [bp].EXFR16.rSS, ds
	cmp [bInDbg],0				;did the exception occur inside DEBUG?
	jz isdebuggee16
if EXCCSIP
	mov si, bx
endif
	mov [bp].EXFR16.rIP,offset ue_intx
	mov bx, [top_sp]
	sub bx, 3*2
	mov [bx+0], di
if EXCCSIP
	mov [bx+2], si
	mov [bx+4], ax
endif
	mov [bp].EXFR16.rSP, bx
	and byte ptr [bp].EXFR16.rFL+1, not 1	;reset TF
	pop ax
	jmp back2dpmi16
isdebuggee16:
	mov [bp].EXFR16.rIP, offset intrtn
	and byte ptr [bp].EXFR16.rFL+1, not 3	;reset IF + TF
	mov [bp].EXFR16.rSP, offset regs.rSS
	mov [regs.rIP],ax
	mov word ptr [regs.rIP+2],0
	mov [regs.rCS],bx
	mov [regs.rFL],cx
	mov [regs.rSP],dx
	mov [regs.rSS],si
	mov [run_intw],di
;	pop ax
;	mov [regs.rDS],ax
;	mov ds,ax
	pop ds
back2dpmi16:
	popa
	add sp, 2
	retf

exc00:
	push EXC00MSG
	jmp exc_xx
exc01:
	push EXC01MSG
	jmp exc_xx
exc03:
	push EXC03MSG
	jmp exc_xx
if CATCHEXC06
exc06:
	push EXC06MSG
	jmp exc_xx
endif
if CATCHEXC07
exc07:
	push EXC07MSG
	jmp exc_xx
endif
if CATCHEXC0C
exc0c:
	push EXC0CMSG
	jmp exc_xx
endif
exc0d:
	push EXC0DMSG
	jmp exc_xx
exc0e:
	push EXC0EMSG
exc_xx:
	test cs:[dpmi32],1
	jz excxx_16

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
	mov di, [ebp].EXFR32.wMsg
	mov [ebp].EXFR32.rCS, cs
	mov [ebp].EXFR32.rSS, ds
	cmp [bInDbg],0	;did the exception occur inside DEBUG?
	jz isdebuggee32
if EXCCSIP
;--- it's assumed that an exception in DEBUG is always in 16-bit code,
;--- but this isn't necessarily true, since the debuggee may have hooked
;--- exceptions. Since v2.0, this is less probable, because DebugX will
;--- always restore exception handlers 0D/0E on entry.
	mov si, bx
endif
	mov [ebp].EXFR32.rEIP,offset ue_intx
	movzx ebx,[top_sp]
if EXCCSIP
 if EXCCSEIP
	sub bx, 2*2+4
 else
	sub bx, 3*2
 endif
else
	sub bx, 2
endif
	mov [bx+0], di	; msg
 if EXCCSIP
	mov [bx+2], si	; cs
  if EXCCSEIP
	mov [bx+4], eax
  else
	mov [bx+4], ax
  endif
 endif
	mov [ebp].EXFR32.rESP, ebx
	and byte ptr [ebp].EXFR32.rEFL+1, not 1	;reset TF
	pop ax
	jmp back2dpmi32
isdebuggee32:
	@dprintf "excxx: client exception"
	mov [ebp].EXFR32.rEIP, offset intrtn
	and byte ptr  [ebp].EXFR32.rEFL+1, not 3;reset IF + TF
	mov [ebp].EXFR32.rESP, offset regs.rSS
	mov dword ptr [regs.rIP], eax
	mov [regs.rCS],bx
;	mov dword ptr [regs.rFL], ecx	; preferable?
	mov [regs.rFL],cx
	mov dword ptr [regs.rSP], edx
	mov [regs.rSS],si
	mov [run_intw],di
;	pop ax
;	mov [regs.rDS],ax
;	mov ds,ax
	pop ds
back2dpmi32:
	popad
	add sp, 2
	retd

