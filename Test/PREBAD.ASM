
;--- disassembler: handling of "bad" prefixes
;--- assemble: jwasm -mz prebad.asm

	.286
	.model small
	.stack 256
	.dosseg
	.386

	.code

main proc c

	int 3
	ret
	db 67h
	push 2074h
	db 66h
	mov al,ds:[0]
	db 26h
	xchg al, ah

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

