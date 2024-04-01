
;--- test program termination with
;--- a) l cmd to reload a program
;--- b) q cmd to quit debug

;--- Vector 21h is intercepted and a breakpoint set for the AH=4Ch branch.
;--- This will return to the debugger, without actually terminating the
;--- debuggee. Prior to v2.03, debug ignored the entry mode and continued
;--- with the cmd (l/q), usually resulting in "memory corruption" or "out of
;--- memory" errors. Since v2.03, debug realizes that program termination
;--- failed and stops, reporting an "unexpected breakpoint".

	.286
	.model tiny
	.dosseg
	.stack 1024
	.386

	.data

oldvec dd ?

	.code

myint21 proc
	cmp ah, 4Ch
	jz @F
	jmp cs:[oldvec]
@@:
	int 3
	pusha
	push ds
	lds dx, cs:[oldvec]
	mov ax, 2521h
	pushf
	call cs:[oldvec]
	pop ds
	popa
	int 21h
	jmp $
myint21 endp

main proc

	mov ax, 3521h
	int 21h
	mov word ptr oldvec+0,bx
	mov word ptr oldvec+2,es
	push ds
	push cs
	pop ds
	mov dx, offset myint21
	mov ax, 2521h
	int 21h
	pop ds

	int 3

exit:
	lds dx, oldvec
	mov ax, 2521h
	int 21h
	ret
main endp

start:
	mov ax,@data
	mov ds, ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx
	mov bx, sp
	shr bx, 4
	add bx, 10h
	mov ah, 4Ah
	int 21h
	call main
	mov ah, 4ch
	int 21h

	END start
