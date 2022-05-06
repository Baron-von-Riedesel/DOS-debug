
;--- test LEAVE instruction in protected-mode

;--- the leave instruction may cause stack exceptions
;--- if 16-bit code runs as 32-bit DPMI client.

    .286
    .MODEL small
    option casemap:none
    .dosseg
    .stack 2048

    .code

;--- little procedure that does a 16-bit multiplication, result returned in DX:AX.
;--- problem is that the ret instruction may cause the assembler to add a LEAVE
;--- instruction, and there's also a slight incompatibility if jwasm is used
;--- without option -Zg:
;---
;---           .286   .386  .486  .586
;--------------------------------------
;--- Masm        y      n     n     y      ( y = LEAVE generated )
;--- JWasm       y      y     n     n
;--- JWasm(-Zg)  y      n     n     y

mul16 proc c p1:word, p2:word
    mov ax,p1
    mul p2
    ret
mul16 endp

    .386

main proc c

    mov ebp, 12345678h   ; if hiword(ebp) is != 0, LEAVE will cause a stack exception
;    mov ebp, 5678h      ; if hiword(ebp) == 0,  program runs without problems
    invoke mul16, 2, 2
    ret
main endp

start proc c public

;--- setup small memory model

    cld
    mov dx, @data
    mov ds, dx
    mov ax, ss
    sub ax, dx
    shl ax, 4
    mov ss, dx
    add sp, ax

;--- now ds=ss=dgroup

    mov bx, sp
    shr bx, 4
    mov cx, es
    mov ax, ss
    sub ax, cx
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
    mov bp, sp
    mov ax, 1            ;start a 16-bit client
    call far ptr [bp]
    jc initfailed
    add sp,4
    call main
    mov ah, 4Ch
    int 21h
nohost:
    call error
    db "no DPMI host installed",13,10,'$'
nomem:
    call error
    db "not enough DOS memory for initialisation",13,10,'$'
initfailed:
    call error
    db "DPMI initialisation failed",13,10,'$'
error:
    push cs
    pop ds
    pop dx
    mov ah, 9
    int 21h
    mov ax, 4C00h
    int 21h

start endp

    END start

