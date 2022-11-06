@echo off
rem create special DEBUG versions

echo creating debugxD - debug version of debugx
jwasm -nologo -D?PM=1 -bin -Fo build\DEBUGXD.COM -Fl=build\DEBUGXD.LST -DCATCHINT01=0 -DCATCHINT03=0 -DPROMPT=] src\debug.asm

echo creating debugxE - checks for exc 06, 0C and 0D in real-mode
jwasm -nologo -D?PM=1 -bin -Fo build\DEBUGXE.COM -Fl=build\DEBUGXE.LST -DCATCHINT06=1 -DCATCHINT0C=1 -DCATCHINT0D=1 src\debug.asm

echo creating debugxF - client can't modify exc 01, 03, 0d and 0e in protected-mode
jwasm -nologo -D?PM=1 -bin -Fo build\DEBUGXF.COM -Fl=build\DEBUGXF.LST -DCATCHINT31=1 src\debug.asm

echo creating debugxG - device driver version of debugx
jwasm -nologo -D?PM=1 -mz  -Fo build\DEBUGXG.EXE -Fl=build\DEBUGXG.LST -DCATCHINT06=1 -DDRIVER=1 src\debug.asm

echo creating debugxU - dx cmd uses unreal mode
jwasm -nologo -D?PM=1 -bin -Fo build\DEBUGXU.COM -Fl=build\DEBUGXU.LST -DUSEUNREAL=1 -DCATCHINT0D=1 src\debug.asm

echo creating debugxV - v cmd flips screens & sysreq trapped
jwasm -nologo -D?PM=1 -bin -Fo build\DEBUGXV.COM -Fl=build\DEBUGXV.LST -DVXCHG=1 -DCATCHSYSREQ=1 src\debug.asm

echo creating debugB.bin - a "boot loader"  version
jwasm -nologo -bin  -Fo build\DEBUGB.BIN -Fl=build\DEBUGB.LST -D?PM=0 -DCATCHINT06=1 -DBOOTDBG=1 src\debug.asm
