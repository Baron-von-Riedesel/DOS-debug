@echo off
rem Builds mktables.exe. using MS Visual C++ 1.52
rem This step is only required if one of the following files were modified:
rem 1) instr.set
rem 2) instr.key
rem 3) instr.ord
rem 4) mktables.c

set MSVC=\msvc
set LIB=%MSVC%\lib
%MSVC%\bin\cl -c -nologo -G3 -Fobuild\mktables.obj -I%MSVC%\include src\mktables.c
rem %MSVC%\bin\link /NOLOGO build\mktables.obj,build\mktables.exe,build\mktables.map /NON;
%MSVC%\bin\link build\mktables.obj,build\mktables.exe,build\mktables.map;
