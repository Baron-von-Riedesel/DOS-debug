@echo off
rem Builds mktables.exe. using MS Visual C++ 1.52
rem This step is only required if one of the following files were modified:
rem 1) instr.set
rem 2) instr.key
rem 3) instr.ord
rem 4) mktables.c

echo WARNING, currently MS VC doesn't generate a valid debugtbl.inc!

\msvc\bin\cl -c -nologo -G3 -D__MSDOS__ -Fobuild\mktables.obj -I\msvc\include src\mktables.c
set lib=\msvc\lib
\msvc\bin\link /NOLOGO build\mktables.obj,build\mktables.exe,build\mktables.map /NON;
