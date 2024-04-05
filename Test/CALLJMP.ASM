
;--- (dis)assembler: test 32-bit call/jmp/push [memref]
;--- create: jwasm -mz calljmp.asm

	.286
	.MODEL small
	.stack 1024
	.dosseg
	.386

PN32 typedef ptr near32

_DATA32 segment use32 public 'DATA'
var1l dw 0
var2l dd 0
var3l PN32 0
var4l df 0
_DATA32 ends

	.data

var1 dw 0
var2 dd 0
var3 PN32 0
var4 df 0

	.code

main proc c

	int 3
	ret

	call [var1]	;near16
	jmp  [var1]
	call [var2]	;far16
	jmp  [var2]
	call [var3]	;near32
	jmp  [var3]
	call [var4]	;far32
	jmp  [var4]
	call [var1][bx]
	jmp  [var1][bx]
	call [var2][bx]
	jmp  [var2][bx]
	call [var3][bx]
	jmp  [var3][bx]
	call [var4][bx]
	jmp  [var4][bx]

	push [var1]	;word
	push [var2]	;dword
	push [var3]
;	push [var4]
	push [var1][bx];word
	push [var2][bx];dword
	push [var3][bx]
;	push [var4][bx]

	assume ds:_DATA32
	call [var1l]	;near16
	jmp  [var1l]
	call [var2l]	;far16
	jmp  [var2l]
	call [var3l]	;near32
	jmp  [var3l]
	call [var4l]	;far32
	jmp  [var4l]
	call [var1l][ebx]
	jmp  [var1l][ebx]
	call [var2l][ebx]
	jmp  [var2l][ebx]
	call [var3l][ebx]
	jmp  [var3l][ebx]
	call [var4l][ebx]
	jmp  [var4l][ebx]

	push [var1l]	;word
	push [var2l]	;dword
	push [var3l]
;   push [var4l]
	push [var1l][ebx];word
	push [var2l][ebx];dword
	push [var3l][ebx]
;	push [var4l][bx]

	assume ds:DGROUP

main endp

start proc
	call main
	mov ax,4c00h
	int 21h
start endp

	END start

