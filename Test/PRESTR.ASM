
;--- disassembler: 32bit string instructions in 16-bit code
;--- assemble: jwasm -mz prestr.asm

	.286
	.model small
	.stack 256
	.dosseg
	.386

	.code

main:
	int 3
	ret
;--- 32bit variants
	cmpsb ds:[esi], es:[edi]
	lodsb ds:[esi]
	movsb es:[edi], ds:[esi]
	scasb es:[edi]
	stosb es:[edi]

	cmpsw ds:[esi], es:[edi]
	lodsw ds:[esi]
	movsw es:[edi], ds:[esi]
	scasw es:[edi]
	stosw es:[edi]

	cmpsd ds:[esi], es:[edi]
	lodsd ds:[esi]
	movsd es:[edi], ds:[esi]
	scasd es:[edi]
	stosd es:[edi]

	repnz cmpsb ds:[esi], es:[edi]
	rep   lodsb ds:[esi]
	rep   movsb es:[edi], ds:[esi]
	repnz scasb es:[edi]
	rep   stosb es:[edi]

	repnz cmpsw ds:[esi], es:[edi]
	rep   lodsw ds:[esi]
	rep   movsw es:[edi], ds:[esi]
	repnz scasw es:[edi]
	rep   stosw es:[edi]

	repnz cmpsd ds:[esi], es:[edi]
	rep   lodsd ds:[esi]
	rep   movsd es:[edi], ds:[esi]
	repnz scasd es:[edi]
	rep   stosd es:[edi]

	repnz cmpsb cs:[esi], es:[edi]
	rep   lodsb cs:[esi]
	rep   movsb es:[edi], cs:[esi]
	repnz cmpsw cs:[esi], es:[edi]
	rep   lodsw cs:[esi]
	rep   movsw es:[edi], cs:[esi]
	repnz cmpsd cs:[esi], es:[edi]
	rep   lodsd cs:[esi]
	rep   movsd es:[edi], cs:[esi]

;--- 16bit variants
	cmpsb
	lodsb
	movsb
	scasb
	stosb

	cmpsw
	lodsw
	movsw
	scasw
	stosw

	cmpsd
	lodsd
	movsd
	scasd
	stosd

	repnz cmpsb
	rep   lodsb
	rep   movsb
	repnz scasb
	rep   stosb

	repnz cmpsw
	rep   lodsw
	rep   movsw
	repnz scasw
	rep   stosw

	repnz cmpsd
	rep   lodsd
	rep   movsd
	repnz scasd
	rep   stosd

	repnz cmpsb cs:[si], es:[di]
	rep   lodsb cs:[si]
	rep   movsb es:[di], cs:[si]
	repnz cmpsw cs:[si], es:[di]
	rep   lodsw cs:[si]
	rep   movsw es:[di], cs:[si]
	repnz cmpsd cs:[si], es:[di]
	rep   lodsd cs:[si]
	rep   movsd es:[di], cs:[si]

start:
	call main
	mov ah,4Ch
	int 21h

	END start
