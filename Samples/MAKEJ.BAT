@echo off
rem assemble the samples which are written in MASM syntax.
rem JWasm is used.
jwasm -nologo -bin -Fo DPMICL16.COM DPMICL16.ASM
jwasm -nologo -bin -Fo DPMIBK16.COM DPMIBK16.ASM
jwasm -nologo -mz DPMICL32.ASM
jwasm -nologo -mz DPMIBK32.ASM
