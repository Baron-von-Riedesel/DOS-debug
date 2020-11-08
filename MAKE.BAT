@echo off
echo creating debug.com
jwasm -nologo -D?PM=0 -bin -Fobuild\DEBUG.COM -Flbuild\DEBUG.LST src\debug.asm
echo creating debugx.com
jwasm -nologo -D?PM=1 -bin -Fo build\DEBUGX.COM -Flbuild\DEBUGX.LST src\debug.asm
rem ml -c -nologo -D?PM=1 -Fo build\DEBUGX.OBJ -Flbuild\DEBUGX.LST src\debug.asm
