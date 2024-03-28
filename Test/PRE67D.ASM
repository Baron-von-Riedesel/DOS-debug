
;--- disassembler: opcode that change due to 67h prefix
;--- assemble: jwasm pre67d.asm
;--- link: jwlink format win pe hx f pre67d.obj op stub=loadpe.bin,stack=0x1000

	.386
	.MODEL flat

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
	loopw @B
	loopew @B
	loopnew @B
	ret

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

