
;--- disassembler:
;--- 1. opcodes that change due to 66h prefix
;--- 2. register names that change due to 66h prefix
;--- assemble: jwasm -mz pre66d.asm

	.386
	.MODEL tiny
	.stack 1024
	.dosseg

	.data?
xxx db 200 dup (?)
	.code

main proc c

	int 3
	ret
;--- the 32-bit variants
	cwde
	cmpsd
	cdq
	fldenvd [xxx]
	frstord [xxx]
	fsaved  [xxx]
	fstenvd [xxx]
	insd
	iretd
	lodsd
	movsd
	outsd
	popad
	popfd
	pushad
	pushfd
	retd	; should be retfd
	retd 4
	scasd
	stosd
;--- the 16-bit variants
	cbw
	cmpsw
	cwd
	fldenvw [xxx]
	frstorw [xxx]
	fsavew  [xxx]
	fstenvw [xxx]
	insw
	iret	; should be iretw
	lodsw
	movsw
	outsw
	popaw
	popf	; should be popfw
	pusha	; should be pushaw
	pushf	; should be pushfw
	retw	; should be retfw (masm 6.15 wrongly generates a 66h prefix here!)
	retw 4
	scasw
	stosw

	mov ax, 1
	lea bx, [bx]
	mov ds, ax

main endp

start32 proc
	call main
	mov ax,4c00h
	int 21h
start32 endp

	include initpm.inc

	END start

