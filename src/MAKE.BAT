@echo off
echo creating debug.com
jwasm -nologo -D?PM=0 -bin -Fo DEBUG.COM -FlDEBUG.LST debug.asm
echo creating debugx.com
jwasm -c -nologo -D?PM=1 -bin -Fo DEBUGX.COM -FlDEBUGX.LST debug.asm
rem ml -c -nologo -D?PM=1 -Fo DEBUGX.OBJ -FlDEBUGX.LST debug.asm
