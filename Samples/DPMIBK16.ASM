
;--- DPMIBK16.ASM: 16bit DPMI application written in MASM syntax.
;--- this sample temporarily switches back to real-mode.
;--- assemble: JWasm -bin -Fo dpmibk16.com dpmibk16.asm

LF  equ 10
CR  equ 13

    .286
    .model tiny

;--- DPMI real-mode call structure

RMCS struct
rEDI    dd ?
rESI    dd ?
rEBP    dd ?
        dd ?
rEBX    dd ?
rEDX    dd ?
rECX    dd ?
rEAX    dd ?
rFlags  dw ?
rES     dw ?
rDS     dw ?
rFS     dw ?
rGS     dw ?
rIP     dw ?
rCS     dw ?
rSP     dw ?
rSS     dw ?
RMCS ends

    .code

    org 100h

;--- the 16bit initialization part

start:
    pop ax          ;get word saved on stack for COM files
    mov bx, sp
    shr bx, 4
    jnz @F
    mov bx,1000h    ;it was a full 64kB stack
@@:
    mov ah, 4Ah     ;free unused memory
    int 21h
    mov ax, 1687h   ;DPMI host installed?
    int 2Fh
    and ax, ax
    jnz nohost
    push es         ;save DPMI entry address
    push di
    and si, si      ;requires host client-specific DOS memory?
    jz nomemneeded
    mov bx, si
    mov ah, 48h     ;alloc DOS memory
    int 21h
    jc nomem
    mov es, ax
nomemneeded:
    mov bp, sp
    mov bx, cs      ;save real-mode value of CS in BX
    mov ax, 0000    ;start a 16-bit client
    call far ptr [bp]   ;initial switch to protected-mode
    jnc initok
    call error
    db "DPMI initialisation failed",CR,LF,'$'
nohost:
    call error
    db "no DPMI host installed",CR,LF,'$'
nomem:
    call error
    db "not enough DOS memory for initialisation",CR,LF,'$'
error:
    push cs
    pop ds
    pop dx
    mov ah, 9
    int 21h
    mov ax, 4C00h
    int 21h

;--- now in protected-mode

initok:
    push bx
    call printstring
    db "welcome in protected-mode",CR,LF,0
    pop bx

;--- switch back to real-mode

    sub sp, sizeof RMCS
    mov bp,sp
    mov [bp].RMCS.rIP, offset backinreal
    mov [bp].RMCS.rCS, bx
    xor ax, ax
    mov [bp].RMCS.rFlags, ax
    mov [bp].RMCS.rDS, ax
    mov [bp].RMCS.rES, ax
    lea ax,[bp-20h]
    mov [bp].RMCS.rSP, ax
    mov [bp].RMCS.rSS, bx
    xor bx,bx
    xor cx,cx
    mov di,bp
    push ss
    pop es
    mov ax,0301h	;temporarily switch to real-mode
    int 31h

    call printstring
    db "back in protected-mode",CR,LF,0
    mov ax, 4C00h   ;normal client exit
    int 21h

backinreal:
    push cs
    pop ds
    call printstring
    db "switched to real-mode",CR,LF,0
    retf            ;back to protected-mode

;--- print a string in both protected-mode and real-mode.
;--- uses simple DOS commands without pointers.

printstring:
    pop si
nextchar:
    lodsb
    and al,al
    jz stringdone
    mov dl,al
    mov ah,2
    int 21h
    jmp nextchar
stringdone:
    push si
    ret

    end start
