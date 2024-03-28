
;--- disassembler: handling of rep prefixes
;--- assemble: jwasm prerep.asm
;--- link: jwlink format win pe hx f prerep.obj op stub=loadpe.bin,stack=0x1000

	.386
	.MODEL flat

	.code

main proc c

	int 3
	ret
	rep movsb
	repnz cmpsb
	repz scasb
	repne cmpsb
	repe scasb

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

