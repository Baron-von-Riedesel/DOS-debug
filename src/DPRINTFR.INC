
;--- debug printf - all registers preserved, including flags
;--- DEBUGR variant, compatible with 32-bit stack

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
	call cs:[int10vec]
	pop bx
	ret

handle_char endp

;--- ltob(long n, char * s, int base);
;--- convert long to string
;--- eax=number
;--- ss:ebx=buffer
;--- cx=base

ltob PROC 

	push edi
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
	add ebx,10
	mov BYTE PTR ss:[ebx],0
	dec ebx
@@nextdigit:
	xor edx, edx
	div edi
	add dl,'0'
	cmp dl,'9'
	jbe @F
	add dl,7+20h
@@:
	mov ss:[ebx],dl
	dec ebx
	and eax, eax
	jne @@nextdigit
	cmp ch,0
	je @F
	mov ss:[ebx],ch
	dec ebx
@@:
	inc ebx
	mov eax,ebx
	pop edi
	ret

ltob ENDP

;--- ds unused; ss unknown, may be 16- or 32-bit.
;--- tiny model ( strings may be addressed with CS ) assumed.

dprintf PROC

d_esp     equ <dword ptr [ebp+32+2]>
d_ret     equ <word ptr [ebp+32+2+4]>
d_fmt     equ <word ptr [ebp+32+2+4+2]>
d_args    equ <[ebp+32+2+4+2+2]>

d_size    equ <word ptr [ebp-2]>
d_flag    equ <byte ptr [ebp-3]>
d_longarg equ <byte ptr [ebp-4]>
d_fill    equ <byte ptr [ebp-5]>
d_szTmp   equ <[ebp-18]>

	push esp
	pushf
	pushad
	mov ebp, esp
	sub esp, 18
	mov ax, ss
	lar eax, eax
	bt eax, 22
	jc @F
	movzx ebp, bp
@@:
	lea edi, d_args
@@L335:
	mov si, d_fmt
nextchar:
	lodsb cs:[si]
	or al,al
	je done
	cmp al,'%'
	je formatitem
	call handle_char
	jmp nextchar
done:
	sub edi, 2
	mov ax, d_ret
	mov ss:[edi], ax
	mov d_esp, edi
	add esp, 18
	popad
	popf
	pop esp
	ret

formatitem:
	push @@L335
	xor dx,dx
	mov d_longarg,dl
	mov bl,1
	mov cl,' '
	cmp BYTE PTR cs:[si],'-'
	jne @F
	dec bx
	inc si
@@:
	mov d_flag, bl
	cmp BYTE PTR cs:[si],'0'
	jne @F
	mov cl,'0'
	inc si
@@:
	mov d_fill,cl
	mov bx,dx
@@:
	lodsb cs:[si]
	cmp al, '0'
	jb numdone
	cmp al, '9'
	ja numdone
	sub al,'0'
	cbw
	imul cx,bx,10		;cx = bx * 10
	add ax,cx
	mov bx,ax
	jmp @B
numdone:
	dec si
	mov d_size, bx
	cmp BYTE PTR cs:[si],'l'
	jne @F
	mov d_longarg,1
	inc si
@@:
	lodsb cs:[si]
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
	mov ax,ss:[edi]
	add edi,2
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
	mov ax,ss:[edi]
	add edi,2
	sub dx,dx
	cmp cx,0		;signed or unsigned?
	jge @F
	cwd
@@:
	cmp d_longarg,0
	je @F
	mov dx,ss:[edi]
	add edi,2
@@:
	lea ebx, d_szTmp

	push dx
	push ax
	pop eax
;	invoke ltob, eax, bx, cx
	call ltob
	mov esi,eax
	.while byte ptr ss:[esi]
		lodsb ss:[esi]
		call handle_char
	.endw
	retn

handle_s:
	mov si,ss:[edi]
	add edi,2

output_string:	;display string at ds:si
	mov ax,si
	mov bx,d_size
	.while byte ptr cs:[si]
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

	.while byte ptr cs:[si]
		lodsb cs:[si]
		call handle_char
	.endw

	.while sword ptr bx > 0
		mov al, d_fill
		call handle_char
		dec bx
	.endw
	retn

dprintf ENDP

d_esp     equ <>
d_ret     equ <>
d_fmt     equ <>
d_args    equ <>
d_size    equ <>
d_flag    equ <>
d_longarg equ <>
d_fill    equ <>
d_szTmp   equ <>

