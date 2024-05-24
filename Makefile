
# create all DEBUG versions with JWasm.
# Masm could also be used, but then an OMF linker is required;
# also, Masm won't be able to assemble the long mode variant DEBUGRL.BIN.

# to enable the BP/BC cmds, use -DBCMD=1

NAME=DEBUG
OUTD=build

ALL: $(OUTD)/DEBUG.COM   $(OUTD)/DEBUGX.COM  $(OUTD)/DEBUGXD.COM $(OUTD)/DEBUGXE.COM $(OUTD)/DEBUGXF.COM \
     $(OUTD)/DEBUGXG.EXE $(OUTD)/DEBUGXU.COM $(OUTD)/DEBUGXV.COM $(OUTD)/DEBUGB.BIN  $(OUTD)/DEBUGR.BIN $(OUTD)/DEBUGRL.BIN $(OUTD)/DEBUGRV.BIN

DEPS= src/$(NAME).ASM src/ASMTBL.INC src/DISTBL.INC src/DPRINTF.INC src/FPTOSTR.INC src/DISASM.INC src/LINEASM.INC

$(OUTD)/DEBUG.COM: $(DEPS)   src/TRAPR.INC
	@echo creating debug.com
	@jwasm -nologo -bin -Fo$(OUTD)/DEBUG.COM -Fl$(OUTD)/DEBUG.LST src/$(NAME).ASM
$(OUTD)/DEBUGX.COM: $(DEPS)  src/TRAPR.INC src/TRAPD.INC
	@echo creating debugx.com
	@jwasm -nologo -D?DPMI=1 -DALTVID=1 -bin -Fo $(OUTD)/DEBUGX.COM -Fl$(OUTD)/DEBUGX.LST src/$(NAME).ASM
$(OUTD)/DEBUGXD.COM: $(DEPS) src/TRAPR.INC src/TRAPD.INC
	@echo creating debugxD - debug version of debugx
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)/DEBUGXD.COM -Fl=$(OUTD)/DEBUGXD.LST -DCATCHINT01=0 -DCATCHINT03=0 -DPROMPT=] src/$(NAME).ASM
$(OUTD)/DEBUGXE.COM: $(DEPS) src/TRAPR.INC src/TRAPD.INC
	@echo creating debugxE - checks for exc 06, 0C and 0D in real-mode
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)/DEBUGXE.COM -Fl=$(OUTD)/DEBUGXE.LST -DCATCHINT06=1 -DCATCHINT0C=1 -DCATCHINT0D=1 src/$(NAME).ASM
$(OUTD)/DEBUGXF.COM: $(DEPS) src/TRAPR.INC src/TRAPD.INC
	@echo creating debugxF - client cannot modify exc 01, 03, 0d and 0e in protected-mode
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)/DEBUGXF.COM -Fl=$(OUTD)/DEBUGXF.LST -DCATCHINT31=1 src/$(NAME).ASM
$(OUTD)/DEBUGXG.EXE: $(DEPS) src/TRAPR.INC src/TRAPD.INC
	@echo creating debugxG - device driver version of debugx, b cmds
	@jwasm -nologo -D?DPMI=1 -mz  -Fo $(OUTD)/DEBUGXG.EXE -Fl=$(OUTD)/DEBUGXG.LST -DDRIVER=1 -DBCMD=1 src/$(NAME).ASM
$(OUTD)/DEBUGXU.COM: $(DEPS) src/TRAPR.INC src/TRAPD.INC
	@echo creating debugxU - dx cmd uses unreal mode
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)/DEBUGXU.COM -Fl=$(OUTD)/DEBUGXU.LST -DUSEUNREAL=1 -DCATCHINT0D=1 src/$(NAME).ASM
$(OUTD)/DEBUGXV.COM: $(DEPS) src/TRAPR.INC src/TRAPD.INC
	@echo creating debugxV - v cmd flips screens, sysreq trapped, b cmds
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)/DEBUGXV.COM -Fl=$(OUTD)/DEBUGXV.LST -DVXCHG=1 -DCATCHSYSREQ=1 -DBCMD=1 src/$(NAME).ASM
$(OUTD)/DEBUGB.BIN:  $(DEPS) src/TRAPR.INC
	@echo creating debugB.bin - a "boot loader"  version
	@jwasm -nologo -bin  -Fo $(OUTD)/DEBUGB.BIN -Fl=$(OUTD)/DEBUGB.LST -DBOOTDBG=1 src/$(NAME).ASM
$(OUTD)/DEBUGR.BIN:  $(DEPS) src/TRAPP.INC
	@echo creating debugR.bin - a protected-mode "ring 0"  version
	@jwasm -nologo -bin  -Fo $(OUTD)/DEBUGR.BIN -Fl=$(OUTD)/DEBUGR.LST -DRING0=1 src/$(NAME).ASM
$(OUTD)/DEBUGRL.BIN: $(DEPS) src/TRAPPL.INC
	@echo creating debugRL.bin - a protected-mode "ring 0"  version for long mode
	@jwasm -nologo -bin  -Fo $(OUTD)/DEBUGRL.BIN -Fl=$(OUTD)/DEBUGRL.LST -Sg -DRING0=1 -DLMODE=1 src/$(NAME).ASM
$(OUTD)/DEBUGRV.BIN: $(DEPS) src/TRAPPV.INC
	@echo creating debugRV.bin - a protected-mode "ring 0"  version with v86 support
	@jwasm -nologo -bin  -Fo $(OUTD)/DEBUGRV.BIN -Fl=$(OUTD)/DEBUGRV.LST -Sg -DRING0=1 -DV86M=1 -DCATCHSYSREQ=1 -DCATCHINT0C=1 src/$(NAME).ASM

clean:
	del $(OUTD)\$(NAME)*.com
	del $(OUTD)\DEBUGXG.exe
	del $(OUTD)\$(NAME)*.bin
	del $(OUTD)\$(NAME)*.lst
