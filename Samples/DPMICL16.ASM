
;--- DPMICL16.ASM: 16bit DPMI application written in MASM syntax.
;--- assemble: JWasm -bin -Fo dpmicl16.com dpmicl16.asm

LF  equ 10
CR  equ 13

    .286
    .model tiny

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
    mov ax, 0000    ;start a 16-bit client
    call far ptr [bp]   ;initial switch to protected-mode
    jc initfailed

;--- now in protected-mode

    call printstring
    db "welcome in protected-mode",CR,LF,0
    mov ax, 4C00h   ;normal client exit
    int 21h

nohost:
    call error
    db "no DPMI host installed",CR,LF,'$'
nomem:
    call error
    db "not enough DOS memory for initialisation",CR,LF,'$'
initfailed:
    call error
    db "DPMI initialisation failed",CR,LF,'$'
error:
    push cs
    pop ds
    pop dx
    mov ah, 9
    int 21h
    mov ax, 4C00h
    int 21h

;--- print a string in protected-mode with simple
;--- DOS commands not using pointers.

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
