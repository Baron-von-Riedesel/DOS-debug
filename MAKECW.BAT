@echo off
rem Builds mktables.exe. Open Watcom's C compiler is used.
rem This step is only required if one of the following files were modified:
rem 1) instr.set
rem 2) instr.key
rem 3) instr.ord
rem 4) mktables.c

rem here jwlink is used instead of wlink

\watcom\binnt\wcc -q -ox -i\watcom\h -3 -fo=build\mktables.obj src\mktables.c
rem \watcom\binnt\wlink system dos f build\mktables.obj n build\mktables.exe op q,m=build\mktables.map
jwlink format dos f build\mktables.obj n build\mktables.exe libpath \watcom\lib286\dos libpath \watcom\lib286 op q,m=build\mktables.map
