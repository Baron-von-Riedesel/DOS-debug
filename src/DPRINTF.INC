
;--- debug printf - all registers preserved, including flags

if CATCHINT41
;--- .486 makes jwasm avoid LEAVE generation - problem if stack is 32-bit
;--- and hiword(ebp) != 0. That can happen for @dprintf inside intr41().
	.486
endif

handle_char proc

	cmp al,10
	jnz @F
	mov al,13
	call @F
	mov al,10
@@:
	push bx
	xor bx,bx
	mov ah,0Eh
if RING0
	call cs:[int10vec]
else
	int 10h
endif
	pop bx
	ret

handle_char endp

;--- ltob(long n, char * s, int base);
;--- convert long to string
;--- eax=number
;--- bx=buffer - is expected to be onto stack
;--- cx=base

;ltob PROC stdcall uses edi number:dword, outb:word, base:word
ltob PROC 

	push edi
	push edx
	movzx edi, cx
	mov ch,0
	cmp di,-10
	jne @F
	mov di,10
	and eax,eax
	jns @F
	neg eax
	mov ch,'-'
@@:
	add bx,10
	mov BYTE PTR ss:[bx],0
	dec bx
@@nextdigit:
	xor edx, edx
	div edi
	add dl,'0'
	cmp dl,'9'
	jbe @F
	add dl,7+20h
@@:
	mov ss:[bx],dl
	dec bx
	and eax, eax
	jne @@nextdigit
	cmp ch,0
	je @F
	mov ss:[bx],ch
	dec bx
@@:
	inc bx
	mov ax,bx
	pop edx
	pop edi
	ret

ltob ENDP

;--- ss doesn't need to be dgroup
;--- v2.01: ss may be 32-bit!

dprintf PROC

d_sp   equ word ptr [bp+16+2]
d_ret  equ word ptr [bp+16+2+2]
d_fmt  equ word ptr [bp+16+2+2+2]
d_args equ word ptr [bp+16+2+2+2+2]

if 0
local size_:word
local flag:byte
local longarg:byte
local fill:byte
local szTmp[12]:byte
else
d_size    equ <[bp-2]>
d_flag    equ <byte ptr [bp-3]>
d_longarg equ <byte ptr [bp-4]>
d_fill    equ <byte ptr [bp-5]>
d_szTmp   equ <[bp-18]>
endif

	push sp
	pushf
	pusha
	mov bp, sp
	sub sp, 18
	push ds
	push cs
	pop ds
	lea di, d_args
@@L335:
	mov si, d_fmt
nextchar:
	lodsb [si]
	or al,al
	je done
	cmp al,'%'
	je formatitem
	call handle_char
	jmp nextchar
done:
	sub di, 2
	mov ax, d_ret
	mov ss:[di], ax
	mov d_sp, di
	pop ds
	mov sp, bp
	popa
	popf
	pop sp
	ret

formatitem:
	push @@L335
	xor dx,dx
	mov d_longarg,dl
	mov bl,1
	mov cl,' '
	cmp BYTE PTR [si],'-'
	jne @F
	dec bx
	inc si
@@:
	mov d_flag, bl
	cmp BYTE PTR [si],'0'
	jne @F
	mov cl,'0'
	inc si
@@:
	mov d_fill,cl
	mov bx,dx

	.while byte ptr [si] >= '0' && byte ptr [si] <= '9'
		lodsb
		sub al,'0'
		cbw
		imul cx,bx,10		;cx = bx * 10
		add ax,cx
		mov bx,ax
	.endw

	mov d_size, bx
	cmp BYTE PTR [si],'l'
	jne @F
	mov d_longarg,1
	inc si
@@:
	lodsb
	mov d_fmt,si
	cmp al,'x'
	je handle_x
	cmp al,'X'
	je handle_x
	cmp al,'c'
	je handle_c
	cmp al,'d'
	je handle_d
	cmp al,'i'
	je handle_i
	cmp al,'s'
	je handle_s
	cmp al,'u'
	je handle_u
	cmp al,0
	jnz @@L359
	pop ax
	jmp done
handle_c:
	mov ax,ss:[di]
	add di,2
@@L359:
	call handle_char
	retn

handle_x:
	mov cx,16
	jmp @@lprt262
handle_d:
handle_i:
	mov cx,-10
	jmp @@lprt262
handle_u:
	mov cx,10
@@lprt262:
	mov ax,ss:[di]
	add di,2
	sub dx,dx
	cmp cx,0		;signed or unsigned?
	jge @F
	cwd
@@:
	cmp d_longarg,0
	je @F
	mov dx,ss:[di]
	add di,2
@@:
	lea bx, d_szTmp
	push dx
	push ax
	pop eax
;	invoke ltob, eax, bx, cx
	call ltob
	mov si,ax
	push ds
	push ss
	pop ds
	call output_string
	pop ds
	retn

handle_s:
	mov si,ss:[di]
	add di,2

output_string:	;display string at ds:si
	mov ax,si
	mov bx,d_size
	.while byte ptr [si]
		inc si
	.endw
	sub si,ax
	xchg ax,si
	sub bx,ax
	.if d_flag == 1
		.while sword ptr bx > 0
			mov al, d_fill
			call handle_char
			dec bx
		.endw
	.endif

	.while byte ptr [si]
		lodsb
		call handle_char
	.endw

	.while sword ptr bx > 0
		mov al, d_fill
		call handle_char
		dec bx
	.endw
	retn

dprintf ENDP

