
;--- disassembler: 16-bit string instructions in 32-bit code
;--- assemble: jwasm -mz prestrd.asm

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
	assume ds:_DATA16
	assume es:_DATA16
	assume fs:_DATA16
	assume ss:_DATA16

	lodsb [si]
	lodsw [si]
	lodsd [si]
	movsb [di],[si]
	movsw [di],[si]
	movsd [di],[si]
	outsb dx,[si]
	outsw dx,[si]
	outsd dx,[si]
	cmpsb [si],[di]
	cmpsw [si],[di]
	cmpsd [si],[di]
	insb  [di], dx
	insw  [di], dx
	insd  [di], dx
	scasb [di]
	scasw [di]
	scasd [di]

	lodsb ss:[si]
	lodsw ss:[si]
	lodsd ss:[si]
	movsb [di],ss:[si]
	movsw [di],ss:[si]
	movsd [di],ss:[si]
	outsb dx,es:[si]
	outsw dx,es:[si]
	outsd dx,es:[si]
	cmpsb fs:[si],[di]
	cmpsw fs:[si],[di]
	cmpsd fs:[si],[di]
;--- es prefix is default, cannot be changed
	insb  es:[di], dx
	insw  es:[di], dx
	insd  es:[di], dx
	scasb es:[di]
	scasw es:[di]
	scasd es:[di]

	assume ds:_DATA
	assume es:_DATA
	assume fs:_DATA
	assume gs:_DATA
	assume ss:_DATA

	lodsb [esi]
	lodsw [esi]
	lodsd [esi]
	movsb [edi],[esi]
	movsw [edi],[esi]
	movsd [edi],[esi]
	outsb dx,[esi]
	outsw dx,[esi]
	outsd dx,[esi]
	cmpsb [esi],[edi]
	cmpsw [esi],[edi]
	cmpsd [esi],[edi]
	insb  [edi], dx
	insw  [edi], dx
	insd  [edi], dx
	scasb [edi]
	scasw [edi]
	scasd [edi]

	lodsb cs:[esi]
	lodsw cs:[esi]
	lodsd cs:[esi]
	movsb [edi],ss:[esi]
	movsw [edi],ss:[esi]
	movsd [edi],ss:[esi]
	outsb dx,fs:[esi]
	outsw dx,fs:[esi]
	outsd dx,fs:[esi]
	cmpsb gs:[esi],[edi]
	cmpsw gs:[esi],[edi]
	cmpsd gs:[esi],[edi]
;--- es prefix is default, cannot be changed
	insb  es:[edi], dx
	insw  es:[edi], dx
	insd  es:[edi], dx
	scasb es:[edi]
	scasw es:[edi]
	scasd es:[edi]

main endp

start32 proc c public
	call main
	mov ax,4c00h
	int 21h
start32 endp

	include initpm.inc

	END start

