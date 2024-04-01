
;--- DATA1MB.ASM: 16-bit DPMI app with a data segment of 1 MB
;--- to test debug's 'd' cmd with offsets >= 10000h
;--- assemble: JWasm -mz data1mb.asm

LF  equ 10
CR  equ 13

	.286
	.model small
	.dosseg 	;this ensures that stack segment is last
	.stack 1024

	.code

main proc
	int 3
	ret
main endp

start:
	mov ax, ss
	mov cx, es
	sub ax, cx
	mov bx, sp
	shr bx, 4
	add bx, ax
	mov ah, 4Ah 	;free unused memory
	int 21h
	mov ax, @data
	mov ds, ax
	mov bx, ss
	sub bx, ax
	shl bx, 4
	mov ss, ax
	add sp, bx		;small model ss=ds=dgroup

	mov ax, 1687h	;DPMI host installed?
	int 2Fh
	and ax, ax
	jnz nohost
	push es 		;save DPMI entry address
	push di
	and si, si		;requires host client-specific DOS memory?
	jz @F
	mov bx, si
	mov ah, 48h 	;alloc DOS memory
	int 21h
	jc nomem
	mov es, ax
@@:
	mov bp, sp
	xor ax, ax	 		;start a 16-bit client
	call far ptr [bp]	;initial switch to protected-mode
	jc initfailed


	mov cx, lowword  100000h
	mov bx, highword 100000h
	mov ax, 501h		; alloc 1 MB
	int 31h
	jc memfailed
	push bx
	push cx
	mov cx, 1
	mov ax, 0			; alloc 1 descriptor
	int 31h
	jc descfailed
	mov bx, ax
	pop dx
	pop cx
	mov ax, 7			; set base
	int 31h
	mov dx, lowword  100000h-1
	mov cx, highword 100000h-1
	mov ax,8		 	; set descriptor limit
	int 31h
	mov cx, ds
	mov ss, bx			; switch SS,DS to 1 MB block
	mov ds, bx
	mov bx, cx
	mov ax, 1			; free original DS descriptor
	int 31h
	call main
	mov ax, 4C00h
	int 21h

starterr:
nohost:
	call error
	db e1-e1
nomem:
	call error
	db e2-e1
initfailed:
	call error
	db e3-e1
memfailed:
	call error
	db e4-e1
descfailed:
	call error
	db e5-e1
error:
	pop bx
	mov dl,cs:[bx]
	mov dh,0
	add dx, offset e1
	push cs
	pop ds
	mov ah, 9
	int 21h
	mov ax, 4C00h
	int 21h

e1  db "no DPMI host installed",CR,LF,'$'
e2  db "not enough DOS memory for initialisation",CR,LF,'$'
e3  db "DPMI initialisation failed",CR,LF,'$'
e4  db "no extended memory",CR,LF,'$'
e5  db "no descriptors",CR,LF,'$'

	end start
