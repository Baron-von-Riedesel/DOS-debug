
# create all DEBUG versions

OUTD=build

ALL: $(OUTD)\DEBUG.COM   $(OUTD)\DEBUGX.COM  $(OUTD)\DEBUGXD.COM $(OUTD)\DEBUGXE.COM $(OUTD)\DEBUGXF.COM \
     $(OUTD)\DEBUGXG.EXE $(OUTD)\DEBUGXU.COM $(OUTD)\DEBUGXV.COM $(OUTD)\DEBUGB.BIN  $(OUTD)\DEBUGR.BIN

DEPS= src\debug.asm src\debugtbl.inc src\dprintf.inc src\fptostr.inc

$(OUTD)\DEBUG.COM: $(DEPS)
	@echo creating debug.com
	@jwasm -nologo -bin -Fo$(OUTD)\DEBUG.COM -Fl$(OUTD)\DEBUG.LST src\debug.asm
$(OUTD)\DEBUGX.COM: $(DEPS)
	@echo creating debugx.com
	@jwasm -nologo -D?DPMI=1 -DALTVID=1 -bin -Fo $(OUTD)\DEBUGX.COM -Fl$(OUTD)\DEBUGX.LST src\debug.asm
$(OUTD)\DEBUGXD.COM: $(DEPS)
	@echo creating debugxD - debug version of debugx
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)\DEBUGXD.COM -Fl=$(OUTD)\DEBUGXD.LST -DCATCHINT01=0 -DCATCHINT03=0 -DPROMPT=] src\debug.asm
$(OUTD)\DEBUGXE.COM: $(DEPS)
	@echo creating debugxE - checks for exc 06, 0C and 0D in real-mode
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)\DEBUGXE.COM -Fl=$(OUTD)\DEBUGXE.LST -DCATCHINT06=1 -DCATCHINT0C=1 -DCATCHINT0D=1 src\debug.asm
$(OUTD)\DEBUGXF.COM: $(DEPS)
	@echo creating debugxF - client can't modify exc 01, 03, 0d and 0e in protected-mode
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)\DEBUGXF.COM -Fl=$(OUTD)\DEBUGXF.LST -DCATCHINT31=1 src\debug.asm
$(OUTD)\DEBUGXG.EXE: $(DEPS)
	@echo creating debugxG - device driver version of debugx
	@jwasm -nologo -D?DPMI=1 -mz  -Fo $(OUTD)\DEBUGXG.EXE -Fl=$(OUTD)\DEBUGXG.LST -DCATCHINT06=1 -DDRIVER=1 src\debug.asm
$(OUTD)\DEBUGXU.COM: $(DEPS)
	@echo creating debugxU - dx cmd uses unreal mode
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)\DEBUGXU.COM -Fl=$(OUTD)\DEBUGXU.LST -DUSEUNREAL=1 -DCATCHINT0D=1 src\debug.asm
$(OUTD)\DEBUGXV.COM: $(DEPS)
	@echo creating debugxV - v cmd flips screens & sysreq trapped
	@jwasm -nologo -D?DPMI=1 -bin -Fo $(OUTD)\DEBUGXV.COM -Fl=$(OUTD)\DEBUGXV.LST -DVXCHG=1 -DCATCHSYSREQ=1 src\debug.asm
$(OUTD)\DEBUGB.BIN:  $(DEPS)
	@echo creating debugB.bin - a "boot loader"  version
	@jwasm -nologo -bin  -Fo $(OUTD)\DEBUGB.BIN -Fl=$(OUTD)\DEBUGB.LST -DCATCHINT06=1 -DBOOTDBG=1 src\debug.asm
$(OUTD)\DEBUGR.BIN:  $(DEPS)
	@echo creating debugR.bin - a protected-mode "ring 0"  version
	@jwasm -nologo -bin  -Fo $(OUTD)\DEBUGR.BIN -Fl=$(OUTD)\DEBUGR.LST -DCATCHINT06=1 -DRING0=1 src\debug.asm
