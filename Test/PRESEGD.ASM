
;--- disassembler: handling of unused segment prefixes
;--- assemble: jwasm -mz presegd.asm

	.386
	.MODEL tiny
	.stack 1024
	.dosseg

	.code

main proc c

	int 3
	ret
	db 26h,2eh,36h,3eh,64h,65h
	movsd

main endp

start32 proc
	call main
	mov ax,4c00h
	int 21h
start32 endp

	include initpm.inc

	END start

