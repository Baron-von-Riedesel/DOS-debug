@echo off
rem create special DEBUG versions

echo creating debugJ.bin - a protected-mode "ring 0"  version
jwasm -nologo -bin -Fo build\DEBUGJ.BIN -Fl=build\DEBUGJ.LST -DCATCHINT06=1 -DRING0=1 src\debug.asm
