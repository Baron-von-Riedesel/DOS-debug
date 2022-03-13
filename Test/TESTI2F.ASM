
;--- testi2f
;--- calls int 2fh, ax=1680h in protected-mode in an "endless" loop.
;--- assemble: JWasm -mz testi2f.asm

LF  equ 10
CR  equ 13

    .model small
    .386

    .dosseg     ;this ensures that stack segment is last

    .stack 1024

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

    .data

    .code


start16:
    mov ax,ss
    mov cx,es
    sub ax, cx
    mov bx, sp
    shr bx, 4
    inc bx
    add bx, ax
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
    mov ax, DGROUP
    mov ds, ax
    mov bx, ss
    mov bp, sp
    mov ax, 0001        ;start a 32-bit client
    call far ptr [bp]   ;initial switch to protected-mode
    jc initfailed

;--- now in protected-mode

    sub sp, sizeof RMCS+2
    movzx ebp, sp
    push ss
    pop es
@@:
    xor eax, eax
    mov [bp].RMCS.rSP, ax
    mov [bp].RMCS.rSS, ax
    mov word ptr [bp].RMCS.rFlags, 203h
    mov word ptr [bp].RMCS.rEAX, 1680h
    mov bx, 002Fh
    xor cx,cx
    mov edi,ebp
    mov ax,0300h    ;temporarily switch to real-mode
    int 31h
    mov ah,02
    mov dl,'.'
    int 21h
    jmp @B

    mov ax,4c00h
    int 21h

nohost:
    mov dx, offset dErr1
    jmp error
nomem:
    mov dx, offset dErr2
    jmp error
initfailed:
    mov dx, offset dErr3
error:
    push cs
    pop ds
    mov ah, 9
    int 21h
    mov ax, 4C00h
    int 21h

dErr1 db "no DPMI host installed",CR,LF,'$'
dErr2 db "not enough DOS memory for initialisation",CR,LF,'$'
dErr3 db "DPMI initialisation failed",CR,LF,'$'
dBackinRM db "switched to real-mode",CR,LF,'$'

_TEXT16 ends

    end start16
