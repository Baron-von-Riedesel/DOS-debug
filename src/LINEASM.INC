
;--- A command - tiny assembler.

;--- todo:
;--- 1. fix regression since v1.09: cmp [x], yy  assumes word operand if no size given
;--- 2. MS debug accepts call near/far [x], Debug rejects near [x], accepts far [x]
;--- 3. MS debug accepts call near/far x (adding current cs as seg if far), Debug rejects both

;--- macros for asmtbl.inc

;--- mne macro, used for the assembler mnemonics table

mne macro val2:REQ, dbytes:VARARG
ASMDATA segment
CURROFS = $
	ifnb <dbytes>
	 db dbytes
	endif
ASMDATA ends
	dw CURROFS - asmtab
MN_&val2 equ $ - mnlist
tmpstr catstr <!">,@SubStr(val2,1,@SizeStr(val2)-1),<!",!'>,@SubStr(val2,@SizeStr(val2)),<!'>,<+80h>
	db tmpstr
endm

;--- AGRP: num is the index into agroups, that finally defines the opcode (1 or 2 byte).
;--- rfld, bits 0-2 of the final value, define bits 3-5 in ai.regmem.

AGRP macro num,rfld
	exitm <240h + num*8 + rfld>
endm

variant macro opcode:req, key:req, lockb, machine
ASMDATA segment
	ifnb <lockb>
	 db lockb
	endif
	ifnb <machine>
	 db machine
	endif
ainfo = (opcode) * ASMMOD + key
	db HIGH ainfo, LOW ainfo
ASMDATA ends
endm

fpvariant macro opcode, key, addb, lockb, machine
	variant opcode, key, lockb, machine
ASMDATA segment
	db addb
ASMDATA ends
endm

endvariant macro
ASMDATA segment
	db -1
ASMDATA ends
endm

;--- opl macro, used to define operand list types
;--- the macro defines an EQUate, OPLIST_XX, which
;--- is refered to by array opindex.
;--- v2.50: "terminating" 0 no longer required.

opl macro index, value:VARARG
OPLIST_&index equ $ - oplists
	ifnb <value>
	  db value
	endif
endm

;--- flags for instruction operands.
;--- First the sizes.

OP_ALL	equ 40h		;byte/word/dword operand (could be 30h but ...)
OP_1632	equ 50h		;word or dword operand
OP_8	equ 60h		;byte operand
OP_16	equ 70h		;word operand
OP_32	equ 80h		;dword operand
OP_64	equ 90h		;qword operand

OP_SIZE	equ OP_ALL		;the lowest of these

;--- These operand types need to be combined with a size flag..
;--- order must match items in asm_jmp1, bittab and dis_jmp1

OP_IMM		equ 0		;immediate
OP_RM		equ 2		;reg/mem
OP_M		equ 4		;mem (but not reg)
OP_R_MOD	equ 6		;register, determined from MOD R/M part
OP_MOFFS	equ 8		;memory offset; e.g., [1234]
OP_R		equ 10		;reg part of reg/mem byte
OP_R_ADD	equ 12		;register, determined from instruction byte
OP_AX		equ 14		;al or ax or eax

;--- These don't need a size.
;--- order must match items in asm_jmp1, bittab and dis_optab.
;--- additionally, order of OP_M64 - OP_FARMEM is used
;--- in table asm_siznum
;--- v2.50: value 0 was used to terminate an operand list ( macro opl )
;---        it's free now.

OP_M64		equ 2		; 0 qword memory (obsolete?)
OP_MFLOAT	equ 4		; 1 float memory
OP_MDOUBLE	equ 6		; 2 double-precision floating memory
OP_M80		equ 8		; 3 tbyte memory
OP_MXX		equ 10		; 4 memory (size unknown)
OP_FARMEM	equ 12		; 5 memory far16/far32 pointer 
OP_FARIMM	equ 14		; 6 far16/far32 immediate
OP_REL8		equ 16		; 7 byte address relative to IP
OP_REL1632	equ 18		; 8 word or dword address relative to IP
OP_1CHK		equ 20		; 9 check for ST(1)
OP_STI		equ 22		;10 ST(I)
OP_CR		equ 24		;11 CRx
OP_DR		equ 26		;12 DRx
OP_TR		equ 28		;13 TRx
OP_SEGREG	equ 30		;14 segment register
OP_IMMS8	equ 32		;15 sign extended immediate byte
OP_IMM8		equ 34		;16 immediate byte (other args may be (d)word)
OP_MMX		equ 36		;17 MMx
OP_SHOSIZ	equ 38		;18 set flag to always show the size

OP_1		equ 40		;19 1 (simple "string" ops from here on)
OP_3		equ 42		;20 3
OP_DX		equ 44		;21 DX
OP_CL		equ 46		;22 CL
OP_ST		equ 48		;23 ST (top of coprocessor stack)
OP_CS		equ 50		;24 CS
OP_DS		equ 52		;25 DS
OP_ES		equ 54		;26 ES
OP_FS		equ 56		;27 FS
OP_GS		equ 58		;28 GS
OP_SS		equ 60		;29 SS

OP_STR equ OP_1		;first "string" op

CONST segment

;--- Instructions that have an implicit operand subject to a segment override
;--- (outsb/w, movsb/w, cmpsb/w, lodsb/w, xlat).
;--- also used by disassembler

prfxtab	db 06eh,06fh, 0a4h,0a5h, 0a6h,0a7h, 0ach,0adh, 0d7h
N_PRFXTAB equ $ - prfxtab

;--- Instructions that can be used with REP/REPE/REPNE.
;--- also used by disassembler

replist	db 06ch,06eh,0a4h,0aah,0ach	;REP (INSB, OUTSB, MOVSB, STOSB, LODSB)
N_REPNC  equ $ - replist
		db 0a6h,0aeh				;REPE/REPNE (CMPSB, SCASB)
N_REPALL equ $ - replist

	include <ASMTBL.INC>

;--- opindex array - help array to access operand list items (oplists);
;--- needed because the operand list items differ in size.

opindex label byte
	.radix 16t
opidx = 0
	repeat ASMMOD
if opidx lt 10h
%	db OPLIST_0&@CatStr(%opidx)
else
%	db OPLIST_&@CatStr(%opidx)
endif
opidx = opidx + 1
	endm
	.radix 10t
	db offset agroups - offset oplists	; size of oplists table, required to find end of last operand list

CONST ends

_DATA segment

asm_mn_flags	db 0	;flags for the mnemonic

AMF_D32		equ 1		;32bit opcode/data operand
AMF_WAIT	equ 2
AMF_A32		equ 4		;address operand is 32bit
AMF_SIB		equ 8		;there's a SIB in the arguments
AMF_MSEG	equ 10h		;if a seg prefix was given b4 mnemonic
AMF_FSGS	equ 20h		;if FS or GS was encountered

AMF_D16		equ 40h		;16bit opcode/data operand
AMF_ADDR	equ 80h		;address operand is given

bEndOplItem db 0		;v2.50

;--- aa_saved_prefix and aa_seg_pre must be consecutive.
aa_saved_prefix	db 0	;WAIT or REP... prefix
aa_seg_pre	db 0		;segment prefix

mneminfo	dw 0		;address associated with the mnemonic
a_opcode	dw 0		;op code info for this variant
a_opcode2	dw 0		;copy of a_opcode for obs-instruction

;--- dmflags values
DM_COPR		equ 1	;math coprocessor
DM_MMX		equ 2	;MMX extensions

;--- varflags values
VAR_LOCKABLE	equ 1	;variant is lockable
VAR_MODRM		equ 2	;if there's a MOD R/M here
VAR_SIZ_GIVN	equ 4	;if a size was given
VAR_SIZ_FORCD	equ 8	;if only one size is permitted
VAR_SIZ_NEED	equ 10h	;if we need the size
VAR_D16			equ 20h	;if operand size is WORD
VAR_D32			equ 40h	;if operand size is DWORD

AINSTR struct
rmaddr		dw ?	;address of operand giving the R/M byte (asm only)
;--- regmem and sibbyte must be consecutive
regmem		db ?	;mod reg r/m part of instruction
sibbyte		db ?	;SIB byte
immaddr		dw ?	;address of operand giving the immed stf (asm only)
xxaddr		dw ?	;address of additional stuff (asm only)
;--- dismach and dmflags must be consecutive
dismach		db ?	;type of processor needed
dmflags		db ?	;flags for extra processor features
opcode_or	db ?	;extra bits in the op code (asm only)
opsize		db ?	;size of this operation (2 or 4) (asm only)
varflags	db ?	;flags for this variant (asm only)
reqsize		db ?	;size that this arg should be (asm only)
AINSTR ends

ai	AINSTR <?>		; used by assembler and disassembler

_DATA ends

CONST segment

;--- search for "obsolete" instructions
;--- dbe0: FENI
;--- dbe1: FDISI
;--- dbe4: FSETPM
;---  124: MOV TRx, reg
;---  126: MOV reg, TRx

a_obstab	dw 0dbe0h,0dbe1h,0dbe4h,124h,126h	;obs. instruction codes
obsmach		db 1,1,2,4,4	;max permissible machine for the above

modrmtab	db 11,0,13,0,15,0,14,0	;[bx], [bp], [di], [si]
			db 15,13,14,13,15,11,14,11	;[bp+di],[bp+si],[bx+di],[bx+si]

aam_args	db 'a',CR

;--- Equates for parsed arguments, stored in OPRND.flags

ARG_DEREF		equ 1	;non-immediate memory reference
ARG_MODRM		equ 2	;if we've computed the MOD R/M byte
ARG_JUSTREG		equ 4	;a solo register
ARG_WEIRDREG	equ 8	;if it's a segment register or CR, etc.
ARG_IMMED		equ 10h	;if it's just a number
ARG_FARADDR		equ 20h	;if it's of the form xxxx:yyyyyyyy

;--- For each operand type in the following table, the first byte is
;--- the bits, at least one of which must be present; the second is the
;--- bits all of which must be absent.
;--- the items in bittab must be ordered similiar to asm_jmp1 and dis_jmp1.

bittab label byte
	db ARG_IMMED			;+0 OP_IMM
	db ARG_DEREF+ARG_JUSTREG;+1 OP_RM
	db ARG_DEREF			;+2 OP_M
	db ARG_JUSTREG			;+3 OP_R_MOD
	db ARG_DEREF			;+4 OP_MOFFS
	db ARG_JUSTREG			;+5 OP_R
	db ARG_JUSTREG			;+6 OP_R_ADD
	db ARG_JUSTREG			;+7 OP_AX

	db ARG_DEREF			; 0 OP_M64
	db ARG_DEREF			; 1 OP_MFLOAT
	db ARG_DEREF			; 2 OP_MDOUBLE
	db ARG_DEREF			; 3 OP_M80
	db ARG_DEREF			; 4 OP_MXX
	db ARG_DEREF			; 5 OP_FARMEM
	db ARG_FARADDR			; 6 OP_FARIMM
	db ARG_IMMED			; 7 OP_REL8
	db ARG_IMMED			; 8 OP_REL1632
	db ARG_WEIRDREG			; 9 OP_1CHK
	db ARG_WEIRDREG			;10 OP_STI
	db ARG_WEIRDREG			;11 OP_CR
	db ARG_WEIRDREG			;12 OP_DR
	db ARG_WEIRDREG			;13 OP_TR
	db ARG_WEIRDREG			;14 OP_SEGREG
	db ARG_IMMED			;15 OP_IMMS8
	db ARG_IMMED			;16 OP_IMM8
	db ARG_WEIRDREG			;17 OP_MMX
	db 0ffh					;18 OP_SHOSIZ

	db ARG_IMMED			;OP_1
	db ARG_IMMED			;OP_3
	db ARG_JUSTREG			;OP_DX
	db ARG_JUSTREG			;OP_CL
	db ARG_WEIRDREG			;OP_ST
	db ARG_WEIRDREG			;OP_CS
	db ARG_WEIRDREG			;OP_DS
	db ARG_WEIRDREG			;OP_ES
	db ARG_WEIRDREG			;OP_FS
	db ARG_WEIRDREG			;OP_GS
	db ARG_WEIRDREG			;OP_SS

;--- special ops DX, CL, ST, CS, DS, ES, FS, GS, SS
;--- entry required if ao48 is set
;--- order of entries matches the last 9 ones in dis_optab

asm_regnum label byte
	db REG_DX, REG_CL, REG_ST, REG_CS, REG_DS, REG_ES, REG_FS, REG_GS, REG_SS

;--- size qualifier
;--- 1  BY=BYTE ptr
;--- 2  WO=WORD ptr
;--- 3  unused
;--- 4  DW=DWORD ptr
;--- 5  QW=QWORD ptr
;--- 6  FL=FLOAT ptr (REAL4)
;--- 7  DO=DOUBLE ptr (REAL8)
;--- 8  TB=TBYTE ptr (REAL10)
;--- 9  SH=SHORT 
;--- 10 LO=LONG
;--- 11 NE=NEAR ptr
;--- 12 FA=FAR ptr

SIZ_NONE	equ 0
SIZ_BYTE	equ 1
SIZ_WORD	equ 2
SIZ_DWORD	equ 4
SIZ_QWORD	equ 5
SIZ_FLOAT	equ 6
SIZ_DOUBLE	equ 7
SIZ_TBYTE	equ 8
SIZ_SHORT	equ 9
SIZ_LONG	equ 10
SIZ_NEAR	equ 11
SIZ_FAR		equ 12

sizetcnam	db 'BY','WO','WO','DW','QW','FL','DO','TB','SH','LO','NE','FA'

;--- sizes for OP_M64, OP_MFLOAT, OP_MDOUBLE, OP_M80, OP_MXX, OP_FARMEM

asm_siznum	db SIZ_QWORD, SIZ_FLOAT, SIZ_DOUBLE, SIZ_TBYTE
			db -1, SIZ_FAR			;-1 = none

CONST ends

;--- write byte in AL to BX/[E]DX, then increment [E]DX

writeasm proc
	call writemem
	sizeprfX	;inc edx
	inc dx
	ret
writeasm endp

;--- write CX bytes from DS:SI to BX:[E]DX

writeasmn proc
	jcxz nowrite
@@:
	lodsb
	call writeasm
	loop @B
nowrite:
	ret
writeasmn endp

a_cmd proc
	mov [errret],offset aa01
	cmp al,CR
	je aa01x		;if end of line
	@movs bx,[regs.rCS]	;default segment to use
aa00a:
	call getaddr	;get address into bx:(e)dx
	call chkeol		;expect end of line here
	sizeprfX		;mov [a_addr+0],edx
	mov [a_addr+0],dx	;save the address
	mov [a_addr+4],bx
if ?PM
	jmp aa01
aa01x:
 if ?DPMI
	call ispm_dbe
	jz aa01
;--- v2.0: def seg for a is no longer automatically converted
;--- when pm is entered.
 endif
	test [bFlagsPM], 1	; default for a-cmd already set?
	jnz aa01
	@movs ax, [regs.rCS]; use current CS:IP as default
	mov [a_addr+4], ax 
	sizeprfX			; mov eax, [regs.IP]
	mov ax, [regs.rIP]    
	sizeprfX			; mov [a_addr+0], eax
	mov [a_addr+0], ax
else
aa01x:
endif

;--- Begin loop over input lines.

aa01:
if ?PM
	or [bFlagsPM], 1
endif
	@dprintf "aa01: a_addr=%X:%lX", word ptr [a_addr+4], dword ptr [a_addr+0]
if FLATSS
	db 66h              ;mov esp,[top_sp]
endif
	mov sp,[top_sp]		;restore the stack (this implies no "ret")
	mov di,offset line_out
	@dispsegm [a_addr+4]
	mov al,':'
	stosb
	mov [asm_mn_flags],0
if ?PM
	mov bx,[a_addr+4]
	call getseldefsize
	mov [bCSAttr],al
endif
	sizeprfX			;mov eax,[a_addr+0]
	mov ax,[a_addr+0]
	call DispOfs
	mov al,' '
	stosb
	call getline00
	cmp al,CR
	je aa_exit	;if done
	cmp al,';'
	je aa01		;if comment
	mov word ptr [aa_saved_prefix],0 ;clear aa_saved_prefix and aa_seg_pre

;--- Get mnemonic and look it up.

aa02:
	mov di,offset line_out	;return here after LOCK/REP/SEG prefix
	push si			;save position of mnemonic
aa03:
	cmp al,'a'
	jb @F			;if not lower case letter
	cmp al,'z'
	ja @F
	and al,TOUPPER	;convert to upper case
@@:
	stosb
	lodsb
	cmp al,CR
	je @F			;if end of mnemonic
	cmp al,';'
	je @F
	cmp al,' '
	je @F
	cmp al,':'
	je @F
	cmp al,TAB
	jne aa03
@@:
	or byte ptr [di-1],80h	;set highest bit of last char of mnemonic
	call skipwh0	;skip to next field
	dec si
	push si			;save position in input line
;	mov al,0
;	stosb

;--- now search mnemonic in list

	mov si,offset mnlist
aa06:               ;<--- next mnemonic
	mov bx,si
	add si,2		;skip the 'asmtab' offset 
	mov cx,si
@@:
	lodsb			;skip to end of string
	and al,al
	jns @B			;if not end of string
	xchg cx,si
	push cx
	sub cx,si		;size of opcode in mnlist
	mov di,offset line_out
	repe cmpsb
	pop si
	je aa14			;if found it
	cmp si,offset end_mnlist
	jc aa06			;next mnemonic
	pop si			;skip position in input line
aa13a:
	pop si			;skip position of mnemonic
aa13b:
	jmp cmd_error	;complain
aa_exit:
	jmp cmdloop		;done with this command

;--- We found the mnemonic.

aa14:
	mov si,[bx]		;get the offset into asmtab
	add si,offset asmtab

;   Now si points to the spot in asmtab corresponding to this mnemonic.
;   The format of the assembler table is as follows.
;   First, there is optionally one of the following bytes:
;       ASM_DB      db mnemonic
;       ASM_DW      dw mnemonic
;       ASM_DD      dd mnemonic
;       ASM_WAIT    the mnemonic should start with a wait
;                   instruction.
;       ASM_D32     This is a 32 bit instruction variant.
;       ASM_D16     This is a 16 bit instruction variant.
;       ASM_AAX     Special for AAM and AAD instructions:
;                   put 0ah in for a default operand.
;       ASM_SEG     This is a segment prefix.
;       ASM_LOCKREP This is a LOCK or REP... prefix.
;
;   Then, in most cases, this is followed by one or more of the following
;   sequences, indicating an instruction variant.
;   ASM_LOCKABLE (optional) indicates that this instruction can
;                follow a LOCK prefix.
;   ASM_MACHx    (optional) indicates the first machine on which this
;                instruction appeared.
;   [word]       This is a 16-bit integer, most significant byte
;                first, giving ASMMOD * a + b, where b is an
;                index into the array opindex (indicating the
;                key, or type of operand list), and a is as
;                follows:
;                0-255     The (one-byte) instruction.
;                256-511   The lower 8 bits give the second byte of
;                          a two-byte instruction beginning with 0fh.
;                512-575   Bits 2-0 say which floating point instruction
;                          this is (0d8h-0dfh), and 5-3 give the /r
;                          field.
;                576-...   (a-576)/8 is the index in the array agroups
;                          (which gives the real value of a), and the
;                          low-order 3 bits gives the /r field.
;
;   [byte]       This gives the second byte of a floating
;                instruction if 0d8h <= a <= 0dfh.
;
;   Following these is an ASM_END byte.
;
;   Exceptions:
;       ASM_SEG and ASM_LOCKREP are followed by just one byte, the
;       prefix byte.
;       ASM_DB, ASM_DW, and ASM_DD don't need to be followed by
;       anything.

ASM_END		equ 0ffh
ASM_DB		equ 0feh
ASM_DW		equ 0fdh
ASM_DD		equ 0fch
ASM_ORG		equ 0fbh
ASM_WAIT	equ 0fah
ASM_D32		equ 0f9h
ASM_D16		equ 0f8h
ASM_AAX		equ 0f7h
ASM_SEG		equ 0f6h
ASM_LOCKREP	equ 0f5h
ASM_LOCKABLE equ 0f4h
ASM_MACH6	equ 0f3h
ASM_MACH5	equ 0f2h
ASM_MACH4	equ 0f1h
ASM_MACH3	equ 0f0h
ASM_MACH2	equ 0efh
ASM_MACH1	equ 0eeh
ASM_MACH0	equ 0edh

	cmp byte ptr [si],ASM_LOCKREP	;check for mnemonic flag byte
	jb aa15						;if none
	lodsb						;get the prefix
	sub al,ASM_LOCKREP			;convert to 0-9
	je aa18						;if LOCK or REP...
	cbw
	dec ax
	jz aa17						;if segment prefix (ASM_SEG)
	dec ax
	jz aa16						;if aad or aam (ASM_AAX)
	dec ax
	jz aa15_1					;if ASM_D16
	cmp al,3
	jae aa20					;if ASM_ORG or ASM_DD or ASM_DW or ASM_DB
	or [asm_mn_flags],al		;save AMF_D32 or AMF_WAIT (1 or 2)
aa15:
	jmp ab01					;now process the arguments
aa15_1:
	or [asm_mn_flags],AMF_D16
	inc si						;skip the ASM_D32 byte
	jmp ab01					;now process the arguments

aa16:
	jmp ab00

;--- segment prefix

aa17:
	lodsb			;get prefix value
	mov [aa_seg_pre],al
	mov cl,al
	or [asm_mn_flags],AMF_MSEG
	pop si			;get position in input line
	pop ax			;skip
	lodsb
	cmp al,':'
	jne aa13b
	call skipwhite
	cmp al,CR
	je @F
	cmp al,';'
	jne aa13b
@@:
	mov di,offset line_out
	mov al,cl
	stosb
	jmp aa27		;back for more

;--- LOCK or REP prefix

aa18:
	lodsb			;get prefix value
	xchg al,[aa_saved_prefix]
	cmp al,0
	jnz aa13a		;if there already was a saved prefix
	pop si
	pop ax
	lodsb
	cmp al,CR
	je @F			;if end of line
	cmp al,';'
	je @F			;if end of line (comment)
	jmp aa02		;back for more
@@:
	mov al,[aa_saved_prefix]	;just a prefix, nothing else
	mov di,offset line_out
	stosb
	jmp aa27

;--- Pseudo ops (org or db/dw/dd).

aa20:
	cmp word ptr [aa_saved_prefix],0
	jnz aa13a		;if there was a prefix or a segment: error
	pop si			;get position in input line
	sub al,3		;AX=0 if org, 1 if dd, 2 if dw, 3 if db.
	jnz aa20m		;if not ORG

;--- Process ORG pseudo op.

	call skipwhite
	cmp al,CR
	je @F				;if nothing
	mov bx,[a_addr+4]	;default segment
	jmp aa00a			;go to top
@@:
	jmp aa01			;get next line

;--- Data instructions (DB/DW/DD).

aa20m:
	mov di,offset line_out	;put the bytes here when we get them
	xchg ax,bx				;mov bx,ax
	shl bx,1
	mov bp,[bx+aadbsto-2]	;get address of storage routine
	call skipwhite
	cmp al,CR
	je aa27				;if end of line

aa21:					;<--- loop
	cmp al,'"'
	je aa22				;if string
	cmp al,"'"
	je aa22				;if string
	call aageti			;get a numerical value into dx:bx, size into cl
	cmp cl,cs:[bp-1]	;compare with size
	jg aa24				;if overflow
	xchg ax,bx
	call bp				;store value in AL/AX/DX:AX
	cmp di,offset real_end
	ja aa24				;if output line overflow
	xchg ax,bx
	jmp aa26			;done with this one

aa22:
	mov ah,al
aa23:
	lodsb
	cmp al,CR
	je aa24			;if end of line
	cmp al,ah
	je aa25			;if end of string
	stosb
	cmp di,offset real_end
	jbe aa23		;if output line not overflowing
aa24:
	jmp aa13b		;error
aa25:
	lodsb
aa26:
	call skipcomm0
	cmp al,CR
	jne aa21		;if not end of line

;--- End of line.  Copy it to debuggee's memory

aa27:
	mov si,offset line_out
	mov bx,[a_addr+4]
	sizeprfX	;mov edx, [a_addr+0]
	mov dx,[a_addr+0]
	mov cx,di
	sub cx,si
	call writeasmn
	sizeprfX	;mov [a_addr+0],edx
	mov [a_addr+0],dx
	jmp aa01

CONST segment
;--- table for routine to store a number ( index dd=1,dw=2,db=3 )
aadbsto dw sto_dd,sto_dw,sto_db
CONST ends

;--- Routines to store a byte/word/dword.

	db 4            ;size to store
sto_dd:
	stosw			;store a dword value
	xchg ax,dx
	stosw
	xchg ax,dx
	ret
	db 2            ;size to store
sto_dw:
	stosw			;store a word value
	ret
	db 1            ;size to store
sto_db:
	stosb			;store a byte value
	ret

;   Here we process the AAD and AAM instructions.  They are special
;   in that they may take a one-byte argument, or none (in which case
;   the argument defaults to 0ah = ten).

ab00:
	mov [mneminfo],si	;save this address
	pop si
	lodsb
	cmp al,CR
	je ab00a		;if end of line
	cmp al,';'
	jne ab01b		;if not end of line
ab00a:
	mov si,offset aam_args	;fake a 0ah argument
	jmp ab01a

;--- Process normal instructions.

;   First we parse each argument into a 12-byte data block (OPRND), stored
;   consecutively at line_out, line_out+12, etc.
;   This is stored in an OPRND struct:

;   [di+2]: Size argument, if any (1=byte, 2=word, 3=(unused), 4=dword,
;           5=qword, 6=float, 7=double, 8=tbyte, 9=short, 10=long, 11=near,
;           12=far), see SIZ_xxx and sizetcnam
;   [di+3]  Size of MOD R/M displacement
;   [di+4]  First register, or MOD R/M byte, or num of additional bytes
;   [di+5]  Second register or index register or SIB byte
;   [di+6]  Index factor
;   [di+7]  Sizes of numbers are or-ed here
;   [di+8]  (dword) number

;   For arguments of the form xxxx:yyyyyyyy, xxxx is stored in <num2>,
;   and yyyyyyyy in <num>.  The number of bytes in yyyyyyyy is stored in
;   opaddr, 2 is stored in <numadd>, and di is stored in xxaddr.

OPRND struc
flags	db ?	;+0 ARG_xxx Flags (ARG_DEREF, etc.)
		db ?	;+1 unused   
sizearg	db ?	;+2
sizedis	db ?	;+3 Size of MOD R/M displacement
union
reg1	db ?	;+4 First register, or MOD R/M byte
numadd	db ?	;+4 (additional bytes, stored at num2 (up to 4)
ends
union
struct
reg2	db ?	;+5 Second register or index register or SIB byte
index	db ?	;+6 Index factor
ends
num2	dw ?	;+5
ends
orednum	db ?	;+7
num		dd ?	;+8
OPRND ends

ab01:
	mov [mneminfo],si	;save this address
	pop si				;get position in line
ab01a:
	lodsb
ab01b:
	mov di,offset line_out

;--- Begin loop over operands.

ab02:               ;<--- next operand
	cmp al,CR
	je ab03			;if end of line
	cmp al,';'
	jne ab04		;if not end of line
ab03:
	jmp ab99		;to next phase

ab04:
	push di			;clear out the current OPRND storage area
	mov cx,sizeof OPRND / 2
	xor ax,ax
	rep stosw
	pop di

;--- check for size qualifiers, "PTR" or segment prefixes.

ab05:
	dec si
	mov ax,[si]
	and ax,TOUPPER_W
	cmp [di].OPRND.sizearg,SIZ_NONE
	jne ab07		;if already have a size qualifier ("BYTE PTR",...)
	push di
	mov di,offset sizetcnam
	mov cx,sizeof sizetcnam / 2
	repne scasw
	pop di
	jne ab07		;if not found
	or cx,cx
	jnz @F			;if not 'FA'
	mov al,[si+2]
	and al,TOUPPER
	cmp al,'R'
	jne ab09		;if not 'FAR' (could be hexadecimal)
@@:
	sub cl,sizeof sizetcnam / 2
	neg cl			;convert to 1, ..., 12
	mov [di].OPRND.sizearg,cl
	call skipalphanum	;skip the rest of the size qualifier and white space
	mov ah,[si]
	and ax,TOUPPER_W
	cmp ax,'TP'
	jne ab05		;if not 'PTR'
	call skipalphanum	;skip the rest of "PTR" and white space
	jmp ab05

;--- not a size qualifier or "PTR"

ab07:
	cmp [aa_seg_pre],0
	jne ab09		;if we already have a segment prefix
	push di
	mov di,offset segrgnam
	mov cx,N_SEGREGS
	repne scasw
	pop di
	jne ab09		;if not found
	push si			;save si in case there's no colon
	lodsw
	call skipwhite
	cmp al,':'
	jne ab08		;if not followed by ':'
	pop ax			;discard saved si
	call skipwhite	;skip it
	mov bx,offset prefixlist + 5
	sub bx,cx
	mov al,[bx]		;look up the prefix byte
	mov [aa_seg_pre],al	;save it away
	jmp ab05
ab08:
	pop si

;--- Begin parsing main part of argument.

;--- first check registers

ab09:
	push di			;check for solo registers
	mov di,offset rgnam816
	mov cx,N_ALLREGS;8+16bit regs, segment regs, special regs
	call aagetreg
	pop di
	jc ab14			;if not a register
	or [di].OPRND.flags, ARG_JUSTREG
	mov [di].OPRND.reg1,bl	;save register number
	cmp bl,24		;0-23 = AL-DH, AX-DI, EAX-EDI (REG_NO_GPR)
	jae @F			;if it's not a normal register
	xchg ax,bx		;mov al,bl
	mov cl,3
	shr al,cl		;al = size:  0 -> byte, 1 -> word, 2 -> dword
	add al,-2
	adc al,3		;convert to 1, 2, 4 (respectively)
	jmp ab13
@@:
	xor [di].OPRND.flags, ARG_JUSTREG + ARG_WEIRDREG
	mov al,SIZ_WORD	;register size
	cmp bl,REG_ST
	ja ab11			;if it's MM, CR, DR or TR
	je @F			;if it's ST
	cmp bl,28		;24-27 are ES,CS,SS,DS (segrgnam)
	jb ab13			;if it's a normal segment register
	or [asm_mn_flags],AMF_FSGS	;flag it
	jmp ab13
@@:
	cmp byte ptr [si],'('
	jne ab12		;if just plain ST
	lodsb
	lodsb
	sub al,'0'
	cmp al,7
	ja ab10			;if not 0..7
	mov [di].OPRND.reg2,al	;save the number
	lodsb
	cmp al,')'
	je ab12			;if not error
ab10:
	jmp aa13b		;error

;--- other registers 31-34 (MM, CR, DR, TR)

ab11:
	lodsb
	sub al,'0'
	cmp al,7
	ja ab10			;if error
	mov [di].OPRND.reg2,al	;save the number
	mov al,SIZ_DWORD;register size
	cmp bl,REG_MM
	jne ab13		;if not MM register
	or [di].OPRND.flags, ARG_JUSTREG
	mov al,SIZ_QWORD
	jmp ab13
ab12:
	mov al,0		;size for ST regs
ab13:
	cmp al,[di].OPRND.sizearg	;compare with stated size
	je @F			;if same
	xchg al,[di].OPRND.sizearg
	cmp al,0
	jne ab10		;if wrong size given - error
@@:
	jmp ab44		;done with this operand

;--- It's not a register reference.  Try for a number.

ab14:
	lodsb
	call aaifnum
	jc ab17			;it's not a number
	call aageti		;get the number
	mov [di].OPRND.orednum,cl
	mov word ptr [di].OPRND.num+0,bx
	mov word ptr [di].OPRND.num+2,dx
	call skipwh0
	cmp cl,2
	jg ab17			;if we can't have a colon here
	cmp al,':'
	jne ab17		;if not xxxx:yyyy
if 1	;v2.50: size for ssss:oooo must be none or far
	cmp [di].OPRND.sizearg, SIZ_NONE
	jz @F
	cmp [di].OPRND.sizearg, SIZ_FAR
	jnz ab24
@@:
endif
	call skipwhite
	call aageti
	mov cx,word ptr [di].OPRND.num+0
	mov [di].OPRND.num2,cx
	mov word ptr [di].OPRND.num+0,bx
	mov word ptr [di].OPRND.num+2,dx
	or [di].OPRND.flags, ARG_FARADDR
	jmp ab43		;done with this operand

;--- Check for [...].

ab15:
	jmp ab30		;do post-processing

ab16:
	call skipwhite
ab17:
	cmp al,'['		;begin loop over sets of []
	jne ab15		;if not [
	or [di].OPRND.flags, ARG_DEREF ;set the flag
ab18:
	call skipwhite
ab19:
	cmp al,']'		;begin loop within []
	je ab16			;if done

;--- Check for a register (within []).

	dec si
	push di
	mov di,offset rgnam16
	mov cx,N_REGS16
	call aagetreg
	pop di
	jc ab25			;if not a register
	cmp bl,16
	jae @F			;if 32-bit register
	add bl,8		;adjust 0..7 to 8..15
	jmp ab21
@@:
	cmp [di].OPRND.reg2, 0
	jnz ab21		;if we already have an index
	call skipwhite
	dec si
	cmp al,'*'
	jne ab21		;if not followed by '*'
	inc si
	mov [di].OPRND.reg2,bl	;save index register
	call skipwhite
	call aageti
	call aaconvindex
	jmp ab28		;ready for next part

ab21:
	cmp [di].OPRND.reg1,0
	jne @F			;if there's already a register
	mov [di].OPRND.reg1,bl
	jmp ab23
@@:
	cmp [di].OPRND.reg2, 0
	jne ab24		;if too many registers
	mov [di].OPRND.reg2,bl
ab23:
	call skipwhite
	jmp ab28		;ready for next part
ab24:
	jmp aa13b		;error

;--- Try for a number (within []).

ab25:
	lodsb
ab26:
	call aageti		;get a number (or flag an error)
	call skipwh0
	cmp al,'*'
	je ab27			;if it's an index factor
	or [di].OPRND.orednum,cl
	add word ptr [di].OPRND.num+0,bx
	adc word ptr [di].OPRND.num+2,dx
	jmp ab28		;next part ...

ab27:
	call aaconvindex
	call skipwhite
	dec si
	push di
	mov di,offset rgnam16
	xor cx,cx
	call aagetreg
	pop di
	jc ab24			;if error
	cmp [di].OPRND.reg2, 0
	jne ab24		;if there is already a register
	mov [di].OPRND.reg2, bl
	call skipwhite

;--- Ready for the next term within [].

ab28:
	cmp al,'-'
	je ab26			;if a (negative) number is next
	cmp al,'+'
	jne @F			;if no next term (presumably)
	jmp ab18
@@:
	jmp ab19		;back for more

;--- Post-processing for complicated arguments.

ab30:
	cmp word ptr [di].OPRND.reg1,0	;check both reg1+reg2
	jnz ab32		;if registers were given ( ==> create MOD R/M)
	cmp [di].OPRND.orednum,0
	jz ab31			;if nothing was given ( ==> error)
	cmp [di].OPRND.flags,0
	jnz ab30b		;if it was not immediate
	or [di].OPRND.flags,ARG_IMMED
ab30a:
	jmp ab43		;done with this argument
ab30b:
	or [asm_mn_flags],AMF_ADDR
	mov al,2		;size of the displacement
	test [di].OPRND.orednum,4
	jz @F			;if not 32-bit displacement
	inc ax
	inc ax
	or [asm_mn_flags],AMF_A32	;32-bit addressing
@@:
	mov [di].OPRND.sizedis,al	;save displacement size
	jmp ab30a		;done with this argument
ab31:
	jmp aa13b		;flag an error

;   Create the MOD R/M byte.
;   (For disp-only or register, this will be done later as needed.)

ab32:
	or [di].OPRND.flags, ARG_MODRM
	mov al,[di].OPRND.reg1
	or al,[di].OPRND.reg2
	test al,16
	jnz ab34		;if 32-bit addressing
	test [di].OPRND.orednum,4
	jnz ab34		;if 32-bit addressing
;	or [asm_mn_flags], AMF_ADDR | AMF_A32
	or [asm_mn_flags], AMF_ADDR
	mov ax,word ptr [di].OPRND.reg1	;get reg1+reg2
	cmp al,ah
	ja @F			;make sure al >= ah
	xchg al,ah
@@:
	push di
	mov di,offset modrmtab
	mov cx,8
	repne scasw
	pop di
	jne ab31		;if not among the possibilities
	mov bx,206h		;max disp = 2 bytes; 6 ==> (non-existent) [bp]
	jmp ab39		;done (just about)

;--- 32-bit addressing

ab34:
	or [asm_mn_flags],AMF_A32 + AMF_ADDR
	mov al,[di].OPRND.reg1
	or al,[di].OPRND.index
	jnz @F			;if we can't optimize [EXX*1] to [EXX]
	mov ax,word ptr [di].OPRND.reg1	;get reg1+reg2
	xchg al,ah
	mov word ptr [di].OPRND.reg1,ax
@@:
	mov bx,405h		;max disp = 4 bytes; 5 ==> (non-existent) [bp]
	cmp [di].OPRND.reg2,0
	jne @F			;if there's a SIB
	mov cl,[di].OPRND.reg1
	cmp cl,16
	jl ab31			;if wrong register type
	and cl,7
	cmp cl,4		;check for ESP
	jne ab39		;if not, then we're done (otherwise do SIB)
@@:
	or [asm_mn_flags],AMF_SIB	;form SIB
	mov ch,[di].OPRND.index		;get SS bits
	mov cl,3
	shl ch,cl				;shift them halfway into place
	mov al,[di].OPRND.reg2	;index register
	cmp al,20
	je ab31			;if ESP ( ==> error)
	cmp al,0
	jne @F			;if not zero
	mov al,20		;set it for index byte 4
@@:
	cmp al,16
	jl ab31			;if wrong register type
	and al,7
	or ch,al		;put it into the SIB
	shl ch,cl		;shift it into place
	inc cx			;R/M for SIB = 4
	mov al,[di].OPRND.reg1	;now get the low 3 bits
	cmp al,0
	jne @F			;if there was a first register
	or ch,5
	jmp ab42		;MOD = 0, disp is 4 bytes
@@:
	cmp al,16
	jl ab45			;if wrong register type
	and al,7		;first register
	or ch,al		;put it into the SIB
	cmp al,5
	je ab40			;if it's EBP, then we don't recognize disp=0
					;otherwise bl will be set to 0

;--- Find the size of the displacement.

ab39:
	cmp cl,bl
	je ab40			;if it's [(E)BP], then disp=0 is still 1 byte
	mov bl,0		;allow 0-byte disp

ab40:
	push cx
	mov al,byte ptr [di].OPRND.num+0
	mov cl,7
	sar al,cl
	pop cx
	mov ah,byte ptr [di].OPRND.num+1
	cmp al,ah
	jne @F			;if it's bigger than 1 byte
	cmp ax,word ptr [di].OPRND.num+2
	jne @F			;ditto
	mov bh,0		;no displacement
	or bl,byte ptr [di].OPRND.num+0
	jz ab42			;if disp = 0 and it's not (E)BP
	inc bh			;disp = 1 byte
	or cl,40h		;set MOD = 1
	jmp ab42		;done
@@:
	or cl,80h		;set MOD = 2
ab42:
	mov [di].OPRND.sizedis,bh	;store displacement size
	mov word ptr [di].OPRND.reg1, cx	;store MOD R/M and maybe SIB

;--- Finish up with the operand.

ab43:
	dec si
ab44:
	call skipwhite
	add di,sizeof OPRND
	cmp al,CR
	je ab99			;if end of line
	cmp al,';'
	je ab99			;if comment (ditto)
	cmp al,','
	jne ab45		;if not comma ( ==> error)
	cmp di,offset line_out+ 3 * sizeof OPRND
	jae ab45		;if too many operands
	call skipwhite
	jmp ab02

ab45:
	jmp aa13b		;error jump

ab99:
	mov [di].OPRND.flags,-1;end of parsing phase
	push si			;save the location of the end of the string

;   For the next phase, we match the parsed arguments with the set of
;   permissible argument lists for the opcode.  The first match wins.
;   Therefore the argument lists should be ordered such that the
;   cheaper ones come first.

;   There is a tricky issue regarding sizes of memory references.
;   Here are the rules:
;      1.   If a memory reference is given with a size, then it's OK.
;      2.   If a memory reference is given without a size, but some
;       other argument is a register (which implies a size),
;       then the memory reference inherits that size.
;           Exceptions: OP_CL does not imply a size
;                   OP_SHOSIZ
;      3.   If 1 and 2 do not apply, but this is the last possible argument
;       list, and if the argument list requires a particular size, then
;       that size is used.
;      4.   In all other cases, flag an error.

ac01:				;<--- next possible argument list
	xor ax,ax
	mov di,offset ai
	mov cx,sizeof ai/2
	rep stosw
	mov si,[mneminfo]	;address of the argument variant

;--- Sort out initial bytes.  At this point:
;--- si = address of argument variant

ac02:               ;<--- next byte of argument variant
	lodsb
	sub al,ASM_MACH0
	jb ac05			;if no more special bytes
	cmp al,ASM_LOCKABLE - ASM_MACH0
	je @F			;if ASM_LOCKABLE
	ja ac04			;if ASM_END ( ==> error)
	mov [ai.dismach],al;save machine type
	jmp ac02		;back for next byte
@@:
	or [ai.varflags],VAR_LOCKABLE
	jmp ac02		;back for next byte

ac04:
	jmp aa13a		;error

;--- Get and unpack the word.

ac05:
	dec si
	lodsw
	xchg al,ah			;put into little-endian order
	xor dx,dx
	mov bx,ASMMOD
	div bx				;ax = a_opcode; dx = index into opindex
	mov [a_opcode],ax	;save ax
	mov [a_opcode2],ax	;save the second copy
	cmp ax,0dfh
	ja @F				;if not coprocessor instruction
	cmp al,0d8h
	jb @F				;ditto
	or [ai.dmflags],DM_COPR;flag it as an x87 instruction
	mov ah,al			;ah = low order byte of opcode
	lodsb				;get extra byte
	mov [ai.regmem],al		;save it in regmem
	mov [a_opcode2],ax	;save this for obsolete-instruction detection
	or [ai.varflags],VAR_MODRM	;flag its presence
@@:
	mov [mneminfo],si	;save si back again
	mov si,dx
	@dprintf "ac05: opindex=%X", si
	mov ax,word ptr [opindex+si]
	mov bl,al
	mov [bEndOplItem], ah	; end of oplist item

	lea si,[oplists+bx]		;si = the address of our operand list
	mov di,offset line_out	;di = array of OPRNDs

;--- Begin loop over operands.

ac06:               ;<--- next operand
	mov ax, si
	sub ax, offset oplists
	cmp al, [bEndOplItem]
	jae ac10
	lodsb			;get next operand byte
;	cmp al,0
;	je ac10			;if end of list
	cmp [di].OPRND.flags,-1
	je ac01			;if too few operands were given
	cmp al,OP_SIZE
	jb @F			;if no size needed
;	mov ah,0
;	mov cl,4
;	shl ax,cl		;move bits 4-7 (size) to ah (OP_1632=5,OP_8=6,OP_16=7,...)
;	shr al,cl		;move bits 0-3 back
	db 0d4h,10h		;=aam 10h (AX=00XY -> AX=0X0Y)
	mov [ai.reqsize],ah	;save size away
	@dprintf "ac08: di=%X size requested, AH in AX=%X", di, ax
	jmp ac08
@@:					;AL = OP_M64 - ...
	add al,ASM_OPOFF - OP_M64	;adjust for the start entries im asm_jmp1
ac08:
	cbw
	xchg ax,bx		;now bx contains the offset
	mov cx,[asm_jmp1+bx] ;subroutine address
	shr bx,1
	mov al,[bittab+bx]
	@dprintf "ac08: di=%X si=%X, offset=%X, func=%X, al=%X", di, si, bx, cx, ax
	test al,[di].OPRND.flags
	jz ac09			;if no required bits are present
	call cx			;call its specific routine
	cmp word ptr [si-1], (OP_1632 + OP_R) * 256 + (OP_1632 + OP_R_MOD)
	je ac06			;(hack) for IMUL instruction
	add di,sizeof OPRND	;next operand
	jmp ac06		;back for more

ac09:
	jmp ac01		;back to next possibility

;--- End of operand list.

ac10:
	cmp [di].OPRND.flags,-1
	jne ac09		;if too many operands were given

;--- Final check on sizes

	mov al,[ai.varflags]
	test al,VAR_SIZ_NEED
	jz ac12			;if no size needed
	test al,VAR_SIZ_GIVN
	jnz ac12		;if a size was given
	test al,VAR_SIZ_FORCD
	jz ac09			;if the size was not forced ( ==> reject)
	mov si,[mneminfo]
	cmp byte ptr [si],ASM_END
	je ac12			;if this is the last one
ac11:
	jmp aa13a		;it was not ==> error (not a retry)

;--- Check other prefixes.

ac12:
	mov al,[aa_saved_prefix]
	cmp al,0
	jz ac14			;if no saved prefixes to check
	cmp al,0f0h
	jne @F			;if it's a rep prefix
	test [ai.varflags],VAR_LOCKABLE
	jz ac11			;if this variant is not lockable - error
	jmp ac14		;done
@@:
	mov ax,[a_opcode]	;check if opcode is OK for rep{,z,nz}
	and al,not 1		;clear low order bit (MOVSW -> MOVSB)
	cmp ax,0ffh
	ja ac11				;if it's not a 1 byte instruction - error
	mov di,offset replist	;list of instructions that go with rep
	mov cx,N_REPALL			;scan all (REP + REPxx)
	repne scasb
	jnz ac11			;if it's not among them - error

ac14:
	test [asm_mn_flags],AMF_MSEG
	jz @F				;if no segment prefix before mnemonic
	mov ax,[a_opcode]	;check if opcode allows this
	cmp ax,0ffh
	ja ac11				;if it's not a 1 byte instruction - error
	mov di,offset prfxtab
	mov cx,N_PRFXTAB
	repne scasb
	jnz ac11			;if it's not in the list - error
@@:
	mov bx,[ai.immaddr]
	or bx,bx
	jz ac16			;if no immediate data
	mov al,[ai.opsize]
	neg al
	shl al,1
	test al,[bx+7]
	jnz ac11		;if the immediate data was too big - error

;   Put the instruction together
;   (maybe is this why they call it an assembler)

;   First, the prefixes (including preceding WAIT instruction)

ac16:
	sizeprfX	;mov edx,[a_addr]
	mov dx,[a_addr+0]
	mov bx,[a_addr+4]
	test [asm_mn_flags],AMF_WAIT
	jz @F			;if no wait instruction beforehand
	mov al,9bh
	call writeasm
@@:
	mov al,[aa_saved_prefix]
	cmp al,0
	jz @F			;if no LOCK or REP prefix
	call writeasm
@@:

;--- a 67h address size prefix is needed
;--- 1. for CS32: if AMF_ADDR=1 and AMF_A32=1
;--- 2. for CS16: if AMF_ADDR=1 and AMF_A32=0

	mov al,[asm_mn_flags]
	test al,AMF_ADDR
	jz @F
	and al,AMF_A32
if ?PM
	mov ah,[bCSAttr]
	and ah,40h
	or al,ah
endif
	and al,AMF_A32 + 40h
	jz @F
	cmp al,AMF_A32 + 40h
	jz @F
	@dprintf "ac20: 67h prefix"
	mov al,67h
	call writeasm
@@:

;--- a 66h data size prefix is needed
;--- for CS16: if VAR_D32 == 1 or AMF_D32 == 1
;--- for CS32: if VAR_D16 == 1 or AMF_D16 == 1

	mov ah,[asm_mn_flags]
	mov al,[ai.varflags]
if ?PM
	test [bCSAttr],40h
	jz @F
	test al, VAR_D16
	jnz ac20_1
	test ah, AMF_D16
	jnz ac20_1
	jmp ac21
@@:
endif
	test al,VAR_D32
	jnz ac20_1
	test ah,AMF_D32
	jz ac21
ac20_1:
	@dprintf "ac20: 66h prefix"
	mov al,66h
	call writeasm		;store operand-size prefix
ac21:
	mov al,[aa_seg_pre]
	cmp al,0
	jz @F			;if no segment prefix
	call writeasm
	cmp al,64h
	jb @F			;if not 64 or 65 (FS or GS)
	or [asm_mn_flags],AMF_FSGS	;flag it
@@:

;--- Now emit the instruction itself.

	mov ax,[a_opcode]
	mov di,ax
	sub di,240h
	jae @F			;if 576-...
	cmp ax,200h
	jb ac24			;if regular instruction
	or [ai.dmflags],DM_COPR	;flag it as an x87 instruction
	and al,038h		;get register part
	@dprintf "ac21: fpu instr (>200h), update ai.regmem with AL=%X", ax
	or [ai.regmem],al
	xchg ax,di		;mov ax,di (the low bits of di are good)
	and al,7
	or al,0d8h
	jmp ac25		;on to decoding the instruction
@@:
	mov cl,3		;one instruction of a group
	shr di,cl
	and al,7
	shl al,cl
	@dprintf "ac21: grp-instr (%X), update ai.regmem with AL=%X", a_opcode, ax
	or [ai.regmem],al
	shl di,1
	mov ax,[agroups+di]	;get actual opcode

ac24:
	cmp ah,0
	jz ac25			;if no 0fh first
	push ax			;store a 0fh
	@dprintf "ac24: 0F prefix"
	mov al,0fh
	call writeasm
	pop ax

ac25:
	@dprintf "ac25: instruction byte: %X", ax
	or al,[ai.opcode_or]	;put additional bits into the op code
	call writeasm		;store the op code itself

;--- Now store the extra stuff that comes with the instruction.

	mov ax,word ptr [ai.regmem]
	test [ai.varflags],VAR_MODRM
	jz @F			;if no mod reg/mem
	@dprintf "ac25: modrm %X (ai.regmem)", ax
	push ax
	call writeasm
	pop ax
	test [asm_mn_flags],AMF_SIB
	jz @F			;if no SIB
	mov al,ah
	@dprintf "ac25: sib in AL %X", ax
	call writeasm	;store the MOD R/M and SIB, too
@@:

	mov di,[ai.rmaddr]
	or di,di
	jz @F			;if no offset associated with the R/M
	mov cl,[di].OPRND.sizedis
	mov ch,0
	lea si,[di].OPRND.num	;store the R/M offset (or memory offset)
	@dprintf "ac25: mem offs, size=%X ofs=%X", cx, word ptr [di].OPRND.num
	call writeasmn
@@:

;--- Now store immediate data

	mov di,[ai.immaddr]
	or di,di
	jz @F			;if no immediate data
	mov al,[ai.opsize]
	cbw
	xchg ax,cx		;mov cx,ax
	@dprintf "ac25: imm data, size=%X data=%X", cx, word ptr [di].OPRND.num
	lea si,[di].OPRND.num
	call writeasmn
@@:

;--- Now store additional bytes (needed for, e.g., enter instruction)
;--- also for FAR memory address

	mov di,[ai.xxaddr]
	or di,di
	jz @F			;if no additional data
	lea si,[di].OPRND.numadd	;number of bytes (2 for FAR, size of segment)
	lodsb
	cbw
	xchg ax,cx		;mov cx,ax
	@dprintf "ac25: additional data=%X", cx
	call writeasmn
@@:

;--- Done emitting. Update asm address offset.

	sizeprfX	;mov [a_addr],edx
	mov [a_addr],dx

;--- Compute machine type.

	cmp [ai.dismach],3
	jae ac31		;if we already know a 386 is needed
	test [asm_mn_flags], AMF_D32 or AMF_A32 or AMF_FSGS
	jnz ac30		;if 386
	test [ai.varflags],VAR_D32
	jz ac31			;if not 386
ac30:
	mov [ai.dismach],3
ac31:
	mov di,offset a_obstab	;obsolete instruction table
	mov cx,[a_opcode2]
	call showmach		;get machine message into si, length into cx
	jcxz ac33			;if no message

ac32:
	mov di,offset line_out
	rep movsb		;copy the line to line_out
	call putsline

ac33:
	jmp aa01		;back for the next input line

if 0
;--- This is debugging code.  It assumes that the original value
;--- of a_addr is on the top of the stack.

	pop si		;get orig. a_addr
	mov ax,[a_addr+4]
	mov [u_addr+0],si
	mov [u_addr+4],ax
	mov bx,[a_addr]
	sub bx,si
	mov di,offset line_out
	mov cx,10
	mov al,' '
	rep stosb
	mov ds,[a_addr+4]
@@:
	lodsb
	call hexbyte	;display the bytes generated
	dec bx
	jnz @B
	push ss
	pop ds
	call putsline
	call disasm1	;disassemble the new instruction
	jmp aa01		;back to next input line
endif

CONST segment

	align 2

;--- Jump table for operand types.
;--- order of entries in asm_jmp1 must match 
;--- the one in dis_jmp1 / dis_optab.

asm_jmp1 label word
	dw aop_imm, aop_rm, aop_m, aop_r_mod	;OP_IMM, OP_RM, OP_M, OP_R_MOD
	dw aop_moffs, aop_r, aop_r_add, aop_ax	;OP_MOFFS, OP_R, OP_R_ADD, OP_AX
ASM_OPOFF equ $ - asm_jmp1

;--- order must match the one in dis_optab
	dw ao17, ao17, ao17		;OP_M64, OP_MFLOAT, OP_MDOUBLE
	dw ao17, ao17, ao17		;OP_M80, OP_MXX, OP_FARMEM
	dw aop_farimm, aop_rel8, aop_rel1632;OP_FARIMM, OP_REL8, OP_REL1632
	dw ao29, aop_sti, aop_cr	;OP_1CHK, OP_STI, OP_CR
	dw ao34, ao35, ao39		;OP_DR, OP_TR, OP_SEGREG
	dw ao41, ao42, aop_mmx	;OP_IMMS8, OP_IMM8, OP_MMX
	dw ao44, ao46, ao47		;OP_SHOSIZ, OP_1, OP_3
	dw ao48, ao48, ao48		;OP_DX, OP_CL, OP_ST
	dw ao48, ao48, ao48		;OP_CS, OP_DS, OP_ES
	dw ao48, ao48, ao48		;OP_FS, OP_GS, OP_SS

CONST ends

;   Routines to check for specific operand types.
;   Upon success, the routine returns.
;   Upon failure, it pops the return address and jumps to ac01.
;   The routines must preserve si and di.

;--- OP_RM, OP_M, OP_R_MOD:  form MOD R/M byte.

aop_rm:
aop_m:
aop_r_mod:
	call ao90		;form reg/mem byte
	jmp ao07		;go to the size check

;--- OP_R:  register.

aop_r:
	mov al,[di].OPRND.reg1	;register number
	and al,7
	mov cl,3
	shl al,cl		;shift it into place
	or [ai.regmem],al	;put it into the reg/mem byte
	jmp ao07		;go to the size check

;--- OP_R_ADD:  register, added to the instruction.

aop_r_add:
	mov al,[di].OPRND.reg1
	and al,7
	mov [ai.opcode_or],al	;put it there
	jmp ao07		;go to the size check

;--- OP_IMM:  immediate data.

aop_imm:
	mov [ai.immaddr],di	;save the location of this
	jmp ao07		;go to the size check

;--- OP_MOFFS:  just the memory offset

aop_moffs:
	test [di].OPRND.flags,ARG_MODRM
	jnz ao11		;if MOD R/M byte ( ==> reject)
	mov [ai.rmaddr],di	;save the operand pointer
	jmp ao07		;go to the size check

;--- OP_AX:  check for AL/AX/EAX

aop_ax:
	test [di].OPRND.reg1,7
	jnz ao11		;if wrong register
	;jmp ao07		;go to the size check

;--- Size check

ao07:               ;<--- entry for OP_RM, OP_M, OP_R_MOD, OP_R, OP_R_ADD...
	or [ai.varflags],VAR_SIZ_NEED
	@dprintf "ao07: size check, reqsizeB=%X, sizeargB=%X", word ptr ai.reqsize, word ptr [di].OPRND.sizearg
	mov al,[ai.reqsize]	;4 OP_ALL, 5 OP_1632, 6 OP_8, 7 OP_16, 8 OP_32, 9 OP_64
	sub al,5
	jl ao12			;if OP_ALL
	jz ao13			;if OP_1632
;--- OP_8=1, OP_16=2, OP_32=3, OP_64=4
	add al,-3
	adc al,3		;convert 3 --> 4 and 4 --> 5

ao08:               ;<--- entry for OP_M64 ... OP_FARMEM
	or [ai.varflags],VAR_SIZ_FORCD + VAR_SIZ_NEED
ao08_1:
	mov bl,[di].OPRND.sizearg
	@dprintf "ao08_1: BL=%X AL=%X ai.opsize=%X", bx, ax, word ptr ai.opsize
	or bl,bl
	jz @F			;if no size given
	or [ai.varflags],VAR_SIZ_GIVN
	cmp al,bl
	jne ao11		;if sizes conflict
@@:
	cmp al,[ai.opsize]
	je @F			;if sizes agree
	xchg al,[ai.opsize]
	cmp al,0
	jnz ao11		;if sizes disagree
;--- v2.50: the next line caused - as a side effect - a regression for "call [xxxx]"
;--- which has been fixed at ao13.
	or [ai.varflags],VAR_SIZ_GIVN	;v1.18 added!!!
@@:
	ret

ao11:
	jmp ao50		;reject

;--- OP_ALL - Allow all sizes.

ao12:
	mov al,[di].OPRND.sizearg
	cmp al,SIZ_BYTE
	je ao15			;if byte
	jb ao14			;if unknown
	or [ai.opcode_or],1;set bit in instruction
	jmp ao14		;if size is 16 or 32

ao13:				;<--- OP_1632 - word or dword.
	mov al,[di].OPRND.sizearg
	@dprintf "ao13: OP_1632, AL=sizearg=%X, dx=%X", ax, dx
if 1	;v2.50: set default size for call/jmp/push [mem] (hackish fix)
	cmp al,SIZ_NONE
	jnz @F
	cmp dx, 40		;just opindex 40 ( call/jmp/push [memref] )   
	jnz @F
	mov al,SIZ_WORD
 if ?PM
	test [bCSAttr],40h
	jz @F
	mov al,SIZ_DWORD
 endif
@@:
endif
ao14:
	cmp al,SIZ_NONE
	je ao16			;if still unknown
	cmp al,SIZ_WORD
	jne @F			;if word
	or [ai.varflags],VAR_D16
	jmp ao15
@@:
	cmp al,SIZ_DWORD
	jne ao11		;if not dword
	or [ai.varflags],VAR_D32
ao15:
	mov [ai.opsize],al
	or [ai.varflags],VAR_SIZ_GIVN
ao16:
	ret

;   OP_M64 - 64-bit memory reference.
;   OP_MFLOAT - single-precision floating point memory reference.
;   OP_MDOUBLE - double-precision floating point memory reference.
;   OP_M80 - 80-bit memory reference.
;   OP_MXX - memory reference, size unknown.
;   OP_FARMEM - far memory pointer

;--- bx contains byte index for bittab
ao17:
	call ao90		;form reg/mem byte
	mov al,[asm_siznum + bx - ASM_OPOFF/2]
	@dprintf "ao17: bx=%X al=%X ai.opsiz=%X [di].sizearg=%X", bx, ax, word ptr ai.opsize, word ptr [di].OPRND.sizearg
	jmp ao08		;check size

;--- OP_FARIMM - far address contained in instruction

aop_farimm:
if ?PM
	test [bCSAttr],40h
	jnz @F
endif
	mov al,2
	cmp word ptr [di].OPRND.num+2,0
	jz ao22			;if 16 bit address
@@:
	or [ai.varflags],VAR_D32
	mov al,4
ao22:
	mov [di].OPRND.numadd,2	;2 additional bytes (segment part)
	mov [ai.immaddr],di
	mov [ai.opsize],al			;2/4, size of offset
ao22_1:
	mov [ai.xxaddr],di
	ret

;--- OP_REL8 - relative address
;--- Jcc, LOOPx, JxCXZ

aop_rel8:
	mov al,SIZ_SHORT
	call aasizchk	;check the size
	mov cx,2		;size of instruction
	mov al,[asm_mn_flags]

	test al,AMF_D32 or AMF_D16
	jz ao23_1		;if not JxCXZ, LOOPx
	test al,AMF_D32
	jz @F
	or al,AMF_A32	; JxCXZ and LOOPx need a 67h, not a 66h prefix
@@:
	and al,not (AMF_D32 or AMF_D16)
	or al, AMF_ADDR
	mov [asm_mn_flags],al
if ?PM
	mov ah,[bCSAttr]
	and ah,40h
else
	mov ah,0
endif
	and al,AMF_A32
	or al,ah
	jz ao23_1
	cmp al,AMF_A32+40h
	jz ao23_1
	inc cx        ;instruction size = 3
ao23_1:
	mov bx,[a_addr+0]
	add bx,cx
	mov cx,[a_addr+2];v1.22: handle HiWord(EIP) properly
	adc cx,0
	mov ax,word ptr [di].OPRND.num+0
	mov dx,word ptr [di].OPRND.num+2
;--- CX:BX holds E/IP (=src), DX:AX holds dst
	sub ax,bx
	sbb dx,cx
	mov byte ptr [di].OPRND.num2,al
	mov cl,7        ;range must be ffffff80 <= x <= 0000007f
	sar al,cl       ;1xxxxxxxb -> FF, 0xxxxxxxb -> 00
	cmp al,ah
	jne ao_err1		;if too big
	cmp ax,dx
	jne ao_err1		;if too big
	mov [di].OPRND.numadd,1	;save the length
	jmp ao22_1		;save it away

;--- OP_REL1632:  relative jump/call to a longer address.
;--- size of instruction is
;--- a) CS 16-bit:
;---  3 (xx xxxx, jmp/call) or
;---  4 (0F xx xxxx)
;---  6 (66 xx xxxxxxxx)
;---  7 (66 0F xx xxxxxxxx)
;---
;--- b) CS 32-bit:
;---  5 (xx xxxxxxxx, jmp/call) or
;---  6 (0F xx xxxxxxxx)

aop_rel1632:
	mov bx,[a_addr+0]
	mov cx,3
	mov dx,word ptr [di].OPRND.num+2
	mov al,[di].OPRND.sizearg
	cmp [a_opcode],100h	;is a 0F xx opcode?
	jb @F
	inc cx
@@:
	cmp al,SIZ_NONE
	je @F			;if no size given
	cmp al,SIZ_DWORD
	je ao27			;if size "dword"
	cmp al,SIZ_LONG
	jne ao_err1		;if not size "long"
@@:
if ?PM
	test [bCSAttr],40h
	jnz ao27
endif
	or dx,dx
	jnz ao_err1		;if operand is too big
	mov al,2        ;displacement size 2
	jmp ao28
ao27:
	mov al,4        ;displacement size 4
	or [ai.varflags],VAR_D32
	add cx,3		;add 3 to instr size (+2 for displ, +1 for 66h)
if ?PM
	test [bCSAttr],40h
	jz @F
	dec cx			;no 66h prefix byte in 32-bit code
@@:
endif
ao28:
	add bx,cx
	mov cx,[a_addr+2]
	adc cx,0
	mov [di].OPRND.numadd,al	;store size of displacement (2 or 4)
	mov ax,word ptr [di].OPRND.num+0
	sub ax,bx		;compute DX:AX - CX:BX
	sbb dx,cx
	mov [di].OPRND.num2,ax
	mov [di].OPRND.num2+2,dx
	mov [ai.xxaddr],di
	ret
ao_err1:
	jmp ao50		;reject

;--- OP_1CHK - The assembler can ignore this one.

ao29:
	pop ax			;discard return address
	jmp ac06		;next operand

;--- OP_STI - ST(I).

aop_sti:
	mov al,REG_ST	;code for ST
	mov bl,[di].OPRND.reg2
	jmp ao38		;to common code

;--- OP_MMX [previously was OP_ECX (used for LOOPx)]

aop_mmx:
	mov al,REG_MM
	jmp ao37		;to common code

;--- OP_CR

aop_cr:
	mov al,[di].OPRND.reg2	;get the index
	cmp al,4
	ja ao_err1		;if too big
	jne @F			;if not CR4
	mov [ai.dismach],5	;CR4 is new to the 586
@@:
	cmp al,1
	jne @F
	cmp [di+sizeof OPRND].OPRND.flags,-1
	jne ao_err1		;if another arg (can't mov CR1,xx)
@@:
	mov al,REG_CR	;code for CR
	jmp ao37		;to common code

;--- OP_DR

ao34:
	mov al,REG_DR	;code for DR
	jmp ao37		;to common code

;--- OP_TR

ao35:
	mov al,[di].OPRND.reg2	;get the index
	cmp al,3
	jb ao_err1		;if too small
	cmp al,6
	jae @F
	mov [ai.dismach],4	;TR3-5 are new to the 486
@@:
	mov al,REG_TR	;code for TR

;--- Common code for these weird registers.

ao37:
	mov bl,[di].OPRND.reg2
	mov cl,3
	shl bl,cl
ao38:
	or [ai.regmem],bl
	or [ai.varflags],VAR_MODRM
	cmp al,[di].OPRND.reg1	;check for the right numbered register
	je ao40			;if yes, then return
ao38a:
	jmp ao50		;reject

;--- OP_SEGREG

ao39:
	mov al,[di].OPRND.reg1
	sub al,24
	cmp al,6
	jae ao38a		;if not a segment register
	mov cl,3
	shl al,cl
	or [ai.regmem],al
;--- v1.26: don't force size for MOV sreg,mxx / MOV mxx, sreg
	or [ai.varflags], VAR_SIZ_GIVN
ao40:
	ret

;--- OP_IMMS8 - Sign-extended immediate byte (PUSH xx)

ao41:
	and [ai.varflags],not VAR_SIZ_NEED	;added for v1.09. Ok?
	mov ax,word ptr [di].OPRND.num+0
	mov cl,7
	sar al,cl
	jmp ao43		;common code

;--- OP_IMM8 - Immediate byte

ao42:
	mov ax,word ptr [di].OPRND.num+0
	mov al,0
ao43:
	cmp al,ah
	jne ao50		;if too big
	cmp ax,word ptr [di].OPRND.num+2
	jne ao50		;if too big
	mov al,SIZ_BYTE
	call aasizchk	;check that size == 0 or 1
	mov ah,byte ptr [di].OPRND.num+0
	mov word ptr [di].OPRND.numadd,ax	;store length (0/1) + the byte
	mov [ai.xxaddr],di
ao43r:
	ret

;--- OP_SHOSIZ - force the user to declare the size of the next operand

ao44:
	test [ai.varflags],VAR_SIZ_NEED
	jz ao45			;if no testing needs to be done
	test [ai.varflags],VAR_SIZ_GIVN
	jz ao50			;if size was given ( ==> reject)
ao45:
	and [ai.varflags],not VAR_SIZ_GIVN	;clear the flag
	cmp byte ptr [si],OP_IMM8
	je ao45a		;if OP_IMM8 is next, then don't set VAR_SIZ_NEED
	or [ai.varflags],VAR_SIZ_NEED
ao45a:
	mov byte ptr [ai.opsize],0
	pop ax			;discard return address
	jmp ac06		;next operand

;--- OP_1

ao46:
	cmp word ptr [di+7],101h	;check both size and value
	jmp ao49		;test it later

;--- OP_3

ao47:
	cmp word ptr [di+7],301h	;check both size and value
	jmp ao49		;test it later

;--- OP_DX, OP_CL, OP_ST, OP_CS/DS/ES/FS/GS/SS
;--- bx contains index for bittab

ao48:
	mov al,[asm_regnum+bx-(ASM_OPOFF + OP_DX - OP_M64)/2]
	cbw
	cmp ax,word ptr [di].OPRND.reg1

ao49:
	je ao51

;--- Reject this operand list.

ao50:
	pop ax			;discard return address
	jmp ac01		;go back to try the next alternative

ao51:
	ret

;--- AASIZCHK - Check that the size given is 0 or AL.

aasizchk:
	cmp [di].OPRND.sizearg,SIZ_NONE
	je ao51
	cmp [di].OPRND.sizearg,al
	je ao51
	pop ax		;discard return address
	jmp ao50

a_cmd endp

;--- Do reg/mem processing.
;--- in: DI->OPRND
;--- Uses AX

ao90 proc
	@dprintf "ao90: reg/mem processing [di].flags=%X", word ptr [di].OPRND.flags
	test [di].OPRND.flags, ARG_JUSTREG
	jnz ao92		;if just register
	test [di].OPRND.flags, ARG_MODRM
	jz @F			;if no precomputed MOD R/M byte
	mov ax,word ptr [di].OPRND.reg1	;get the precomputed bytes
	jmp ao93		;done
@@:
	mov al,6		;convert plain displacement to MOD R/M
	test [asm_mn_flags],AMF_A32
	jz ao93			;if 16 bit addressing
	dec ax
	jmp ao93		;done

ao92:
	mov al,[di].OPRND.reg1	;convert register to MOD R/M
if 1
	cmp al,REG_MM
	jnz @F
	mov al,[di].OPRND.reg2
@@:
endif
	and al,7		;get low 3 bits
	or al,0c0h

ao93:
	@dprintf "ao90: modrm, ai.regmem=%X, ax=%X", word ptr ai.regmem, ax
	or word ptr [ai.regmem],ax	;store the MOD R/M and SIB
	or [ai.varflags],VAR_MODRM	;flag its presence
	mov [ai.rmaddr],di			;save a pointer
	ret						;done
ao90 endp

;   AAIFNUM - Determine if there's a number next.
;   Entry   AL First character of number
;           SI Address of next character of number
;   Exit    CY Clear if there's a number, set otherwise.
;   Uses    None.

aaifnum proc
	cmp al,'-'
	je aai2			;if minus sign (carry is clear)
	push ax
	sub al,'0'
	cmp al,10
	pop ax
	jb aai1			;if a digit
	push ax
	and al,TOUPPER
	sub al,'A'
	cmp al,6
	pop ax
aai1:
	cmc				;carry clear <==> it's a number
aai2:
	ret
aaifnum endp

;   AAGETI - Get a number from the input line.
;   Entry   AL First character of number
;           SI Address of next character of number
;   Exit    DX:BX Resulting number
;           CL 1 if it's a byte ptr, 2 if a word, 4 if a dword
;           AL Next character not in number
;           SI Address of next character after that
;   Uses    AH, CH

aageti proc
	cmp al,'-'
	je aag1			;if negative
	call aag4		;get the bare number
	mov cx,1		;set up cx
	or dx,dx
	jnz aag2		;if dword
	or bh,bh
	jnz aag3		;if word
	ret				;it's a byte

aag1:
	lodsb
	call aag4		;get the bare number
	mov cx,bx
	or cx,dx
	mov cx,1
	jz aag1a		;if -0
	not dx		;negate the answer
	neg bx
	cmc
	adc dx,0
	test dh,80h
	jz aag7			;if error
	cmp dx,-1
	jne aag2		;if dword
	test bh,80h
	jz aag2			;if dword
	cmp bh,-1
	jne aag3		;if word
	test bl,80h
	jz aag3			;if word
aag1a:
	ret				;it's a byte

aag2:
	inc cx		;return:  it's a dword
	inc cx
aag3:
	inc cx		;return:  it's a word
	ret

aag4:
	xor bx,bx		;get the basic integer
	xor dx,dx
	call getnyb
	jc aag7			;if not a hex digit
aag5:
	or bl,al		;add it to the number
	lodsb
	call getnyb
	jc aag1a		;if done
	test dh,0f0h
	jnz aag7		;if overflow
	mov cx,4
aag6:
	shl bx,1		;shift it by 4
	rcl dx,1
	loop aag6
	jmp aag5

aag7:
	jmp cmd_error	;error

aageti endp

;   AACONVINDEX - Convert results from AAGETI and store index value
;   Entry   DX:BX,CL As in exit from AAGETI
;           DI Points to information record for this arg
;   Exit    SS bits stored in [di].OPRND.index
;   Uses    DL

aaconvindex proc
	cmp cl,1
	jne aacv1		;if the number is too large
	cmp bl,1
	je aacv2		;if 1
	inc dx
	cmp bl,2
	je aacv2		;if 2
	inc dx
	cmp bl,4
	je aacv2		;if 4
	inc dx
	cmp bl,8
	je aacv2		;if 8
aacv1:
	jmp cmd_error	;error

aacv2:
	mov [di].OPRND.index,dl	;save the value
	ret
aaconvindex endp

;   AAGETREG - Get register for the assembler.
;   Entry   DI Start of register table
;           CX Length of register table ( or 0 )
;           SI Address of first character in register name
;   Exit    NC if a register was found
;           SI Updated if a register was found
;           BX Register number, defined as in the table below.
;   Uses    AX, CX, DI

;   Exit value of BX:
;       DI = rgnam816, CX = 27  DI = rgnam16, CX = 8
;       ----------------------  --------------------
;       0  ..  7:  AL .. BH     0  ..  7:  AX .. DI
;       8  .. 15:  AX .. DI     16 .. 23:  EAX..EDI
;       16 .. 23:  EAX..EDI
;       24 .. 29:  ES .. GS
;       30 .. 34:  ST .. TR

aagetreg proc
	mov ax,[si]
	and ax,TOUPPER_W	;convert to upper case
	cmp al,'E'			;check for EAX, etc.
	jne aagr1			;if not
	push ax
	mov al,ah
	mov ah,[si+2]
	and ah,TOUPPER
	push di
	mov di,offset rgnam16
	push cx
	mov cx,N_REGS16
	repne scasw
	mov bx,cx
	pop cx
	pop di
	pop ax
	jne aagr1		;if no match
	inc si
	not bx
	add bl,8+16		;adjust BX
	jmp aagr2		;finish up

aagr1:
	mov bx,cx		;(if cx = 0, this is always reached with
	repne scasw		; ZF clear)
	jne aagr3		;if no match
	sub bx,cx
	dec bx
	cmp bl,16
	jb aagr2		;if AL .. BH or AX .. DI
	add bl,8
aagr2:
	inc si			;skip the register name
	inc si
	clc
	ret
aagr3:
	stc				;not found
	ret
aagetreg endp

