
;--- disassembler: handling of rep prefixes
;--- assemble: jwasm -mz prerepd.asm

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
	rep   movsb
	repnz cmpsb
	repz  scasb
	repne cmpsb
	repe  scasb

	assume ds:_DATA16
	assume es:_DATA16

	rep   movsb [di],[si]
	repnz cmpsb [si],[di]
	repz  scasb [di]
	repne cmpsb [si],[di]
	repe  scasb [di]

	assume ds:DGROUP

main endp

start32 proc
	call main
	mov ax,4c00h
	int 21h
start32 endp

	include initpm.inc

	END start

