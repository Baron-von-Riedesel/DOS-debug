
;--- disassembler: handling of rep prefixes
;--- assemble: jwasm -mz prerep.asm

	.286
	.model small
	.stack 256
	.dosseg
	.386

	.code

main proc c

	int 3
	ret
	rep   movsb
	repnz cmpsb
	repz  scasb
	repne cmpsb
	repe  scasb
	rep   movsb [edi],[esi]
	repnz cmpsb [esi],[edi]
	repz  scasb [edi]
	repne cmpsb [esi],[edi]
	repe  scasb [edi]

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

