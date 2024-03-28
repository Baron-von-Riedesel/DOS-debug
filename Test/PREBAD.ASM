
;--- disassembler: handling of "bad" prefixes
;--- assemble: jwasm prebad.asm
;--- link: jwlink format win pe hx f prebad.obj op stub=loadpe.bin,stack=0x1000

	.386
	.MODEL flat

	.code

main proc c

	int 3
	ret
	db 67h,68h,74h,20h,28h,43h	; assembles to "push 43282074h" with "bad" prefix 67h

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

