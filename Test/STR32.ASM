
;--- disassembler 32bit string cmds

	.286
	.model tiny
	.stack 256
	.dosseg
	.386

	.code

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

start:
	mov ah,4Ch
	int 21h

	END start
