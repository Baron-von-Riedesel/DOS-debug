@echo off
rem Builds mktables.exe. Open Watcom's C compiler is used.
rem This step is only required if one of the following files were modified:
rem 1) instr.set
rem 2) instr.key
rem 3) instr.ord
rem 4) mktables.c

set WATCOM=\watcom
%WATCOM%\binnt\wcc -q -ox -ms -i%WATCOM%\h -3 -fo=build\mktables.obj src\mktables.c
%WATCOM%\binnt\wlink format dos f build\mktables.obj n build\mktables.exe libpath %WATCOM%\lib286\dos libpath %WATCOM%\lib286 op q,m=build\mktables.map
