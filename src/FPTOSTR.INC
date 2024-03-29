
;--- defines procedures
;--- PowerOf10
;--- FloatToBCD
;--- FloatToStr

; These are bits in the FP status word.

FP_LESSTHAN	equ 01h
FP_EQUALTO	equ 40h

MAXNUM equ 16

CONST segment

;ten	dq 10.0
;ten16	dq 1.0e16
;rounder	dq 5.0e10

iexp = 1

ten_1 label tbyte
repeat 15
	dt @CatStr(1.0e,%iexp)
	iexp = iexp + 1
endm

ten_16 label tbyte
repeat 15
	dt @CatStr(1.0e,%iexp)
	iexp = iexp + 16
endm

;--- just the first exponent is necessary for 8-byte doubles

ten_256 label tbyte
repeat 19
	dt @CatStr(1.0e,%iexp)
	iexp = iexp + 256
endm

CONST ends

;--- called by FloatToStr
;--- in: ax=exponent
;--- modifies: bx, cl

PowerOf10 proc uses si

	push ax
	cmp ax, 0		;.IF (SWORD PTR ax < 0)
	jge @F
	neg ax
@@:
	fld1
	mov bl, al
	and bl, 0fh		;bits 0-3
	je @F
	mov si,offset ten_1
	call mul10
@@:
	mov bl, al
	mov cl, 4
	shr bl, cl		;bits 4-7
;	and bl, 0fh
	je @F
	mov si,offset ten_16
	call mul10
@@:
	mov bl, ah
	and bl, 1fh		;bits 8-12
	je @F
	mov si,offset ten_256
	call mul10
@@:
	pop ax
	cmp ax, 0		;.IF (SWORD PTR ax < 0)
	jge @F
	fdivp st(1), st
	ret
@@:
	fmulp st(1), st
	ret
mul10:
	dec bl
	push ax
	mov al,10		; sizeof TBYTE
	mul bl
	xchg bx,ax
	pop ax
	fld tbyte ptr [bx + si]
	fmulp st(1), st
	retn

PowerOf10 ENDP

; Convert a floating point register to ASCII.  For internal use.
; The result always has exactly 18 digits, with zero padding on the
; left if required.
;
; Entry: ST(0) = a number to convert, 0 <= ST(0) < 1E19.
;        DI = an 18-character buffer.
; modifies SI,DI,CX,AX

FloatToBCD PROC

if FLATSS
	sub esp, 12
	mov esi, esp
else
	sub sp, 12
	mov si, sp
endif

	; The fbstp instruction converts the top of the stack to a
	; packed BCD form in ten bytes, with two digits per byte.  The top 
	; byte has the sign, which we ignore.

if FLATSS
	fbstp [esp]
else
	fbstp [si]
endif

	; Now we need to unpack the BCD to ASCII.

if FLATSS
	add esi, 8
else
	add si, 8
endif
	mov cx, 9
@@:
if FLATSS
	mov al, ss:[esi]	; xxxx xxxx AAAA BBBB
	dec esi
else
	mov al, [si]		; xxxx xxxx AAAA BBBB
	dec si
endif
if 0
	rol ax, 12			; BBBB xxxx xxxx AAAA
	rol ah, 4			; xxxx BBBB xxxx AAAA
	and ax, 0f0fh		; 0000 BBBB 0000 AAAA
else
	db 0D4h,10h			; aam 16: 0000 AAAA 0000 BBBB
	xchg al,ah			; 0000 BBBB 0000 AAAA
endif
	add ax, 3030h
	stosw
	loop @B
if FLATSS
	add esp, 12
else
	add sp, 12
endif
	ret

FloatToBCD ENDP

;
; Convert a double precision number to a string.
;
; Entry:   SI=fpin   = 10-byte double to convert
;          DI=pszDbl = buffer to hold converted double
;
; Exit:    DI = behind converted double

FloatToStr PROC USES si

if FLATSS
_DATA segment
iExp dw 0
;mystat dw 0
;szTemp db 22 dup (0)
_DATA ends
else
LOCAL iExp: WORD
LOCAL mystat: WORD
;local szTemp[22]:BYTE
endif

;--- Special case zero has been filtered already (fxtract fails for zero).

;--- Check for a negative number.

	mov cl,[si+9]
	test cl, 80h
	jz @F
	and byte ptr [si+9], 07fh		; change to positive
	mov al,'-'						; store a minus sign
	stosb
@@:

;--- load our value onto the stack.

	fld tbyte ptr [si]
	fld st
	mov [si+9], cl	; restore fpin, must be preserved.

; Compute the closest power of 10 below the number.  We can't get an
; exact value because of rounding.  We could get close by adding in
; log10(mantissa), but it still wouldn't be exact.  Since we'll have to
; check the result anyway, it's silly to waste cycles worrying about
; the mantissa.
;
; The exponent is basically log2(fpin).  Those of you who remember
; algebra realize that log2(fpin) x log10(2) = log10(fpin), which is
; what we want.

	fxtract			; ST=> mantissa, exponent, fpin
	fstp st			; drop the mantissa
	fldlg2			; push log10(2)
	fmulp st(1), st	; ST = log10(fpin), fpin
	fistp iExp		; ST = fpin

;--- A 10-byte double can carry almost 19 digits, but fbstp only stores the
;--- guaranteed 18.  If you're doing 10-byte doubles, change the '16' to '18'.

	cmp iExp, 18
	jnc notbelow18
    
	fld st			; ST = fpin, fpin
	frndint			; ST = int(fpin), fpin
	fcomp st(1)		; ST = fpin, status set
if RING0
	fstsw ax
else
	fstsw mystat
	mov ax, mystat
endif
	test ah, FP_EQUALTO
	jz notequal

;--- We have an integer!  Lucky day.  Go convert it into a temp buffer.

	push di
;	lea di, szTemp
	call FloatToBCD
	pop di

	mov ax, MAXNUM+1
	mov cx, iExp
	sub ax, cx
	inc cx
;	lea si, szTemp
	mov si, di
	add si, ax

;--- The off-by-one order of magnitude problem below can hit us here.  
;--- We just trim off the possible leading zero.

	cmp byte ptr [si],'0'
	jnz @F
	inc si
	dec cx
@@:

;--- Copy the rest of the converted BCD value to our buffer.

	rep movsb
	jmp ftsExit

notequal:
notbelow18:

;--- Have fbstp round to 17 places.

	mov ax, MAXNUM
	sub ax, iExp		; adjust exponent to 17
	call PowerOf10

; Either we have exactly 17 digits, or we have exactly 16 digits.  We can
; detect that condition and adjust now.

	fcom qword ptr [ten_16]
    ; x0xxxx00 means top of stack > ten16
    ; x0xxxx01 means top of stack < ten16
    ; x1xxxx00 means top of stack = ten16
if RING0
	fstsw ax
else
	fstsw mystat
	mov ax, mystat
endif
	test ah,1
	jz @F
	fmul qword ptr [ten_1]
	dec iExp
@@:

;--- Go convert to BCD.

	push di
	lea  di, [di+8]
	call FloatToBCD
	pop di

;	lea si, [szTemp+1]		; point to converted buffer
	lea si, [di+8+1]		; point to converted buffer

;--- If the exponent is between -15 and 16, we should express this as a number
;--- without scientific notation.

	mov cx, [iExp]
	push cx
	add cx,MAXNUM-1
	cmp cx,MAXNUM*2-1
	pop cx
	ja fts6		;if scientific notation

; If the exponent is less than zero, we insert '0.', then -ecx
; leading zeros, then 16 digits of mantissa.  If the exponent is
; positive, we copy ecx+1 digits, then a decimal point (maybe), then 
; the remaining 16-ecx digits.

	inc cx
	cmp cx, 0
	jg @F
	mov ax,'.0'
	stosw
	neg cx
	mov al, '0'
	rep stosb
	mov cx, MAXNUM
	jmp fts3
@@:
	rep movsb
	mov al,'.'
	stosb
	mov cx, MAXNUM
	sub cx, [iExp]
fts3:
	rep movsb

;--- Trim off trailing zeros.

@@:
	cmp byte ptr [di-1],'0'
	jnz @F
	dec di
	jmp @B
@@:

;--- If we cleared out all the decimal digits, kill the decimal point, too.

	cmp byte ptr [di-1], '.'
	jnz @F
	dec di
@@:    

;--- That's it.

	jmp ftsExit
fts6:
; Now convert this to a standard, usable format.  If needed, a minus
; sign is already present in the outgoing buffer, and di already points
; past it.

	movsb				; copy the first digit
	mov al,'.'
	stosb				; plop in a decimal point
	movsw				; copy four more digits
	movsw
	movsw				; copy two more digits

if 0

; The printf %g specified trims off trailing zeros here.  I dislike
; this, so I've disabled it.  Comment out the if 0 and endif if you
; want this.

@@:
	cmp byte ptr [di-1],'0'
	jz @F
	dec di
	jmp @B
@@:
endif

;--- Shove in the exponent.  If you support 10-byte reals, remember to
;--- allow 4 digits for the exponent.

	mov ax,'+e'
	mov dx, [iExp]
	and dx, dx
	jns @F
	neg dx
	mov ah,'-'
@@:
	stosw

	xchg ax,dx
	mov si, 10
	mov cx,4
@@:
	xor dx, dx
	div si
	push dx
	loop @B
	mov cl,4
@@:
	pop ax
	add al,'0'
	stosb
	loop @B

;	add di, 4	; point to terminator

ftsExit:
	ret

FloatToStr ENDP

