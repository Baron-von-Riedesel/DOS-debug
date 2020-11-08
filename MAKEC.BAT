@echo off
rem Builds mktables.exe. Open Watcom's C compiler is used.
rem This step is only required if one of the following files were modified:
rem 1) instr.set
rem 2) instr.key
rem 3) instr.ord
rem 4) mktables.c

rem using Open Watcom
rem wcl -ox -3 -d__MSDOS__ src\mktables.c

rem using MSVC v1.5
\msvc\bin\cl -c -G3 -D__MSDOS__ -Fobuild\mktables.obj -I\msvc\include src\mktables.c
set lib=\msvc\lib
\msvc\bin\link16 build\mktables.obj,build\mktables.exe,build\mktables.map /NON;
