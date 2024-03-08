
 1. About Debug/X

    Debug/X is a package of debuggers. The most important ones are:
    
    - Debug: is a clone of the MS-DOS DEBUG command - although, "clone"
      isn't the correct name, because it has many features not available in
      the original MS DEBUG. For details see below. 

    - DebugX: is an extended version of Debug that allows to debug both
      real-mode and protected-mode (DPMI) DOS programs.

    - additional variants like DebugXv, DebugXg, DebugB or DebugR that are
      useful for special cases. For details see below.


 2. Added/Missing Features

  a. Debug extends MS-Debug in the following ways:

   - The assembler and disassembler support all publicly documented
     instructions for Intel chips through the Pentium Pro (P6), except for
     the MMX instructions (as for DebugX, MMX is partially supported since
     v1.18). The assembler and disassembler inform you if any instruction is 
     inappropriate for the current processor.

   - FPU Opcodes are supported.

   - The current processor (for the purposes of assembler and disassembler
     warnings, above) can be declared to be something else via the following
     commands:

        m [x] set current processor.
              x=0 current processor is 8088.
              x=1..6 current processor is 80x86. 80586 is a Pentium and
              80686 is a Pentium Pro.
              no argument = print current CPU/FPU types.
        mc [2|N] set math coprocessor. 
             2 = math coprocessor is a 287 (only valid if current
                 processor is a 386).
             N = math coprocessor is absent
             no argument = math coprocessor is present

   - 'r register [value]' accepts 32-bit register names (for cpu 80386+).

   - You can do `r cx 1234' instead of having to put the `1234' on a
     separate line.

   - 'rn' displays FPU register status.
      Just the raw hex values of the registers are displayed, though.

   - 'rx' switches among 8086 and 80386 register display (for cpu 80386+).

   - When doing `debug < file', debug will not hang if it reaches an end of
     file before encountering a `q' command.

   - This debugger saves and restores the program's Control-C and critical
     error interrupts, providing for better isolation between the debugger
     and the program being debugged.

   - 'tm 0|1' sets trace command mode, 0 = process INTs (default),
     1 = single-step INTs (the MS-DOS Debug compatible mode).

   - 'xr' allows to reallocate an EMS handle and 'xa' allows to allocate
     an "empty" EMS handle (with zero pages) - but only if an EMM v4.0
     is present.  

   - Besides 'i' and 'o' exist the variations 'iw', 'id', 'ow' and 'od'
     to read/write a WORD or DWORD value from/to a port [DWORD values
     require a 80386+ cpu].

   - 'h' can handle dword values.

   - register names can be used anywhere where a number is expected as
     input. That is, things like "u cs:ip" do work.

   - 'dm' displays the DOS memory control block (MCB) chain and the
     current PSP.

   - if DOS has set its InDOS flag, Debug will avoid to use int 21h
     internally, which allows to single-step through DOS code.

   - 'd', 't' and 'u' are automatically repeated if a blank line is
     entered.

  b. DebugX has the following additional features:

   - besides real-mode applications it can debug both 16-bit and 32-bit
     DPMI clients.
     [To debug DPMI clients a DPMI host has to be installed. Tested with
      cwsdpmi, hdpmi, WinXP NTVDM, 32rtm. In DosEmu and Windows 95/98/ME
      DOS boxes it is required to single-step through the initial switch
      to protected-mode, else DebugX will loose control of the debuggee.]

   - 'dl': display LDT descriptor(s) (in protected-mode only)

   - 'di': display interrupt vector(s)

   - 'dx': display extended memory (read via Int 15h, ah=87h). Requires a
     80386 cpu. 'dx' is automatically repeated if a blank line is entered.
     Be aware that Int 15h, ah=87h most likely will disable "unreal"-mode
     if it was enabled. This may be an unwanted side effect during debugging.

   - 'g': the 80386+ debug hardware support may be used for the first
     breakpoint. This also applies to the 't' and 'p' commands, if they
     have to internally use a breakpoint. Allows to set a breakpoint
     in ROM code or - in protected-mode - in pages marked as read-only.
     This feature is active in protected-mode and true real-mode, but not
     in v86-mode. Be aware that some DPMI hosts don't support that.

   - 'rn' displays FPU registers in "readable" format.

   - when running in a Windows XP DOS bos, DebugX will try to load and use
     DEBXXVDD.DLL. This DLL will allow DebugX to successfully execute its
     low-level disk access commands L and W in this OS - if the user has
     administrator rights. DEBXXVDD.DLL is public domain, the source can
     be found at http://github.com/Baron-von-Riedesel/debxxf. Please
     be aware that you can do severe damage to your disk data if you use
     those low-level functions without knowing what you are doing.

   - 'rm' displays MMX registers.

   - commandline option /2 may direct DebugX's output to a monochrome video
     adapter if one is available. Useful for emulators that support this
     feature ( DosBox-x or 86Box, for example ). Needs at least a VGA
     compatible card, and there's no guarantee that it works as expected.


  c. Optionally, one may create special-purpose versions of Debug(X).
     Run file makex.bat to create them; you'll need the JWasm assembler
     for a successful run. The additional versions are:
  
   - DebugXd.COM: a version which doesn't hook int 01 and int 03. This
     allows to debug this version with a "normal" version of Debug(X).

   - DebugXe.COM: a version which hooks interrupts 06, 0Ch and 0Dh in
     real-mode. This is for - rare - cases when such exceptions may
     occur in real-mode applications.

   - DebugXf.COM: a version which hooks interrupt 31h in protected-mode
     and then rejects any attempt to modify exception vectors 01, 03,
     0Dh and 0Eh. This allows to debug DOS-extended applications that
     modify these vectors.

   - DebugXg.EXE: a version that is in DOS device driver format. This
     variant can be used to debug other device drivers. There are a
     few peculiarities: commands N and Q are rejected, commands
     R and W can't be used to read/write files and interrupt 06 (invalid
     opcode exception) is hooked.

   - DebugXu.COM: a version that uses "unreal" mode to access extended
     memory for the DX command. This is useful to debug applications
     that set/use "unreal" mode themselves, because DebugXU will not
     change the current "unreal" state by its DX command.

   - DebugXv.COM: a version that takes care that screen output of
     debuggee and debugger are strictly separated - the new 'v'
     command is provided to watch the debuggee screen while the
     debugger is active. Additionally, the SysReq key is detected and
     will activate the debugger. This debug version is useful to debug
     fullscreen text mode programs.

   - DebugB.BIN: a version that is supposed to be loaded during the
     boot process, before DOS is loaded. Has to be installed in "free"
     disk space ( for example, in the "reserved" sectors of a FAT partition
     or behind the disk's MBR ) and must be initialized before it becomes
     active. Definitely not for beginners. See "Installing and Initializing
     DebugB" in DEBUG.TXT for details.

   - DebugR(L).BIN: versions that runs in ring0 protected-mode. These variants
     need additional software a) to be loaded and b) to handle the i/o
     requests. Like DebugB.BIN no DOS is used - actually, not even the BIOS
     is used - and hence these are not really "DOS debuggers" anymore. See
     "DebugR Basics" in DEBUG.TXT for more details.

  d. The following features of MS Debug are not implemented:

   - Loading of .HEX files.


 3. How to (re)build the Debug.COM/DebugX.COM Binaries

    MAKE.BAT is intended for rebuilding the debugger binaries. The
    recommended tool for this step is to use the JWasm assembler.
    Alternatively, one can use MS Masm, but then a 16-bit OMF linker 
    will be needed as well (Open Watcom's WLink might do the job). Also,
    the DebugRL variant cannot be created with Masm, since it contains
    a 64-bit segment.


 4. Files Overview

    The files in this distribution are:

    debug.com     the executable binary.
    debugx.com    a DPMI aware version of Debug.
    debxxvdd.dll  a Win32 dll (VDD) loaded if debugx runs in a Windows XP 
                  NTVDM "DOS box". Makes debugx's L and W command work with
                  sectors on this platform.
    readme.txt    this file.
    history.txt   list of changes.
    debug.txt     a MS-Debug tutorial originally written by Michael Webster,
                  extended to describe all additional features of Debug(X).
    SAMPLES       contains samples of 16 and 32-bit DPMI clients in Masm
                  syntax.

    The following files, which may be distributed separately, are needed if 
    debug.com or debugx.com is to be rebuilt:

    debug.asm     Assembler source code for both debug.com and debugx.com.
                  Assemble with JWasm or Masm (see Make.bat).
    debugtbl.inc  include file for debug.asm, contains tables for Debug's
                  internal assembler and disassembler command.
    instr.*       input data for mktables.
    mktables.c    C program to compile the internal instruction-set
                  tables into source file debugtbl.inc. It's supposed to
                  be translated with Open Watcom's 16bit compiler WCC.
    make.bat      batch file to (re)create debug.com and debugx.com.
    makecm.bat    batch file to (re)create mktables.exe with MS C.
    makecw.bat    batch file to (re)create mktables.exe with OW C.
    makex.bat     batch file to create special versions of Debugx.

    Note: files mktables.c and instr.* are to be removed in one of the next
    versions of Debug. Then file debugtbl.inc is supposed to be modified
    directly if new instructions are to be supported..


 5. Copyright

    This program is copyrighted, but feel free to distribute and use it
    as you wish.  For full copyright conditions, see the file debug.asm.

    Paul Vojta
    vojta@math.berkeley.edu

