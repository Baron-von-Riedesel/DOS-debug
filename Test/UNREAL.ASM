
;--- test unreal mode and
;--- DX command of debugxu.com

    .model small
    .dosseg
    option casemap:none
    .stack 5120

DGROUP group _TEXT	;makes a tiny model

CStr macro text:vararg
local sym
    .const
sym db text,0
    .code
    exitm <offset sym>
endm

    .data

SEL_FLAT   equ 1*8
SEL_DATA16 equ 2*8

GDT dq 0                    ; null descriptor
    dw 0FFFFh,0,9200h,0CFh  ; 32-bit flat data descriptor
    dw 0FFFFh,0,9200h,0h    ; 16-bit data descriptor

GDTR label fword        ; Global Descriptors Table Register
    dw 3*8-1            ; limit of GDT (size minus one)
    dd 0                ; linear address of GDT

    .code

    .386
    assume DS:DGROUP

myint0d1 proc
    push cs
    pop ds
    mov dx,CStr(<"unexpected exception occured",13,10,'$'>)
    mov ah,9
    int 21h
    add sp,4
    popf
    jmp continue1
myint0d1 endp

myint0d2 proc
    push cs
    pop ds
    mov dx,CStr(<"expected exception occured",13,10,'$'>)
    mov ah,9
    int 21h
    add sp,4
    popf
    jmp continue2
myint0d2 endp

;--- 16bit start/exit code

start16 proc

    push cs
    pop ds
    mov ax,ss
    mov dx,es
    sub ax,dx
    mov bx,sp
    shr bx,4
    add bx,ax
    mov ax,bx
    sub ax,10h
    shl ax,4
    push ds
    pop ss
    mov sp,ax       ; make a TINY model, CS=SS=DS
    mov ah,4Ah
    int 21h         ; free unused memory

    smsw ax
    test ax,1
    jz @F
    mov dx,CStr(<"will run in real-mode only",13,10,'$'>)
    mov ah,9
    int 21h
    jmp exit
@@:
    mov ax,ds
    movzx eax,ax
    shl eax,4
    add eax,offset GDT
    mov dword ptr [GDTR+2], eax ; convert offset to linear address

    xor ax,ax
    mov es,ax
    mov edi,es:[0dh*4]

    int 3
    call EnableUnreal

    mov ax,cs
    shl eax,16
    mov ax,offset myint0d1
    mov es:[0dh*4],eax


    xor ax,ax
    mov ds,ax
    mov ecx,100000h
    mov ax,ds:[ecx]
continue1::
    push cs
    pop ds
    call DisableUnreal

    mov ax,cs
    shl eax,16
    mov ax,offset myint0d2
    mov es:[0dh*4],eax

    xor ax,ax
    mov ds,ax
    mov ecx,100000h
    mov ax,ds:[ecx]
continue2::
    mov es:[0dh*4],edi
    push cs
    pop ds
exit:
    mov ax,4c00h
    int 21h
start16 endp

    .386p

EnableUnreal proc
    cli
    push ds
    lgdt [GDTR]
    mov eax,cr0
    or al,1
    mov cr0,eax
    jmp @F
@@:
    mov bx,ds
    mov bx,SEL_FLAT
    mov ds,bx
    and al,0FEh
    mov cr0,eax
    jmp @F
@@:
    pop ds
    sti
    ret
EnableUnreal endp

DisableUnreal proc
    cli
    lgdt cs:[GDTR]
    push ds
    mov eax,cr0
    inc ax
    mov cr0,eax
    jmp @F
@@:
    mov bx,SEL_DATA16
    mov ds,bx
    dec ax
    mov cr0,eax
    jmp @F
@@:
    pop ds
    sti
    ret
DisableUnreal endp

    end start16
