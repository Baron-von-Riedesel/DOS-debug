
;--- disassembler:
;---- 1. opcodes that change due to 67h prefix
;---- 2. address sizes that change due to 67h prefix
;--- assemble: jwasm -mz pre67d.asm

	.386
	.MODEL tiny
	.stack 1024
	.dosseg

_DATA16 segment use16 public 'DATA'
_DATA16 ends

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

	assume ds:_DATA16
	mov al,ds:[0]
	mov ax,ds:[0]
	mov eax,ds:[0]
	mov al,[si]
	mov ax,[si]
	mov eax,[si]
	assume ds:DGROUP

main endp

start32 proc
	call main
	mov ax,4c00h
	int 21h
start32 endp

	include initpm.inc

	END start

