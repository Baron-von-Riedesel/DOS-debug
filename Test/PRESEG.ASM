
;--- disassembler: handling of unused segment prefixes
;--- assemble: jwasm -mz preseg.asm

	.286
	.model small
	.stack 256
	.dosseg
	.386

	.code

main proc c

	int 3
	ret
	db 26h,2eh,36h,3eh,64h,65h
	movsw

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

