
;--- disassembler: opcode that change due to 67h prefix
;--- assemble: jwasm -mz pre67.asm

	.286
	.MODEL small
	.stack 1024
	.dosseg
	.386

	.code

main proc c

	int 3
	ret
@@:
;--- the 32-bit variants
	jecxz @B
	loopd @B
	looped @B
	loopned @B
;--- the 16-bit variants
	jcxz @B
	loop @B
	loope @B
	loopne @B
	ret

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

