
;   Here is the start of the disassembly part of the program.

;--- flag bits preflags/preused

PRESEG	equ 1		;segment prefix
PREREP	equ 2		;rep prefixes
PREREPZ	equ 4		;f3, not f2
PRELOCK	equ 8		;lock prefix
PRE32D	equ 10h		;flag for operand size (66h)
PRE32A	equ 20h		;flag for address size (67h)
PREWAIT	equ 40h		;prefix wait (not really a prefix)
GOTREGM	equ 80h		;preused only: set if we have the reg/mem part

;--- equates for disflags:

DIS_F_REPT		equ 1	;repeat after pop ss, etc.
DIS_F_SHOW		equ 2	;show memory contents
DIS_I_SHOW		equ 4	;there are memory contents to show
DIS_I_UNUSED	equ 8	;(internal) print " (unused)"
DIS_I_SHOWSIZ	equ 10h	;(internal) always show the operand size
DIS_I_KNOWSIZ	equ 20h	;(internal) we know the operand size of instr.
DIS_I_MEMACC	equ 80h	;(internal) we're just accessing a mem ref ( dumpreg )

;--- define "general purpose register"
DefGPR macro regist
REG_&regist& equ ($ - rgnam816)/2
	db "&regist&"
endm

;--- register table
;---  0- 7: 8-bit registers
;---  8-15: 16-bit registers
;--- 16-23: 32-bit registers

REG_NO_GPR	equ 24

;--- define "segment register"
DefSR macro regist
REG_&regist& equ REG_NO_GPR + ($ - segrgnam)/2
	db "&regist&"
endm

_DATA segment

dis_n	dw 0		;number of bytes in instruction so far
		dw 0		;must follow dis_n (will always remain 0)
idxins	dw 0		;index of the instruction (unsqueezed)
addrr	dw 0		;address in mod r/m byte (16bit only)
sizeloc dw 0		;address of size words in output line

;--- preflags and preused must be consecutive
preflags db 0		;flags for prefixes found so far
preused  db 0		;flags for prefixes used so far

bInstr	db 0		;the main instruction byte
rmsize	db 0		;<0 or 0 or >0 means mod r/m is 8 or 16 or 32
segmnt	db 0		;segment determined by prefix (or otherwise)
disflags db 0		;flags for the disassembler
disflags2 db 0		;another copy of DIS_I_KNOWSIZ

_DATA ends

CONST segment

;--- table of obsolete-instruction values.
;--- instructions are FENI, FDISI, FSETPM, MOV to/from TRx
obsinst	dw SFPGROUP3, SFPGROUP3+1, SFPGROUP3+4
		dw SPARSE_BASE+24h, SPARSE_BASE+26h

;--- Table for 16-bit mod r/m addressing.  8 = BX, 4 = BP, 2 = SI, 1 = DI.

rmtab	db 8+2, 8+1, 4+2, 4+1, 2, 1, 4, 8

;--- Tables of register names.
;--- rgnam816/rgnam16/segrgnam must be consecutive.
;--- also used by the line assembler

rgnam816 label word
	DefGPR AL
	DefGPR CL
	DefGPR DL
	DefGPR BL
	DefGPR AH
	DefGPR CH
	DefGPR DH
	DefGPR BH
rgnam16 label word
	DefGPR AX
	DefGPR CX
	DefGPR DX
	DefGPR BX
	DefGPR SP
	DefGPR BP
	DefGPR SI
	DefGPR DI
N_REGS16 equ ( $ - rgnam16 ) / 2
segrgnam label word
	DefSR ES
	DefSR CS
	DefSR SS
	DefSR DS
	DefSR FS
	DefSR GS
N_SEGREGS equ ( $ - segrgnam ) / 2
	DefSR ST
	DefSR MM
	DefSR CR
	DefSR DR
	DefSR TR
N_ALLREGS equ ( $ - rgnam816 ) / 2

;--- address of debuggee's segment registers
;--- used to display memory contents ( DIS_F_SHOW )
segrgaddr dw regs.rES,regs.rCS,regs.rSS,regs.rDS
if RING0	; for DebugR, we also display FS/GS contents
	dw regs.rFS, regs.rGS
endif

;--- Tables for handling of named prefixes.

prefixlist	db 26h,2eh,36h,3eh,64h,65h	;segment prefixes (in order)
			db 9bh,0f0h,0f2h,0f3h		;WAIT,LOCK,REPNE,REPE
N_PREFIX equ $ - prefixlist
prefixmnem	dw MN_WAIT,MN_LOCK,MN_REPNE,MN_REPE

CONST ends

disasm1:				;<--- standard entry
	mov al, 0

disasm proc				;<--- entry with AL=disflags ( DIS_F_REPT & DIS_F_SHOW )

	mov [disflags], al

CONST segment	; must be located inside disasm since local labels are used here

	align 2

;   Jump table for OP_IMM, OP_RM, OP_M, OP_R_MOD, OP_MOFFS, OP_R, OP_R_ADD,
;   and OP_AX.
;   See orders of asm_jmp1 and bittab.

dis_jmp1 label word
	dw dop_imm, dop_rm, dop_m, dop_r_mod
	dw dop_moffs, dop_r, dop_r_add, dop_ax

;   jump table for displaying operands
;   See orders of asm_jmp1 and bittab.

dis_optab label word
	dw dop_m64, dop_mfloat, dop_mdouble, dop_m80, dop_mxx,  dop_farmem	;00-05
	dw dop_farimm, dop_rel8, dop_rel1632								;06-08
	dw dop_st1, dop_sti,     dop_cr										;09-11
	dw dop_dr,   dop_tr,     dop_segreg,  dop_imms8						;12-15
	dw dop_imm8, dop_mmx,    dop_shosiz									;16-18
;--- string items OP_1 .. OP_SS
	db '1',0	;19
	db '3',0	;20
	db 'DX'		;21
	db 'CL'		;22
	db 'ST'		;23
	db 'CS','DS','ES','FS','GS','SS'	;24-29

;--- Jump table for a certain place.
;--- the size of this table matches OPTYPES_BASE

dis_jmp2 label word
	dw disbad		;illegal instruction
	dw da_twobyte	;two byte instruction (0F xx)
	dw da_insgrp	;instruction group
	dw da_fpuins	;coprocessor instruction
	dw da_fpugrp	;coprocessor instruction group
	dw da_insprf	;instruction prefix (including 66h/67h)
OPTYPES_BASE equ $ - dis_jmp2

CONST ends

if FLATSS
	.386
;	mov [savesp2],esp
	mov [run_sp],esp
else
;	mov [savesp2],sp
	mov [run_sp],sp
endif
	xor ax,ax
	mov [dis_n],ax
	mov word ptr [preflags],ax	;clear preflags and preused
if ?PM
	mov bx,[u_addr+4]
	call getseldefsize
	mov [bCSAttr],al
endif
	mov [segmnt],3			;initially use DS segment
	mov [rmsize],80h		;signed byte (-128): don't display any memory
	mov word ptr [ai.dismach],0;no special machine needed, so far
	call disgetbyte			;get a byte of the instruction
	cmp al,9bh				;wait instruction (must be the first prefix)
	jne da2					;if not

;   The wait instruction is actually a separate instruction as far as
;   the x86 is concerned, but we treat it as a prefix since there are
;   some mnemonics that incorporate it.  But it has to be treated specially
;   since you can't do, e.g., seg cs wait ... but must do wait seg cs ...
;   instead.  We'll catch it later if the wait instruction is not going to
;   be part of a shared mnemonic.

	or [preflags],PREWAIT

;   If we've found a prefix, we return here for the actual instruction
;   (or another prefix).

da1:
	call disgetbyte
da2:
	mov [bInstr],al	;save away the instruction
	mov ah,0

;--- Now we have the sequence number of the instruction in AX.  Look it up.

da3:
	mov bx,ax
	mov [idxins],ax	;save the compressed index
	cmp ax,SPARSE_BASE
	jb @F			;if it's not from the squeezed part of the table
	mov bl,[sqztab+bx-SPARSE_BASE]
	mov bh,0
	add bx,SPARSE_BASE	;bx = compressed index
@@:
	mov cl,[optypes+bx]	;cx = opcode type
	mov ch,0
	shl bx,1
	mov bx,[opinfo+bx]	;bx = other info (mnemonic if a true instruction)
	mov si,cx
	mov ax,bx
	mov cl,12
	shr ax,cl
	cmp al,[ai.dismach]
	jb @F				;if a higher machine is already required
	mov [ai.dismach],al	;set machine type
@@:
	and bh,0fh			;=and bx,0fffh - remove the machine field
	cmp si,OPTYPES_BASE
	jae da13pre			;if this is an actual instruction
	call [dis_jmp2+si]	;otherwise, do more specific processing
	jmp da3				;back for more

;--- dis_jmp2[1]: Two-byte instruction 0F xx: index 1E0-2DF.

da_twobyte:
	call disgetbyte
	mov [bInstr],al
	mov ah,0
	add ax,SPARSE_BASE
	ret

;--- dis_jmp2[2]: Instruction group.
;--- BX contains "instruction base": 100h, 110h, ...

da_insgrp:
	call getregmem_r	;get the middle 3 bits of the R/M byte
	cbw
	add ax,bx			;offset
	ret

;--- dis_jmp2[3]: Coprocessor instruction.
;--- BX contains "instruction base": 148h, 158h, ...

da_fpuins:
	or [disflags], DIS_I_SHOWSIZ
	or [ai.dmflags], DM_COPR
	call getregmem
	cmp al,0c0h
	jb da_insgrp	;range 00-bfh is same as an instruction group
	mov cl,3
	shr al,cl		;C0-FF --> 18-1F
	sub al,18h-8	;18-1F --> 08-0F
	cbw
	add ax,bx		;offset
	ret

;--- dis_jmp2[4]: Coprocessor instruction group.
;--- BX contains "instruction base": 1C8h, 1D0h, 1D8h

da_fpugrp:
	mov al,[ai.regmem]
	and al,7
	cbw
	add ax,bx
	ret

;--- dis_jmp2[5]: Instruction prefix.  At this point, bl = prefix bits; bh = segment

da_insprf:
if 0	; v2.01: removed - opsize/adrsize prefixes "toggle" just once
	mov al,bl
	and bl,not (PRE32D or PRE32A)	;these flags are XORed!
endif
	test bl,[preflags]
	jnz disbad0		;if there are duplicates
	or [preflags],bl
	test bl,PRESEG
	jz @F			;if not a segment
	mov [segmnt],bh	;save the segment
@@:
	pop ax			;discard return address
	jmp da1

disbad0:
	jmp disbad		;we don't allow duplicate prefixes


da13pre::

if ?PM ; v2.01: update opsize/adrsize prefixes if D bit set AFTER prefixes have been read
	test [bCSAttr], CS32
	jz @F
	xor [preflags], PRE32D or PRE32A
@@:
endif

;   OK.  Here we go.  This is an actual instruction.
;   BX=offset of mnemonic in mnlist
;   SI=offset of operand list in oplists
;   First print the op mnemonic.

da13:
	push si
	lea si,[mnlist+bx]	;offset of mnemonic
	cmp si,offset mnlist+MN_BSWAP
	jne @F				;if not BSWAP
	call dischk32d
	jz disbad0			;if no operand-size prefix
@@:
	call showop			;print out the op code (at line_out+28)
	mov [sizeloc],0		;clear out this flag
	pop si				;recover list of operands
	add si,offset oplists - OPTYPES_BASE
	cmp byte ptr [si],0
	je da21				;if we're done

;   Loop over operands.  si -> operand type.
;   Fortunately the operands appear in the instruction in the same
;   order as they appear in the disassembly output.

da14:
	mov [disflags2],0		;clear out size-related flags
	lodsb					;get the operand type
	cmp al,OP_SIZE
	jb da18					;if it's not size dependent
	mov [disflags2],DIS_I_KNOWSIZ	;indicate variable size
	cmp al,OP_8
	jae da16				;if the size is fixed (8,16,32,64)
	cmp al,OP_1632
	jae da15				;if word or dword
	mov ah,-1
	test [bInstr],1
	jz da17					;if byte
da15:
	or [preused], PRE32D	;mark this flag as used
	mov ah,[preflags]
	and ah, PRE32D			;this will be 10h for dword, 00h for word
	jmp da17				;done

da16:
	mov ah,al		;OP_8, OP_16, OP_32 or OP_64 (we know which)
	and ah,0f0h		;this converts ah to <0 for byte, =0 for word,
	sub ah,OP_16	;and >0 for dword (byte=F0,word=0,dword=10,qword=20)

;--- Now we know the size (in ah); branch off to do the operand itself.

da17:
	mov bl,al
	and bx,0eh			;8 entries (IMM, RM, M, R_MOD, M_OFFS, R, R_ADD, AX)
	call [dis_jmp1+bx]	;print out the operand
	jmp da20			;done with operand

;--- Sizeless operands.

da18:
	cbw
	cmp al, OP_STR
	xchg ax,bx			; mov bx, ax
	mov ax,[dis_optab+bx-2]
	jb @F				;if it's not a string
	stosw
	cmp ah,0
	jnz da20			;if it's two characters
	dec di
	jmp da20			;done with operand
@@:
	call ax				;otherwise, do something else

;--- operand done, check if there's another one

da20:
	cmp byte ptr [si],0
	jz da21				;if we're done
	mov al,','
	stosb
	jmp da14			;another operand

;--- all operands done.

;-------------------------------------------------------------------
;--- now check and loop for unused prefixes:
;--- OPSIZE (66h), ADDRSIZE (67h), WAIT, segment, REP[N][Z], LOCK

;--- v2.03: the string instructions may have both 66h & 67h prefixes.
;--- a 67h prefix will now be shown as a comment behind the opcode.
;--- this code has been reworked.

CONST segment

txflags label byte
	db PREWAIT			; a WAIT prefix hanging
	db PRE32D			; opsize 66h
	db PRE32A			; adrsize 67h
	db PRESEG
	db PREREP or PREREPZ
	db PRELOCK

txsize label byte	; items in txtabs tables
	db N_WTAB
	db N_LTABO
	db N_LTABA
	db N_PRFXTAB
	db N_REPNC
	db N_LOCK

txtabs label word
	dw offset wtab1
	dw offset ltabo1
	dw offset ltaba1
	dw offset prfxtab
	dw offset replist
	dw offset locktab

txprocs label word
	dw hdl_wait
	dw hdl_d32
	dw hdl_a32
	dw hdl_seg
	dw hdl_rep
	dw hdl_lock

strinstr label byte
	db 6ch,6dh,6eh,6fh		; ins, outs
	db 0A4h,0A5h,0A6h,0A7h	; movs, cmps, lods, scas, stos
	db 0AAh,0ABh,0ACh,0ADh,0AEh,0AFh
szA32 db ";A32"
if ?PM
szA16 db ";A16"
endif
CONST ends

;--- preflags:
;--- CS 16-bit: if PRE32x == 1, a prefix has been found.
;--- + PRE32D == 0: nothing done
;--- + PRE32D == 1: CS=32: scan opc table, fnd: switch opcode, notfnd:bad prefix
;--- + PRE32A == 0: nothing done
;--- + PRE32A == 1: CS=32, scan opc table, fnd: switch opcode, notfnd: check str instr
;--- CS 32-bit: if PRE32x == 1, no prefix has been found.
;--- + PRE32D == 0, CS=16: scan opc table, fnd: exit, notfnd: bad prefix
;--- + PRE32D == 1, CS=32: scan opc table, fnd: switch opcodes, notfnd: exit
;--- + PRE32A == 0, CS=16: scan opc table, fnd: exit, notfnd: check str instr
;--- + PRE32A == 1, CS=32: scan opc table, fnd: switch opcodes, notfnd: check str instr

;--- note: a prefix might be marked as "used" already. In this case it must be skipped!

;--- di=current output in line_out
;--- may be changed by the prefix loop if a prefix has to be inserted.

da21:
;	@dprintf "da21, di=%X", di
	xor bx, bx
nextflag:
	mov ax, word ptr [preflags]	; ah=preused
if ?PM
	test [bCSAttr], CS32
	jz @F
;--- if CS is 32bit, checks for A32 must be done in any case.
;--- to detect unused 66h prefixes, PRE32D is to be set as well.
	or al, PRE32A or PRE32D
@@:
endif
	not ah
	and al, ah			;skip flags that are set in preused
	test al,[bx][txflags]
	jz @F
	mov ax,[idxins]
	mov cl,[bx][txsize]
	mov ch,0
	push bx
	shl bx,1
	mov dx,[bx][txtabs]
	call [bx][txprocs]
	pop bx
	mov al,[bx][txflags]
	or [preused], al	;mark this prefix as used
@@:
	inc bx
	cmp bx, 6
	jb nextflag
;	@dprintf "da21 done: preflags=%X", word ptr preflags
	jmp da_done

hdl_scan_table:
	push di
	mov di, dx
	push cx
	repne scasw
	pop cx
	jnz @F
	dec cx
	shl cx, 1
	add di,cx		;position DI for opcode replacement
	mov si,[di]
	add si,offset mnlist
	xor cx, cx		;ZF=1
@@:
	pop di
	ret

ife ?PM
hdl_d32:
endif
hdl_wait:
	call hdl_scan_table
	jnz disbad2
	jmp hdl_showop		;copy op mnemonic, preserve di

if ?PM
hdl_d32:
	test [bCSAttr], CS32		; nothing special if CS is 16-bit
	jz hdl_wait
	@dprintf "hdl_d32, scan opcode tab, preflags=%X", word ptr [preflags]
	call hdl_scan_table
	jnz @F
	@dprintf "hdl_d32, CS=32: opcode found"
	test [preflags], PRE32D	; 66h prefix in CS32 code?
	jz hdl_d32_ex			; if yes: exit
	jmp hdl_showop			; if no: switch opcode to 32-bit
@@:
	@dprintf "hdl_d32, opcode not found"
	test [preflags], PRE32D	; 66h prefix in CS32 code?
	jz disbad2				; if yes: bad 66h prefix
hdl_d32_ex:
	ret
endif

hdl_a32:
	call hdl_scan_table		; check for the few opcodes that change with 67h prefix (LOOPx,JCXZ)
	jnz @F
	@dprintf "hdl_a32, opcode found"
if ?PM
	test [preflags], PRE32A	; CS32?
	jz hdl_a32_ex			; if no, do nothing
endif
	jmp hdl_showop			; switch opcode if found
@@:
	@dprintf "hdl_a32, opcode not found"
if ?PM
	test [bCSAttr], CS32
	jz @F
	test [preflags], PRE32A	; 32bit and a true 67h prefix in code stream?
	jnz hdl_a32_ex			; if no, do nothing
@@:
endif
	@dprintf "hdl_a32, true 67h prefix, testing string instr"
	push di
	mov di, offset strinstr
	mov cx, 14
	repnz scasb
	pop di
	jnz disbad2
	mov si,offset szA32
if ?PM
	test [bCSAttr], CS32
	jz @F
	mov si,offset szA16
@@:
endif
	movsw
	movsw
hdl_a32_ex:
	ret

disbad2:
	jmp disbad

hdl_seg:
	cmp ah,0
	jnz disbad2		;if index > 256
	push di
	mov di,dx
	repne scasb
	pop di
	jne disbad2		;if it's not on the list
	mov cx,3
	call moveover
	push di
	mov di,offset line_out+MNEMONOFS
	call showseg	;show segment register
	mov al,':'
	stosb
	pop di
;	or [preused],PRESEG		;mark it as used
	ret

;--- ax=instr, cx=items in table, dx=offset table

hdl_rep:
	cmp ah,0
	jnz disbad2		;if not in the first 256 bytes
	and al,not 1	;clear bit0 (MOVSW -> MOVSB)
	push di
	mov di,dx		;scan those for REP first
	repne scasb
	mov si,offset mnlist+MN_REP
	je hdl_insprf	;if one of the REP instructions
	mov cl,N_REPALL - N_REPNC
	repne scasb
	jne disbad2		;if not one of the REPE/REPNE instructions
	mov si,offset mnlist+MN_REPE
;	test [preused],PREREPZ		; v2.03: isn't set yet with the new code,
	test [preflags],PREREPZ		; but we may use [preflags].
	jnz hdl_insprf	;if REPE
	mov si,offset mnlist+MN_REPNE
	jmp hdl_insprf	;it's REPNE

hdl_lock:
	push di
	mov di,dx
	repne scasw
	jne disbad2		;if not in the approved list
	test [preused],PRESEG
	jz disbad2		;if memory was not accessed
	mov si,offset mnlist+MN_LOCK
;	or [preused],PRELOCK

;--- Slip in another mnemonic: REP/REPE/REPNE/LOCK.
;--- SI = offset of mnemonic, what should be
;--- DI is on the stack.

hdl_insprf:
	pop di
	mov cx,8
	push si
	call moveover
	pop si
hdl_showop:
	push di
	call showop
	pop di
	ret

;--- Done with instruction.  Erase the size indicator, if appropriate.

da_done:
	mov cx,[sizeloc]
	cmp cx,0
	jz da28b		;if there was no size given
	mov al,[disflags]
	test al,DIS_I_SHOWSIZ
	jnz da28b		;if we need to show the size
	test al,DIS_I_KNOWSIZ
	jz da28b		;if the size is not known already
	xchg cx,di
	mov si,di		;save old di
	mov al,' '
@@:
	scasb			;skip size name
	jne @B			;if not done yet
					;(The above is the same as repne scasb, but
					;has no effect on cx.)
	add di,4		;skip 'PTR '
	xchg si,di
	sub cx,si
	rep movsb		;move the line

;--- Now we're really done.  Print out the bytes on the left.

da28b:
	push di		;print start of disassembly line
	mov di,offset line_out
	mov ax,[u_addr+4]	;print address
	call hexword
	mov al,':'
	stosb
	sizeprfX			;mov eax,[u_addr+0]
	mov ax,[u_addr+0]
	call DispOfs
	mov al,' '
	stosb
	mov bx,[dis_n]
@@:
	mov si,offset line_out+MNEMONOFS - 1
	sub si, di
	shr si, 1
	cmp bx,si
	jle da29		;if it's a short instruction which fits in one line
	sub bx,si
	push bx
	mov bx,si
	push di
	call disshowbytes
	call putsline
	pop cx
	pop bx
	mov di,offset line_out
	sub cx,di
	mov al,' '
	rep stosb
	jmp @B
da29:
	call disshowbytes
	mov al,' '		;pad to op code
	mov cx,offset line_out+MNEMONOFS
	sub cx,di
	jc @F
	rep stosb
@@:
	pop di
	test [disflags], DIS_I_UNUSED
	jz da32			;if we don't print ' (unused)'
	mov si,offset unused
	cmp byte ptr [di-1],' '
	jne @F			;if there's already a space here
	inc si
@@:
	call copystring	;si->di

;--- Print info. on minimal processor needed.

da32:
	push di
	mov di,offset obsinst
	mov cx,[idxins]
	call showmach	;show the machine type, if needed
	pop di
	jcxz da32f		;if no message

;--- Print a message on the far right.

	mov ax,offset line_out+79
	sub ax,cx
	push cx
	call tab_to		;tab out to the location
	pop cx
	rep movsb		;copy the string
	jmp da32z		;done

;--- Dump referenced memory location.
;--- v2.03: skip this if instruction is LEA!

da32f:
	mov al,[disflags]
	xor al,DIS_F_SHOW + DIS_I_SHOW
	test al,DIS_F_SHOW + DIS_I_SHOW
	jnz da32z		;if there is no memory location to show

	cmp [bInstr], 8Dh	; v2.03: don't show mem contents for lea!
	jz da32z

ife RING0			; for DebugR, FS/GS memory contents aren't skipped
	cmp [segmnt],3 
	ja da32z		;if FS or GS
endif
	mov ax,offset line_out+79-8	; room for ss:oooo=bb|wwww|dddddddd
	mov cx,2
	cmp [rmsize],0
	jl da32h		;if byte
	jz @F			;if word
	add cx, 4		; 4 more chars
@@:
	add cx, 2		; 2 more chars
da32h:
	sub ax, cx
	push cx
	call tab_to
	call showseg		;show segment register
	mov al,':'
	stosb
	mov ax,[addrr]
	call hexword		;show offset
	mov al,'='
	stosb
	mov al,[segmnt]		;segment number
	cbw
	shl ax,1
	xchg ax,bx			;mov bx,ax
	mov bx,[segrgaddr+bx] ;get address of value
if ?PM
;--- v2.0: we don't want that just msg "General Protection Fault"
;--- appears, without a hint what the underlying problem is.
;--- so display what's rendered up to now...
	call puts
	or [disflags], DIS_I_MEMACC	; tell exc handler to print a crlf first
	mov di, offset line_out
endif
	pop cx
	shr cl, 1
;--- v2.0: just read the bytes that the instruction would
	push ds
	mov ds, [bx]
	mov bx, cs:[addrr]
	add bx, cx
@@:
	dec bx
	mov al, [bx]
	call hexbyte	;display byte
	dec cl
	jnz @B
	pop ds
if ?PM
	and [disflags], not DIS_I_MEMACC
endif

da32z:
	call trimputs	;print (rest of) disassembled line
	mov al,[disflags]
	test al,DIS_F_REPT
	jz da34			;if we're not allowed to repeat ourselves
	test al,DIS_I_UNUSED
	jnz @F			;if we printed ' (unused)'
	mov ax,[idxins]
	cmp ax,17h
	je @F			;if it was 'pop ss'
	cmp ax,8eh
	je @F			;if it was 'mov ss,--'
	cmp ax,0fbh
	jne da34		;if it was not 'sti'
@@:
	jmp disasm1
da34:
	ret

;--- MOD R/M (OP_RM)

dop_rm:
	call getregmem
	cmp al,0c0h
	jb dop05
	jmp dop_r1			;if pure register reference
dop05:					;<--- used by OP_M, OP_M64, OP_M80
	call showsize		;print out size in AH
dop06:					;<--- used by OP_MOFFS, OP_MXX, OP_MFLOAT, OP_MDOUBLE
	or [preused],PRESEG	;needed even if there's no segment override
						;because handling of LOCK prefix relies on it
	test [preflags],PRESEG
	jz @F				;if no segment override
	call showseg		;print segment name
	mov al,':'
	stosb
@@:
	mov al,[ai.regmem]
	and al,0c7h
	or [preused], PRE32A
	test [preflags], PRE32A
	jz @F
	jmp dop18		;if 32-bit addressing
@@:
	or [disflags], DIS_I_SHOW	;we'd like to show this address
	mov [addrr],0	; zero out the address initially
	cmp al,6
	xchg ax,bx		;mov bx,ax
	mov al,'['
	stosb
	je dop16		;if [xxxx]
	and bx,7
	mov bl,[rmtab+bx]
	test bl,8
	jnz dop09		;if BX
	test bl,4
	jz dop11		;if not BP
	mov ax,'PB'		;"BP"
	mov cx,[regs.rBP]
	test [preflags],PRESEG
	jnz dop10		;if segment override
	dec [segmnt]	;default is now SS
	jmp dop10
dop09:
	mov ax,'XB'		;"BX"
	mov cx,[regs.rBX]

dop10:
	mov [addrr],cx	;print it out, etc.
	stosw
	test bl,2+1
	jz dop13		;if done
	mov al,'+'
	stosb
dop11:
	mov ax,'IS'		;"SI"
	mov cx,[regs.rSI]
	test bl,1
	jz @F			;if SI
	mov al,'D'		;"DI"
	mov cx,[regs.rDI]
@@:
	add [addrr],cx	; base+index ([BX+SI, ....  )
	stosw
dop13:
	test [ai.regmem], 0c0h
	jz dop17		;if no displacement
	test [ai.regmem], 80h
	jnz dop15		;if word displacement
	call disgetbyte
	cbw
	add [addrr],ax	; [base][+index]+byte
	cmp al,0
	mov ah,'+'
	jge @F			;if >= 0
	mov ah,'-'
	neg al
@@:
	mov [di],ah
	inc di
	call hexbyte	;print the byte displacement
	jmp dop17		;done
dop15:
	mov al,'+'
	stosb
dop16:				;<--- pure 16bit offset
	call disgetword
	add [addrr],ax
	call hexword    ;print word displacement
dop17:
	mov al,']'
	stosb
	ret

;--- 32-bit MOD REG R/M addressing.

dop18:
	cmp al,5
	jne @F			;if not just a disp32 address
	mov al,'['
	stosb
	call disp32		;get & display 32bit offset
	jmp dop27

@@:
	push ax
	and al,7
	cmp al,4
	jne @F			;if no SIB
	call disgetbyte	;get and save it
	mov [ai.sibbyte],al
@@:
	pop ax
	test al,80h
	jnz dop22		;if disp32
	test al,40h
	jz dop23		;if no disp8
	call disgetbyte
	cmp al,0
	jge @F			;if >= 0
	neg al
	mov byte ptr [di],'-'
	inc di
@@:
	call hexbyte
	jmp dop23		;done

;--- the disassembler displays offsets first;
;--- example: mov ax,00001000[ebx][edi]

dop22:
	call disp32		;get and display 32bit offset

dop23:
	mov al,[ai.regmem]
	and al,7
	cmp al,4
	jne showsqreg32	;if no SIB
	mov al,[ai.sibbyte]
if 1               ;bugfix: make 'u' correctly handle [ESP],[ESP+x]
	cmp al,24h
	jnz @F
	mov al,4
	jmp showsqreg32
@@:
endif
	and al,7
	cmp al,5
	jne @F			;if not [EBP]
	test [ai.regmem], 0c0h
	jnz @F			;if MOD != 0
	call disp32		;get and show 32-bit displacement instead of [EBP]
	jmp dop25

@@:
	call showsqreg32; render "[E&reg]"; al=reg
dop25:
	mov al,[ai.sibbyte]
	shr al,1
	shr al,1
	shr al,1
	and al,7
	cmp al,4
	je disbad1		;if illegal

	call showsqreg32; render "[E&reg]; al=reg
	dec di			; remove "]"

	mov ah,[ai.sibbyte]
	test ah,0c0h
	jz dop27		;if SS = 0
	mov al,'*'
	stosb
	mov al,'2'
	test ah,80h
	jz @F			;if *2
	mov al,'4'
	test ah,40h
	jz @F			;if *4
	mov al,'8'
@@:
	stosb
dop27:
	mov al,']'
	stosb
	ret

;--- Memory-only reference (OP_M)

dop_m:
	call getregmem
	cmp al,0c0h
	jae disbad1		;if it's a register reference
	jmp dop05

disbad1:
	jmp disbad		;this is not supposed to happen

;--- Register reference from MOD R/M part (OP_R_MOD)

dop_r_mod:
	call getregmem
	cmp al,0c0h
	jb disbad1		;if it's a memory reference
	jmp dop_r1

;--- Memory offset reference (OP_MOFFS)

dop_moffs:
	call showsize	;print the size and save various things
	mov al,5
	test [preflags], PRE32A
	jnz @F			;if 32-bit addressing
	inc ax
@@:
	mov [ai.regmem],al
	jmp dop06		;don't show size

;--- Pure register reference (OP_R)

dop_r:
	call getregmem_r
dop_r1:					;<--- used by OP_RM, OP_R_MOD, OP_R_ADD, OP_AX
	and al,7			;entry point for regs from MOD R/M, and others
	mov cl,[disflags2]
	or [disflags],cl	;if it was variable size operand, the size
						;should now be marked as known.
	cmp ah,0
	jl dop_reg			;if byte register
	jz dop_wordreg		;if word register
	cmp ah,20h			;qword register (mmx)?
	jz dop_regmmx
	mov byte ptr [di],'E'
	inc di
dop_wordreg:
	add al,8			; use the 16-bit names ( rgnam16 )
dop_reg:
	cbw
	shl ax,1
	xchg ax,bx			; mov bx,ax
	mov ax,[rgnam816+bx]; get the register name
	stosw
	ret
dop_regmmx:
	push ax
	mov ax,"MM"
	stosw
	pop ax
	add al,'0'
	stosb
	ret

;--- Register number embedded in the instruction (OP_R_ADD)

dop_r_add:
	mov al,[bInstr]
	jmp dop_r1

;--- AL or AX or EAX (OP_AX)

dop_ax:
	mov al,0
	jmp dop_r1

;--- QWORD mem (OP_M64).
;--- this operand type is used by:
;--- + cmpxchg8b
;--- + fild, fistp

dop_m64:
;	mov ax,'Q'		;print 'Q' +'WORD'
	mov ah,20h		;size QWORD
	jmp dop40

;--- FLOAT (=REAL4) mem (OP_MFLOAT).

dop_mfloat:
	mov ax,'LF'
	stosw
	mov al,'O'
	stosb
	mov ax,'TA'
	jmp dop38c

;--- DOUBLE (=REAL8) mem (OP_MDOUBLE).

dop_mdouble:
	mov ax,'OD'
	stosw
	mov ax,'BU'
	stosw
	mov ax,'EL'
dop38c:
	stosw
	call showptr
	jmp dop42a

;--- TBYTE (=REAL10) mem (OP_M80).

dop_m80:
	mov ax,0ff00h+'T'	;print 't' + 'byte'
	stosb
dop40:
	call getregmem
	cmp al,0c0h
	jae disbad5		;if it's a register reference
	and [disflags],not DIS_F_SHOW	;don't show this
	jmp dop05

;--- far memory (OP_FARMEM).
;--- this is either a FAR16 (DWORD) or FAR32 (FWORD) pointer

dop_farmem:
	call dischk32d
	jz @F			;if not dword far
	call showdwd
	sub di,4		;erase "PTR "
@@:
	mov ax,'AF'		;store "FAR "
	stosw
	mov ax,' R'
	stosw

;--- mem (OP_MXX).

dop_mxx:
	and [disflags],not DIS_F_SHOW	;don't show this
dop42a:
	call getregmem
	cmp al,0c0h
	jae disbad5		;if it's a register reference
	jmp dop06		;don't show size

disbad5:
	jmp disbad

;--- Check for ST(1) (OP_1CHK).

dop_st1:
	pop ax		;discard return address
	mov al,[ai.regmem]
	and al,7
	cmp al,1
	je @F		;if it's ST(1)
	jmp da14	;another operand (but no comma)
@@:
	jmp da21	;end of list

;--- store segment register name (OP_SEGREG).

dop_segreg:
	call getregmem_r
	cmp al,6
	jae disbad		;if not a segment register
	cmp al,2
	je @F			;if SS
	and [disflags],not DIS_F_REPT	;clear flag:  don't repeat
@@:
	cmp al,4
	jb @F			;if not FS or GS
	mov [ai.dismach],3	;(no new 486-686 instructions involve seg regs)
@@:
	add al,8+8		;segreg names are behind 8-bit/16-bit regnames
	jmp dop_reg		;go print it out

;--- Sign-extended immediate byte (OP_IMMS8). "push xx"

dop_imms8:
	call showsizeop
	call disgetbyte
	cmp al,0
	xchg ax,bx		;mov bl,al
	mov al,'+'
	jge @F			;if >= 0
	neg bl
	mov al,'-'
@@:
	stosb
	xchg ax,bx		;mov al,bl
	jmp dop59a		;call hexbyte and return

;--- Immediate byte (OP_IMM8).

dop_imm8:
	call disgetbyte
dop59a:
	jmp hexbyte		;call hexbyte and return

;--- Set flag to always show size (OP_SHOSIZ).

dop_shosiz:
	or [disflags],DIS_I_SHOWSIZ
	pop ax			;discard return address
	jmp da14		;next operand

disasm endp

disbad proc
if FLATSS
	.386
	mov esp,[run_sp]	;pop junk off stack
else
	mov sp,[run_sp]		;pop junk off stack
endif
	mov ax,offset da13pre	; the address where we "return" to
	push ax
	mov [dis_n],0
	mov word ptr [preflags],0		;clear preflags and preused
	mov [rmsize],80h				;don't display any memory
	mov word ptr [ai.dismach],0		;forget about the machine type
	and [disflags],not DIS_I_SHOW	;and flags
	call disgetbyte
	mov di,offset prefixlist
	mov cx,N_PREFIX
	repne scasb
	je @F			;if it's a named prefix
	dec [dis_n]		;reset cnt to 0 again
	mov bx,MN_DB	;offset of 'DB' mnemonic
	mov si,OPLIST_26+OPTYPES_BASE;this says OP_IMM8
	ret
@@:
	or [disflags],DIS_I_UNUSED	;print special flag
	mov bx,N_PREFIX-1
	sub bx,cx
	shl bx,1
	cmp bx,6*2
	jb @F			;if SEG directive
	mov bx,[prefixmnem+bx-6*2]
	mov si,OPTYPES_BASE	;no operand
	ret
@@:
	lea si,[bx+OPLIST_40+OPTYPES_BASE]	;this is OP_ES
	mov bx,MN_SEG
	ret
disbad endp

;--- relative jumps

dop_relxx proc

;--- 8-bit relative jump (OP_REL8)

dop_rel8::
	call disgetbyte
	cbw
	jmp dop_rel16

;--- 16/32-bit relative jump (OP_REL1632)

dop_rel1632::
	call disgetword
	call dischk32d
	jz dop_rel16	;if not 32-bit distance
	push ax
if ?PM
	test [bCSAttr], CS32	;for 32bit code segments
	jnz @F			;no need to display "DWORD "
endif
	call showdwd	;"DWORD PTR "
	sub di,4		;erase "PTR "
@@:
	pop dx
	call disgetword
	mov bx,[u_addr+0]
	add bx,[dis_n]
	add dx,bx
	adc ax,[u_addr+2]
	call hexword
	xchg ax,dx
	jmp hexword		;call hexword and return

dop_rel16:			;16-bit distance
if ?PM
	test [bCSAttr], CS32
	jnz @F
endif
	add ax,[u_addr]
	add ax,[dis_n]
	jmp hexword		;call hexword and return
if ?PM
@@:
	.386
	cwde	;=movsx eax,ax
	add eax,dword ptr [u_addr]
	add eax,dword ptr [dis_n]
	jmp hexdword
	.8086
endif

dop_relxx endp

;--- Here are the routines for printing out the operands themselves.

;--- CRx (OP_CR), DRx (OP_DR), TRx (OP_TR), MMx (OP_MMX)

dop_cr proc
	call getregmem_r
	mov bx,"RC"		; "CRx"
	cmp al,4
	ja disbad4		;if too large
	jne @F
	mov [ai.dismach],5	;CR4 is new to the 586
@@:
	cmp [idxins],SPARSE_BASE+22h
	jne dop55		;if not MOV CRx,xx
	cmp al,1
	jne dop55		;if not CR1
disbad4:
	jmp disbad		;can't MOV CR1,xx

;--- DRx (OP_DR).

dop_dr::
	call getregmem_r
	mov bx,"RD"		; "DRx"
	mov cx,-1		; no max or illegal value (remove?)
	jmp dop55

;--- MMx (OP_MMX)

dop_mmx::
	call getregmem_r
	mov bx,"MM"		; "MMx"
	jmp dop55

;--- TRx (OP_TR).

dop_tr::
	call getregmem_r
	cmp al,3
	jb disbad4		;if too small
	cmp al,6
	jae @F			;if TR6-7
	mov [ai.dismach],4	;TR3-5 are new to the 486
@@:
	mov bx,"RT"		; "TRx"
dop55:
	xchg ax,bx
	stosw			;store XX
	xchg ax,bx
	or al,'0'
	stosb
	ret
dop_cr endp

;--- ST(I) (OP_STI).

dop_sti proc
	mov al,[ai.regmem]
	and al,7
	xchg ax,bx		;mov bx,ax
	mov ax,'TS'
	stosw			;store ST(bl)
	mov al,'('
	stosb
	mov ax,')0'
	or al,bl
	stosw
	ret
dop_sti endp

;--- far immediate (OP_FARIMM). Either FAR16 or FAR32

dop_farimm proc
	mov bx, sp
	call disgetword
	push ax
	call dischk32d
	jz @F			; if not 32-bit address
	call disgetword
	push ax
@@:
	call disgetword	; get segment part
	call hexword
	mov al,':'
	stosb
@@:
	pop ax
	call hexword
	cmp bx, sp
	jnz @B
	ret
dop_farimm endp

;--- Immediate data (OP_IMM)

dop_imm proc
	cmp ah,0
	jl dop03		;if just a byte
	pushf
	test [disflags], DIS_I_SHOWSIZ
	jz @F			;if we don't need to show the size
	call showsize	;print size in AH
	sub di,4		;erase "PTR "
@@:
	call disgetword
	popf
	jz @F			;if just a word
	push ax
	call disgetword	;print the high order word
	call hexword
	pop ax
@@:
	call hexword
	ret

dop03:
	call disgetbyte	;print immediate byte
	call hexbyte
	ret
dop_imm endp

;--- 32-bit addressing without SIB
;--- store "[E&reg]" at DI

showsqreg32 proc
	cbw
	shl ax,1
	xchg ax,bx
	mov ax, 'E['
	stosw
	mov ax, [rgnam16+bx]
	stosw
	mov al,']'
	stosb
	ret
showsqreg32 endp

showsizeop proc
;--- for PUSH imm8 add D/W to opcode if size differs from default (WORD/DWORD)
	cmp [bInstr],6ah
	jnz sso_skip
	call dischk32d
if ?PM
	mov ah,[bCSAttr]
	.286
	shr ah,2		;40h -> 10h (=PRE32D)
	.8086
else
	mov ah,0
endif
	mov al,'W'
	test ah, PRE32D
	jnz @F
	mov al,'D'
@@:
	xor ah,[preflags]
	test ah, PRE32D
	jz sso_skip
	mov [di-4],al
sso_skip:
	ret
showsizeop endp

;--- DISCHK32D - Check for 32 bit operand size prefix (66h).

dischk32d proc
	or [preused], PRE32D
	test [preflags], PRE32D
	ret
dischk32d endp

;   GETREGMEM_R - Get the reg part of the reg/mem part of the instruction
;   Uses    CL

getregmem_r proc
	call getregmem
	mov cl,3
	shr al,cl
	and al,7
	ret
getregmem_r endp

;--- GETREGMEM - Get the reg/mem part of the instruction

getregmem proc
	test [preused],GOTREGM
	jnz @F			;if we have it already
	or [preused],GOTREGM
	call disgetbyte	;get the byte
	mov [ai.regmem],al	;save it away
@@:
	mov al,[ai.regmem]
	ret
getregmem endp

;   DISP32 - Print 32-bit displacement for addressing modes.
;   Entry   None
;   Exit    None
;   Uses    AX

disp32 proc
	call disgetword
	push ax
	call disgetword
	call hexword
	pop ax
	call hexword
	ret
disp32 endp

;   SHOWSEG - Show the segment descriptor in SEGMNT
;   Entry   DI  Where to put it
;   Exit    DI  Updated
;   Uses    AX, BX

showseg proc
	mov al,[segmnt]	;segment number
	cbw
	shl ax,1
	xchg ax,bx		;mov bx,ax
	mov ax, [segrgnam+bx] ;get register name
	stosw
	ret
showseg endp

;   SHOWOP  Show the op code
;   Entry   SI  Null-terminated string containing the op mnemonic
;   Exit    DI  Address of next available byte in output line
;           (>= offset line_out + 32 due to padding)
;   Uses    AL

showop proc
	mov di,offset line_out+MNEMONOFS
@@:
	lodsb
	mov ah,al
	and al,7Fh
	stosb
	and ah,ah
	jns @B
	mov al,' '
@@:
	stosb
	cmp di,offset line_out+MNEMONOFS+8
	jb @B
	ret
showop endp

;   SHOWSIZE - Print a description of the size
;   Entry   AH  10h=DWORD, 00h=WORD, F0h=BYTE, 20h=QWORD
;   Uses    AX

;   SHOWPTR - Print " PTR"
;   Uses    AX

;   SHOWDWD - Print "DWORD PTR"
;   Uses    AX

showsize proc
	mov [rmsize],ah	;save r/m size
	mov [sizeloc],di;save where we're putting this
	mov al,'Q'
	cmp ah,20h
	jz showqwd
	cmp ah,0
	jg showdwd	;if dword
	je showwd	;if word
	mov ax,'YB'
	stosw
	mov ax,'ET'
	jmp ssz3
showdwd::		;<---
	mov al,'D'
showqwd:
	stosb
showwd:
	mov ax,'OW'
	stosw
	mov ax,'DR'
ssz3:
	stosw
showptr::		;<---
	mov ax,'P '
	stosw
	mov ax,'RT'
	stosw
	mov al,' '
	stosb
	ret
showsize endp

;   DISGETBYTE - Get byte for disassembler.
;   Entry   None
;   Exit    AL  Next byte in instruction stream
;   Uses    None

disgetbyte proc
	push ds
if ?PM
	test [bCSAttr], CS32
	jnz @F
endif
	push si
	mov si,[u_addr]
	add si,[dis_n]		;index to the right byte
	mov ds,[u_addr+4]
	lodsb 				;get the byte
	pop si
	pop ds
	inc [dis_n]			;indicate that we've gotten this byte
	ret
if ?PM
	.386
@@:
	push esi
	lds esi,fword ptr [u_addr]
	add esi,dword ptr cs:[dis_n]	;index to the right byte
	lodsb ds:[esi]
	pop esi
	pop ds
	inc [dis_n]
	ret
	.8086
endif
disgetbyte endp

;   DISGETWORD - Get word for disassembler.
;   Entry   None
;   Exit    AX  Next word
;   Uses    None

disgetword proc
	push ds
if ?PM
	test [bCSAttr], CS32
	jnz @F
endif
	push si
	mov si,[u_addr]
	add si,[dis_n]		;index to the right byte
	mov ds,[u_addr+4]
	lodsw
	pop si
	pop ds
	add [dis_n],2
	ret
if ?PM
	.386
@@:
	push esi
	lds esi,fword ptr [u_addr]
	add esi,dword ptr cs:[dis_n]	;index to the right byte
	lodsw ds:[esi]
	pop esi
	pop ds
	add [dis_n],2
	ret
	.8086
endif
disgetword endp

;   DISSHOWBYTES - Show bytes for the disassembler.
;   Entry   BX  Number of bytes (must be > 0)
;   Exit        u_addr updated
;   Uses    BX, SI.

disshowbytes proc
if ?PM
	test [bCSAttr], CS32
	jnz dissb_1
endif
	mov si,[u_addr]
	mov ds,[u_addr+4]
@@:
	lodsb
	call hexbyte
	dec bx
	jnz @B
	@RestoreSeg ds
	mov [u_addr],si
	ret
if ?PM
	.386
dissb_1:
	lds esi,fword ptr [u_addr]
@@:
	lodsb ds:[esi]
	call hexbyte
	dec bx
	jnz @B
	@RestoreSeg ds
	mov dword ptr [u_addr],esi
	ret
    .8086
endif
disshowbytes endp

;   MOVEOVER - Move the line to the right - disassembler subfunction.
;   used to insert prefixes - called by code in the "prefix loop" only.
;   Entry   DI  Last address + 1 of line so far
;   Exit    CX  Number of bytes to move
;   DI  Updated
;   Uses    SI

moveover proc
	cmp [sizeloc],0
	je @F		;if sizeloc not saved
	add [sizeloc],cx
@@:
	mov si,di
	add di,cx
	mov cx,di
	sub cx,offset line_out+MNEMONOFS
	push di
	std
	dec si
	dec di
	rep movsb
	pop di
	cld
	ret
moveover endp

;   TAB_TO - Space fill until reaching the column indicated by AX.
;   (Print a new line if necessary.)

tab_to proc
	push ax
	sub ax,di
	ja @F			;if there's room on this line
	call trimputs
	mov di,offset line_out
@@:
	pop cx
	sub cx,di
	mov al,' '
	rep stosb		;space fill to the right end
	ret
tab_to endp

