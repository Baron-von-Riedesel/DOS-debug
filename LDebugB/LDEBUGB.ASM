
;--- load DebugB into FASTBOOT JLM
;--- assemble: JWasm -mz LDebugB.asm

	.286
	.model tiny
	.dosseg
	.stack 2048
	option casemap:none
	.386

CStr macro text:vararg
local sym
	.const
sym db text,0
	.code
	exitm <offset sym>
endm

DStr macro text:vararg
local sym
	.const
sym db text,'$'
	.code
	exitm <offset sym>
endm

	.const
helptxt label byte
	db "LDebugB supplies file DEBUGB.BIN to FASTLOAD JLM.",13,10
	db "Required:",13,10
	db " - Jemm v5.86+",13,10
	db " - Jemm loaded with option FASTLOAD",13,10
	db " - FASTLOAD.DLL be loaded",13,10
	db '$'

	.code

main proc

local dwFB:dword

	cld
	mov si,81h
nextchr:
	lodsb es:[si]
	cmp al,13
	jz cmdl_done
	cmp al,20h
	jbe nextchr
	mov dx,offset helptxt
	mov ah,9
	int 21h
	ret
cmdl_done:    
	mov bx,4435h	;FASTBOOT/REBOOT device ID
	mov ax,1684h	;get API entry point
	int 2Fh
	cmp al,0
	jnz not_installed
	mov word ptr dwFB+0,di
	mov word ptr dwFB+2,es
	mov ah,0		;get version
	call dwFB
	jc not_installed
	test ah,1		;FASTBOOT variant?
	jz not_installed

	call loaddebugb	;load DEBUGB.BIN into memory
	jc no_debugb

;--- FASTBOOT API AH=3: DS:SI=start debugb, ECX=size debugb in bytes

	push ds
	mov ds,di
	movzx ecx, si
	xor si,si
	mov ah,3
	call dwFB
	pop ds
	jc no_debugb2
	mov dx,DStr("DEBUGB.BIN loaded")
	mov ah,9
	int 21h
	call lfout
	ret

no_debugb2:
	mov dx,DStr("DEBUGB.BIN invalid",13,10)
	mov ah,9
	int 21h
no_debugb:
	mov dx,DStr("couldn't load DEBUGB.BIN")
	mov ah,9
	int 21h
	call lfout
	ret
not_installed:
	mov dx,DStr("FASTBOOT not installed")
	mov ah,9
	int 21h
	call lfout
	ret
main endp

lfout proc
	mov dx,DStr(13,10)
	mov ah,9
	int 21h
	ret
lfout endp

;--- get file size in EAX

getfilesize proc
	mov ax,4202h
	xor cx,cx
	xor dx,dx
	int 21h
	jc exit
	push dx
	push ax
	xor cx,cx
	xor dx,cx
	mov ax,4200h
	int 21h
	pop eax
exit:
	ret
getfilesize endp

;--- load file DEBUGB.BIN into memory
;--- out: DI=segment where debugb.bin has been loaded
;---      SI=size in bytes
;--- file debugb.bin must be in current directory.

loaddebugb proc
	mov dx,CStr("DEBUGB.BIN")
	mov ax,3D00h
	int 21h
	jc open_error
	mov bx,ax
	call getfilesize
	jc open_error
	cmp eax,10000h
	jnc file_too_big
	mov di,bx
	mov si,ax
	mov ebx,eax
	add ebx,16-1
	shr ebx,4
	mov ah,48h
	int 21h
	jc out_of_memory
	mov bx,di
	mov di,ax
	push ds
	mov ds,ax
	mov dx,0
	mov cx,si
	mov ax,3F00h
	int 21h
	pop ds
	jc read_error
	cmp ax,cx
	jnz read_error
	mov ah,3Eh
	int 21h
	ret
open_error:
	mov dx,DStr("DEBUGB.BIN open error")
	mov ah,9
	int 21h
	call lfout
	ret
file_too_big:
	mov dx,DStr("DEBUGB.BIN too big")
	mov ah,9
	int 21h
	call lfout
	ret
out_of_memory:
	mov dx,DStr("out_of_memory")
	mov ah,9
	int 21h
	call lfout
	ret
read_error:
	mov dx,DStr("DEBUGB.BIN read error")
	mov ah,9
	int 21h
	call lfout
	ret
loaddebugb endp

start:
	mov ax,cs
	mov ds,ax
	mov dx,ss
	sub dx,ax
	shl dx,4
	mov ss,ax
	add sp,dx
	mov bx,sp
	shr bx,4
	mov cx,es
	sub ax,cx
	add bx,ax
	mov ah,4Ah
	int 21h
	call main
	mov ah,4ch
	int 21h

	end start

