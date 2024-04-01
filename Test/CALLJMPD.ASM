
;--- assembler:
;---- call/jmp/push [memref]

	.386
	.MODEL tiny
	.stack 1024
	.dosseg

PF16 typedef ptr far16
PF32 typedef ptr far32

_DATA16 segment use16 public 'DATA'
var1s dd 0
var2s PF16 0
var3s PF32 0
var4s dw 0
_DATA16 ends

	.code

var1 dd 0
var2 PF16 0
var3 PF32 0
var4 dw 0

main proc c

	int 3
	ret

	call [var1]
	jmp  [var1]
	push [var1]
	call [var2]
	jmp  [var2]
	push [var2]
	call [var3]
	jmp  [var3]
;	push [var3]
	call [var4]
	jmp  [var4]
	push [var4]
	assume ds:_DATA16
	call [var1s]
	jmp  [var1s]
	push [var1s]
	call [var2s]
	jmp  [var2s]
	push [var2s]
	call [var3s]
	jmp  [var3s]
;	push [var3s]
	call [var4s]
	jmp  [var4s]
	push [var4s]
	assume ds:DGROUP

main endp

start32 proc
	call main
	mov ax,4c00h
	int 21h
start32 endp

	include initpm.inc

	END start

