
;--- DPMIBK32.ASM: 32bit DPMI application written in MASM syntax.
;--- this sample temporarily switches back to real-mode.
;--- assemble: JWasm -mz dpmibk32.asm

LF  equ 10
CR  equ 13

    .386
    .model small

    .dosseg     ;this ensures that stack segment is last

    .stack 1024

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

    .data

szWelcome db "welcome in protected-mode",CR,LF,0
szBackinPM db "back in protected-mode",CR,LF,0

    .code

start:
    push eax
    mov esi, offset szWelcome
    call printstring
    pop ebx

;--- switch back to real-mode

    sub esp, sizeof RMCS+2
    mov ebp,esp
    xor eax, eax
    mov [ebp].RMCS.rIP, offset backtoreal
    mov [ebp].RMCS.rCS, _TEXT16
    mov [ebp].RMCS.rFlags, ax
    mov [ebp].RMCS.rDS, ax
    mov [ebp].RMCS.rES, ax
    mov [ebp].RMCS.rFS, ax
    mov [ebp].RMCS.rGS, ax
    lea eax,[ebp-20h]
    mov [ebp].RMCS.rSP, ax
    mov [ebp].RMCS.rSS, bx
    xor bx,bx
    xor cx,cx
    mov edi,ebp
    push ss
    pop es
    mov ax,0301h	;temporarily switch to real-mode
    int 31h

    mov esi, offset szBackinPM
    call printstring
    mov ax, 4C00h   ;normal client exit
    int 21h

;--- print a string in protected-mode with simple
;--- DOS commands not using pointers.

printstring:
    lodsb
    and al,al
    jz stringdone
    mov dl,al
    mov ah,2
    int 21h
    jmp printstring
stringdone:
    ret

;--- now comes the 16bit initialization part

_TEXT16 segment use16 word public 'CODE'

backtoreal:
    push cs
    pop ds
    mov dx,offset dBackinRM
    mov ah,9
    int 21h
    retf            ;back to protected-mode


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

;--- create a 32bit code selector and jump to 32bit code

    push bx     ;save stack segment
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
    pop ax      ;store stack segment in AX
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
dBackinRM db "switched to real-mode",CR,LF,'$'

_TEXT16 ends

    end start16
