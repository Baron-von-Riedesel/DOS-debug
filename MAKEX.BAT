@echo off
rem create special DEBUG versions with JWasm
if not exist build\NUL mkdir build

echo creating debugxD - debug version of debugx
jwasm -nologo -bin -Fo build\DEBUGXD.COM -Fl=build\DEBUGXD.LST -D?DPMI=1 -DCATCHINT01=0 -DCATCHINT03=0 -DPROMPT=] src\debug.asm

echo creating debugxE - checks for exc 06, 0C and 0D in real-mode
jwasm -nologo -bin -Fo build\DEBUGXE.COM -Fl=build\DEBUGXE.LST -D?DPMI=1 -DCATCHINT06=1 -DCATCHINT0C=1 -DCATCHINT0D=1 src\debug.asm

echo creating debugxF - debuggee can't modify exc 1, 3, 0dh and 0eh in protected-mode
jwasm -nologo -bin -Fo build\DEBUGXF.COM -Fl=build\DEBUGXF.LST -D?DPMI=1 -DCATCHINT31=1 src\debug.asm

echo creating debugxG - device driver version of debugx, b cmds
jwasm -nologo -mz  -Fo build\DEBUGXG.EXE -Fl=build\DEBUGXG.LST -D?DPMI=1 -DDRIVER=1 -DBCMD=1 src\debug.asm

echo creating debugxU - dx cmd uses unreal mode
jwasm -nologo -bin -Fo build\DEBUGXU.COM -Fl=build\DEBUGXU.LST -D?DPMI=1 -DUSEUNREAL=1 -DCATCHINT0D=1 src\debug.asm

echo creating debugxV - v cmd flips screens & sysreq trapped & b cmds
jwasm -nologo -bin -Fo build\DEBUGXV.COM -Fl=build\DEBUGXV.LST -D?DPMI=1 -DVXCHG=1 -DCATCHSYSREQ=1 -DBCMD=1 src\debug.asm

echo creating debugB.bin - a "boot loader"  version
jwasm -nologo -bin  -Fo build\DEBUGB.BIN -Fl=build\DEBUGB.LST -DBOOTDBG=1 -DBCMD=1 src\debug.asm

echo creating debugBj.bin - a "boot loader"  version that won't use hw bps ( for 86Box and alikes )
jwasm -nologo -bin  -Fo build\DEBUGBJ.BIN -Fl=build\DEBUGBJ.LST -DBOOTDBG=1 src\debug.asm

echo creating debugR.bin - a protected-mode "ring 0" version
jwasm -nologo -bin  -Fo build\DEBUGR.BIN -Fl=build\DEBUGR.LST -DRING0=1 src\debug.asm

echo creating debugRV.bin - a protected-mode "ring 0" version with v86 support
jwasm -nologo -bin  -Fo build\DEBUGRV.BIN -Fl=build\DEBUGRV.LST -DRING0=1 -DV86M=1 -DCATCHINT02=1 -DCATCHINT0C=1 -DCATCHSYSREQ=1 src\debug.asm

echo creating debugRL.bin - a protected-mode "ring 0" version for long mode
jwasm -nologo -bin  -Fo build\DEBUGRL.BIN -Fl=build\DEBUGRL.LST -DRING0=1 -DLMODE=1 src\debug.asm
