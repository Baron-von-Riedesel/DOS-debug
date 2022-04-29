
;--- test debugx's qq cmd ( new since v1.29 ).

;--- this little test program is buggy.
;--- it intercepts int 21h in protected-mode, and
;--- firmly assumes that register DS holds a selector
;--- for DGROUP when an int 21h is called. After DS is set to NULL,
;--- a 'q' command inside DEBUGX fails, protected-mode cannot be left.
;--- since v1.29 there's now a "qq" command, which resets pm int 21h.
;--- "qq" will terminate the debuggee, and debugx's real-mode prompt '-'
;--- should appear.

    .286
    .MODEL small
    option casemap:none
    .dosseg
    .stack 2048
    .386

    .data

oldint21 dd 0

    .code

;--- the client's int 21h routine
;--- if firmly assumes that register ds holds selector for dgroup!

myint21 proc
    cmp ah, 9
    jz is09
    jmp [oldint21]
is09:
    pushd 0       ; set SS:SP to 0:0
    sub sp, 2*2   ; skip CS:IP
    push 0        ; gs
    push 0        ; fs
    push @data    ; ds=real-mode DGROUP
    push @data    ; es=real-mode DGROUP
    pushf
    pushad
    mov di, sp    ; now ss:sp -> DPMI RMCS
    push ss
    pop es
    mov bx, 0021h
    xor cx, cx
    mov ax, 0300h
    int 31h
    popad
    popf
    add sp, 8*2
    iret

myint21 endp

main proc c

    .const
string1 db "hello, debugx",13,10,'$'
    .code

    mov dx, offset string1
    mov ah, 9
    int 21h
    push 0     ; now set DS != DGROUP; makes calling int 21h "impossible"
    pop ds
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
    mov ax, 0000    ;start a 16-bit client
    call far ptr [bp]
    jc initfailed

;--- intercept protected-mode int 21h

    mov bl,21h
    mov ax,0204h
    int 31h
    mov word ptr [oldint21+0],dx
    mov word ptr [oldint21+2],cx
    mov cx, cs
    mov dx, offset myint21
    mov al,5
    int 31h
    call main
    mov ax, 4C00h
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

