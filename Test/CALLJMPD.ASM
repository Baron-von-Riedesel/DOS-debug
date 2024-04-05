
;--- (dis)assembler: test 32-bit call/jmp/push [memref]
;--- create: jwasm -mz calljmpd.asm

	.386
	.MODEL tiny
	.stack 1024
	.dosseg

PF16 typedef ptr far16
PF32 typedef ptr far32
PN32 typedef ptr near32

_DATA16 segment use16 public 'DATA'
var1s PN32 0
var2s PF32 0
var3s dw 0
var4s PF16 0
_DATA16 ends

	.code

var1 dd 0
var2 PF32 0
var3 dw 0
var4 PF16 0

main proc c

	int 3
	ret

	call [var1]	;near32
	jmp  [var1]
	call [var2]	;far32
	jmp  [var2]
	call [var3]	;near16
	jmp  [var3]
	call [var4]	;far16
	jmp  [var4]
	call [var1][ebx]
	jmp  [var1][ebx]
	call [var2][ebx]
	jmp  [var2][ebx]
	call [var3][ebx]
	jmp  [var3][ebx]
	call [var4][ebx]
	jmp  [var4][ebx]

	push [var1]	;dword
;   push [var2]
	push [var3]	;word
	push [var4]	;dword

	assume ds:_DATA16
	call [var1s]	;near32
	jmp  [var1s]
	call [var2s]	;far32
	jmp  [var2s]
	call [var3s]	;near16
	jmp  [var3s]
	call [var4s]	;far16
	jmp  [var4s]
	call [var1s][bx]
	jmp  [var1s][bx]
	call [var2s][bx]
	jmp  [var2s][bx]
	call [var3s][bx]
	jmp  [var3s][bx]
	call [var4s][bx]
	jmp  [var4s][bx]

	push [var1s]	;dword
;	push [var2s]
	push [var3s]	;word
	push [var4s]	;dword
	assume ds:DGROUP

main endp

start32 proc
	call main
	mov ax,4c00h
	int 21h
start32 endp

	include initpm.inc

	END start

