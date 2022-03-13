
;--- HUGESEG.ASM: 32bit DPMI application.
;--- assemble: JWasm -mz hugeseg.asm
;--- this sample is to test debugx's correct handling of 32-bit offsets
;--- for the a/c/d/e/m/s/u commands.

LF  equ 10
CR  equ 13

MEMSIZE equ 200000h

    .386
    .model small

    .dosseg     ;this ensures that stack segment is last

    .stack 1024

    .data

    .code

start:
    mov bx, highword MEMSIZE
    mov cx, lowword MEMSIZE
    mov ax, 501h    ;allocate a 128 kb block
    int 31h
    jc errx
;--- bx:cx contains the address of the block
    push bx
    push cx
    mov cx,1
    mov ax,0        ;allocate a descriptor
    int 31h
    jc errx
    mov bx,ax
    pop dx
    pop cx
    mov ax,7        ;set base of descriptor
    int 31h
    jc errx
    mov cx,highword (MEMSIZE-1)
    mov dx,lowword (MEMSIZE-1)
    mov ax,8        ;set limit of descriptor
    int 31h
    jc errx
    mov ds,bx

;--- now we have DS=selector of a block (size MEMSIZE), still 16-bit default size

    int 3

;--- a bug in debugx <= v1.28 was that to accept offsets beyond 64k, the
;--- default size flag had to be set!

    lar ecx,ebx
    shr ecx,8
    or ch,40h       ;set default to 32-bit
    mov ax,9        ;set descriptor flags
    int 31h

;--- now DS=selector of a descriptor with default size 32-bit

    int 3

errx:
    mov ax, 4C00h   ;normal client exit
    int 21h

;--- now comes the 16bit initialization part

_TEXT16 segment use16 word public 'CODE'

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
    mov bp, sp
    mov ax, 0001        ;start a 32-bit client
    call far ptr [bp]   ;initial switch to protected-mode
    jc initfailed

;--- now in protected-mode

;--- create a 32bit code selector and jump to 32bit code

    mov cx,1
    mov ax,0
    int 31h
    mov bx,ax
    mov cx,_TEXT
    mov dx,cx
    shl dx,4
    shr cx,12
    mov ax,7
    int 31h     ;set base address
    mov dx,-1
    mov cx,0
    mov ax,8
    int 31h     ;set descriptor limit to 64 kB
    mov cx,cs
    lar cx,cx
    shr cx,8
    or ch,40h
    mov ax,9
    int 31h     ;set code descriptors attributes to 32bit
    push ebx
    push offset start
    retd        ;jump to 32-bit code

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

_TEXT16 ends

    end start16
