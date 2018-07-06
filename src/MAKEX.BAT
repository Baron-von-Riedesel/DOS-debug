@echo off
rem create special DEBUG versions

echo creating debugxD - debug version of debugx
jwasm -c -nologo -D?PM=1 -bin -Fo DEBUGXD.COM -Fl=DEBUGXD.LST -DCATCHINT01=0 -DCATCHINT03=0 debug.asm

echo creating debugxE - checks for exc 06, 0C and 0D in real-mode
jwasm -c -nologo -D?PM=1 -bin -Fo DEBUGXE.COM -Fl=DEBUGXE.LST -DCATCHINT06=1 -DCATCHINT0C=1 -DCATCHINT0D=1 debug.asm

echo creating debugxF - client can't modify exc 01, 03, 0d and 0e in protected-mode
jwasm -c -nologo -D?PM=1 -bin -Fo DEBUGXF.COM -Fl=DEBUGXF.LST -DCATCHINT31=1 debug.asm

echo creating debugxG - device driver version of debugx
jwasm -c -nologo -D?PM=1 -mz -Fo DEBUGXG.EXE -Fl=DEBUGXG.LST -DCATCHINT06=1 -DDRIVER=1 debug.asm
