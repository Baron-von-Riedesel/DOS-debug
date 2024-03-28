
;--- disassembler: handling of unused segment prefixes
;--- assemble: jwasm presegd.asm
;--- link: jwlink format win pe hx f presegd.obj op stub=loadpe.bin,stack=0x1000

	.386
	.MODEL flat

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

