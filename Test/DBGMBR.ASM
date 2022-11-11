
;--- simple MBR to load DebugB
;--- 1. loaded at 7C00h
;--- 2. relocates itself to 600h
;--- 3. reads 40 sectors (# 1-40 ) at 8000h
;--- 4. calls 0800h:0000
;--- 5. breakpoint to activate debugger

_TEXT segment word public 'CODE'

	assume ds:_TEXT

	org 600h

start:
	XOR AX, AX
	MOV SS, AX
	MOV SP, 7C00h
	STI
	mov es, ax
	mov ds, ax
	CLD
	MOV SI, offset start2 + (7C00h - 600h)
	MOV DI, offset start2
	PUSH AX
	PUSH DI
	MOV CX, (start+200h) - start2
	REP MOVSB
	RETF
start2:

;--- no check of partition table, just load DebugB ( assumed in sector 1 - 4x )
;--- register DL should contain disk#

	push dx              ; save drive [bp+6]
	MOV BX, 55AAh
	MOV AH, 41h
	INT 13h
	JB nolba
	CMP BX, 0AA55h
	JNZ nolba
	TEST CL, 01
	JZ nolba
	mov ax, 1
	jmp ok
nolba:
	mov ah, 8
	int 13h
	jc error1
	mov si, cx
	and si, 3Fh
	mov al, dh
	inc al
	mov ah, 0
	mov di, ax
	mov ax, 0
ok:
	push ax             ; access method: 0=chs,1=lba [bp+4]
	mov ax, 0
	push ax             ; hiword sector# [bp+2]
	mov ax, 1
	push ax             ; loword sector# [bp+0]
	mov bp, sp
	mov cx, 40          ; sectors to read
	mov bx, 8000h       ; offset of address to load DebugB
	call read_access
	jc error1
	db 9ah              ; call 0800h:0000
	dw 0, 800h
	mov dx,[bp+6]
	int 3
	int 19h

lba2chs:
	mov cx, word ptr [bp+0]
	mov ax, word ptr [bp+2]
	xor dx, dx
	div si
	xchg ax, cx
	div si
	inc dx
	xchg cx, dx
	div di
	mov dh, dl
	mov ch, al
	ror ah, 1
	ror ah, 1
	or cl, ah
	ret

;--- read cx sectors at es:bx
;--- sector# in [bp+0], access method in [bp+4], drive in [bp+6]

read_access:
	cmp word ptr [bp+4],0
	jnz uselba
	push cx
	call lba2chs   ; translate LBA to CHS (DH:CX)
	pop ax         ; sectors to read in AL
	mov dl, [bp+6]
	MOV AH, 2h     ; CHS read
	INT 13h
	ret
uselba:
	XOR SI,SI
	PUSH SI        ; sector# 48-63
	PUSH SI        ; sector# 32-47
	PUSH word ptr [bp+2]
	PUSH word ptr [bp+0]
	PUSH ES
	PUSH BX
	PUSH CX
	MOV  SI,0010h
	PUSH SI
	MOV SI,SP
	mov dl, [bp+6]
	MOV AX,4200h	 ; LBA read
	INT 13h
	lea sp, [si+2*8]
	RET

error1:
	mov si, offset szerr
nextchar:
	lodsb
	and al,al
	jz @F
	mov ah,0eh
	mov bx,1
	int 10h
	jmp nextchar
@@:
	int 18h
	jmp @B

szerr db "disk i/o error",13,10,0

	org 7feh
	dw 0AA55h

_TEXT ends

	end
