
;--- disassembler:
;---- 1. opcodes that change due to 67h prefix
;---- 2. address sizes that change due to 67h prefix
;--- assemble: jwasm -mz pre67.asm

	.286
	.MODEL small
	.stack 1024
	.dosseg
	.386

_DATA32 segment use32 public 'DATA'
_DATA32 ends

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
	assume ds:_DATA32
	mov al,ds:[0]
	mov ax,ds:[0]
	mov eax,ds:[0]
	mov al,[esi]
	mov ax,[esi]
	mov eax,[esi]
	assume ds:DGROUP

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

