
;--- disassembler: handling of "bad" prefixes
;--- assemble: jwasm -mz prebadd.asm

	.386
	.MODEL tiny
	.stack 1024
	.dosseg

	.code

main proc c

	int 3
	ret
	db 67h
	push 12345678h
	db 66h
	mov al,ds:[0]
	db 26h
	xchg al, ah

main endp

start32 proc
	call main
	mov ax,4c00h
	int 21h
start32 endp

	include initpm.inc

	END start

