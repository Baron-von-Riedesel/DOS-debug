/*
 * This program reads in the various data files, performs some checks,
 * and spits out the tables needed for assembly and disassembly.
 *
 * The input files are:
 *      instr.set   Instruction set
 *      instr.key   Translation from one- or two-character keys to
 *                  operand list types
 *      instr.ord   Ordering relations to enforce on the operands
 *
 * The output tables are written to DEBUGTBL.INC, which is
 * included into DEBUG.ASM.
 */

#ifndef DOS
#ifdef __MSDOS__
#define DOS 1
#else
#define DOS 0
#endif
#endif

#include <stdlib.h>
#if ! DOS
#include <unistd.h>
#else
#include <io.h>
#endif
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>

#if DOS
#define bzero(a, b) memset(a, 0, b)
#else
#define cdecl
#endif

#define MAX_OL_TYPES        82
#define MAX_N_ORDS          30
#define LINELEN            132
#define MAX_ASM_TAB       2048
#define MAX_MNRECS         400
#define MAX_SAVED_MNEMS     10
#define MAX_SLASH_ENTRIES   20
#define MAX_HASH_ENTRIES    15
#define MAX_STAR_ENTRIES    15
#define MAX_LOCKTAB_ENTRIES 50
#define MAX_AGROUP_ENTRIES  14
#define MSHIFT              12 /* number of bits below machine type */
#define SORTMN              0  /* sort mnemonics */

typedef char    Boolean;
#define True    1
#define False   0

#define NUMBER(x)   (sizeof(x) / sizeof(*x))

char line[LINELEN];
const char *filename;
int lineno;

int n_keys = 0;
struct keytab {
 short key;  /* */
 short value;
 short width;
};

int n_ol_types = 0;
struct keytab olkeydict[MAX_OL_TYPES];
char *olnames[MAX_OL_TYPES];  // containes lines of INSTR.KEY
int oloffset[MAX_OL_TYPES];

int n_ords = 0;
struct keytab *keyord1[MAX_N_ORDS];
struct keytab *keyord2[MAX_N_ORDS];
Boolean ordsmall[MAX_OL_TYPES];

/*
 * Equates for the assembler table.
 * These should be the same as in debug.asm.
 */

#define ASM_END     0xff
#define ASM_DB      0xfe
#define ASM_DW      0xfd
#define ASM_DD      0xfc
#define ASM_ORG     0xfb
#define ASM_WAIT    0xfa
#define ASM_D32     0xf9
#define ASM_D16     0xf8
#define ASM_AAX     0xf7
#define ASM_SEG     0xf6
#define ASM_LOCKREP 0xf5
#define ASM_LOCKABLE    0xf4
#define ASM_MACH6   0xf3
#define ASM_MACH0   0xed

int n_asm_tab = 0;
unsigned char asmtab[MAX_ASM_TAB];

struct mnrec {
	struct mnrec	*next;
	char		*string;
	short		len;
	short		offset;    /* ??? */
	short		asmoffset; /* offset in asmtab */
};

int num_mnrecs;
struct mnrec mnlist[MAX_MNRECS];
struct mnrec *mnhead;

int n_saved_mnems = 0;
int saved_mnem[MAX_SAVED_MNEMS];

int n_slash_entries;
int slashtab_seq[MAX_SLASH_ENTRIES];
int slashtab_mn[MAX_SLASH_ENTRIES];

int n_hash_entries;
int hashtab_seq[MAX_HASH_ENTRIES];
int hashtab_mn[MAX_HASH_ENTRIES];

int n_star_entries;
int startab_seq[MAX_STAR_ENTRIES];
int startab_mn[MAX_STAR_ENTRIES];

int n_locktab;
int locktab[MAX_LOCKTAB_ENTRIES];

int n_agroups;
int agroup_i[MAX_AGROUP_ENTRIES];
int agroup_inf[MAX_AGROUP_ENTRIES];

volatile void fail(const char *message, ...)
{
	va_list args;

	va_start(args, message);
	vfprintf(stderr, message, args);
	va_end(args);
	putc('\n', stderr);
	exit(1);
}

FILE * openread(const char *path)
{
	FILE *f;

	f = fopen(path, "r");
	if (f == NULL) {
	    perror(path);
	    exit(1);
	}
	filename = path;
	lineno = 0;
	return f;
}

volatile void linenofail(const char *message, ...)
{
	va_list args;

	fprintf(stderr, "Line %d of `%s':  ", lineno, filename);
	va_start(args, message);
	vfprintf(stderr, message, args);
	va_end(args);
	putc('\n', stderr);
	exit(1);
}

void * xmalloc(unsigned int len, const char *why)
{
	void *ptr = malloc(len);

	if (ptr == NULL) fail("Cannot allocate %u bytes for %s", len, why);
	return ptr;
}

Boolean getline(FILE *ff)
{
	int n;

	for (;;) {
		if (fgets(line, LINELEN, ff) == NULL) return False;
		++lineno;
		if (line[0] == '#') continue;
		n = strlen(line) - 1;
		if (n < 0 || line[n] != '\n')
			linenofail("too long.");
		if (n > 0 && line[n-1] == '\r') --n;
		if (n == 0) continue;
		line[n] = '\0';
		return True;
	}
}

short getkey(char **pp)
{
	short key;
	char *p = *pp;

	if (*p == ' ' || *p == '\t' || *p == ';' || *p == '\0')
	    linenofail("key expected");
	key = *p++;
	if (*p != ' ' && *p != '\t' && *p != ';' && *p != '\0') {
	    key = (key << 8) | *p++;
	    if (*p != ' ' && *p != '\t' && *p != ';' && *p != '\0')
		linenofail("key too long");
	}
	*pp = p;
	return key;
}

/*
 *	Mark the given key pointer as small, as well as anything smaller than
 *	it (according to instr.ord).
 */

void marksmall(struct keytab *kp)
{
	int i;

	ordsmall[kp - olkeydict] = True;
	for (i = 0; i < n_ords; ++i)
		if (keyord2[i] == kp)
			marksmall(keyord1[i]);
}

/*
 * Add a byte to the assembler table (asmtab).
 * The format of this table is described in a long comment in debug.asm,
 * somewhere within the mini-assembler.
 */

void add_to_asmtab(unsigned char byte)
{
	if (n_asm_tab >= MAX_ASM_TAB)
		linenofail("Assembler table overflow.");
	asmtab[n_asm_tab++] = byte;
}


unsigned char getmachine(char **pp)
{
	char *p = *pp;
	unsigned char value;

	if (*p != ';') return 0;
	++p;
	if (*p < '0' || *p > '6')
		linenofail("bad machine type");
	value = *p++ - '0';
	add_to_asmtab(ASM_MACH0 + value);
	*pp = p;
	return value;
}

struct keytab * lookupkey(short key)
{
	struct keytab *kp;

	for (kp = olkeydict; kp < olkeydict + NUMBER(olkeydict); ++kp)
	    if (key == kp->key) return kp;
    linenofail("can't find key %X", key);
    return NULL;
}

char * skipwhite(char *p)
{
	while (*p == ' ' || *p == '\t') ++p;
	return p;
}

/*
 *	Data and setup stuff for the disassembler processing.
 */

/*	Data on coprocessor groups */

unsigned int fpgrouptab[] = {0xd9e8, 0xd9f0, 0xd9f8};

#define NGROUPS     9

#define GROUP(i)    (256 + 8 * ((i) - 1))
#define COPR(i)     (256 + 8 * NGROUPS + 16 * (i))
#define FPGROUP(i)  (256 + 8 * NGROUPS + 16 * 8 + 8 * (i))
#define SPARSE_BASE (256 + 8 * NGROUPS + 16 * 8 + 8 * NUMBER(fpgrouptab))

/* #define OPILLEGAL 0 */
#define OPTWOBYTE   2
#define OPGROUP     4
#define OPCOPR      6
#define OPFPGROUP   8
#define OPPREFIX    10
#define OPSIMPLE    12
#define OPTYPES     12  /* op types start here (includes simple ops) */

#define PRESEG      1   /* these should be the same as in debug.asm */
#define PREREP      2
#define PREREPZ     4
#define PRELOCK     8
#define PRE32D      0x10
#define PRE32A      0x20

/*
 *	For sparsely filled parts of the opcode map, we have counterparts
 *	to the above, which are compressed in a simple way.
 */

/*	Sparse coprocessor groups */

unsigned int sp_fpgrouptab[] = {0xd9d0, 0xd9e0, 0xdae8, 0xdbe0,
				   0xded8, 0xdfe0};

#define NSGROUPS 5

#define SGROUP(i)	(SPARSE_BASE + 256 + 8 * ((i) - 1))
#define SFPGROUP(i)	(SPARSE_BASE + 256 + 8 * NSGROUPS + 8 * (i))
#define NOPS		(SPARSE_BASE + 256 + 8 * NSGROUPS + 8 * NUMBER(sp_fpgrouptab))

int optype[NOPS];
int opinfo[NOPS];
unsigned char opmach[NOPS];

/*
 * Here are the tables for the main processor groups.
 */

struct {
	int seq;	/* sequence number of the group */
	int info;	/* which group number it is */
} grouptab[]= {
	{0x80, GROUP(1)},	/* Intel group 1 */
	{0x81, GROUP(1)},
	{0x83, GROUP(2)},
	{0xd0, GROUP(3)},	/* Intel group 2 */
	{0xd1, GROUP(3)},
	{0xd2, GROUP(4)},
	{0xd3, GROUP(4)},
	{0xc0, GROUP(5)},	/* Intel group 2a */
	{0xc1, GROUP(5)},
	{0xf6, GROUP(6)},	/* Intel group 3 */
	{0xf7, GROUP(6)},
	{0xff, GROUP(7)},	/* Intel group 5 */
	{SPARSE_BASE + 0x00, GROUP(8)}, /* Intel group 6 */
	{SPARSE_BASE + 0x01, GROUP(9)}  /* Intel group 7 */
};

/* #define NGROUPS 9 (this was done above) */

struct {	/* sparse groups */
	int seq;	/* sequence number of the group */
	int info;	/* which group number it is */
} sp_grouptab[] = {
	{0xfe, SGROUP(1)},		/* Intel group 4 */
	{SPARSE_BASE+0xba, SGROUP(2)},	/* Intel group 8 */
	{SPARSE_BASE+0xc7, SGROUP(3)},	/* Intel group 9 */
	{0x8f, SGROUP(4)},		/* Not an Intel group */
	{0xc6, SGROUP(5)},		/* Not an Intel group */
	{0xc7, SGROUP(5)}
};

/* #define NSGROUPS 5 (this was done above) */

/*
 *	Creates an entry in the disassembler lookup table
 */

void entertable(int i, int type, int info)
{
	if (optype[i] != 0)
		linenofail("Duplicate information for index %d", i);
	optype[i] = type;
	opinfo[i] = info;
}

/*
 *	Get a hex nybble from the input line or fail.
 */

int getnybble(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	linenofail("Hex digit expected instead of `%c'", c);
	return -1;
}

/*
 *	Get a hex byte from the input line and update the pointer accordingly.
 */

int getbyte(char **pp)
{
	char *p = *pp;
	int answer;

	answer = getnybble(*p++);
	answer = (answer << 4) | getnybble(*p++);
	*pp = p;
	return answer;
}

/*
 *	Get a `/r' descriptor from the input line and update the pointer
 *	accordingly.
 */

int getslash(char **pp)
{
	char *p = *pp;
	int answer;

	if (*p != '/') linenofail("`/' expected");
	++p;
	if (*p < '0' || *p > '7') linenofail("Octal digit expected");
	answer = *p - '0';
	++p;
	*pp = p;
	return answer;
}

int entermn(char *str, char *str_end)
{
	char *p;

	if (num_mnrecs >= MAX_MNRECS)
		linenofail("Too many mnemonics");

	if (*str == '+') {
		if (n_saved_mnems >= MAX_SAVED_MNEMS)
			linenofail("Too many mnemonics to save");
		saved_mnem[n_saved_mnems++] = num_mnrecs;
		++str;
	}

	p = xmalloc(str_end - str + 1, "mnemonic name");
	mnlist[num_mnrecs].string = p;
	mnlist[num_mnrecs].len = str_end - str;
	while (str < str_end) *p++ = toupper(*str++);
	*p = 0;
	mnlist[num_mnrecs].asmoffset = n_asm_tab;
	return num_mnrecs++;
}

/*
 *	Merge sort the indicated range of mnemonic records.
 */
#if SORTMN
struct mnrec * mn_sort(struct mnrec *start, int len)
{
	struct mnrec *p1, *p2, *answer;
	struct mnrec **headpp;
	int i;

	i = len / 2;
	if (i == 0)
		return start;

	p1 = mn_sort(start, i);
	p2 = mn_sort(start + i, len - i);
	headpp = &answer;
	for (;;) {
		if (strcmp(p1->string, p2->string) < 0) {
			*headpp = p1;
			headpp = &p1->next;
			p1 = *headpp;
			if (p1 == NULL) {
				*headpp = p2;
				break;
			}
		} else {
			*headpp = p2;
			headpp = &p2->next;
			p2 = *headpp;
			if (p2 == NULL) {
				*headpp = p1;
				break;
			}
		}
	}
	return answer;
}
#endif
/*
 *	This reads the main file, "instr.set".
 */

void read_is(FILE *f1)
{
	int i;

	entertable(0x0f, OPTWOBYTE, SPARSE_BASE);
	entertable(0x26, OPPREFIX, PRESEG | (0 << 8));	/* seg es */
	entertable(0x2e, OPPREFIX, PRESEG | (1 << 8));	/* seg cs */
	entertable(0x36, OPPREFIX, PRESEG | (2 << 8));	/* seg ss */
	entertable(0x3e, OPPREFIX, PRESEG | (3 << 8));	/* seg ds */
	entertable(0x64, OPPREFIX, PRESEG | (4 << 8));	/* seg fs */
	entertable(0x65, OPPREFIX, PRESEG | (5 << 8));	/* seg gs */
	entertable(0xf2, OPPREFIX, PREREP);		/* other prefixes */
	entertable(0xf3, OPPREFIX, PREREP | PREREPZ);
	entertable(0xf0, OPPREFIX, PRELOCK);
	entertable(0x66, OPPREFIX, PRE32D);
	entertable(0x67, OPPREFIX, PRE32A);
	opmach[0x64] = opmach[0x65] = opmach[0x66] = opmach[0x67] = 3;
	
	for (i = 0; i < NUMBER(grouptab); ++i)
		entertable(grouptab[i].seq, OPGROUP, grouptab[i].info);
	for (i = 0; i < NUMBER(sp_grouptab); ++i)
		entertable(sp_grouptab[i].seq, OPGROUP, sp_grouptab[i].info);
	for (i = 0; i < 8; ++i)
		entertable(0xd8 + i, OPCOPR, COPR(i));
	for (i = 0; i < NUMBER(fpgrouptab); ++i) {
		unsigned int j = fpgrouptab[i];
		unsigned int k = (j >> 8) - 0xd8;

		if (k > 8 || (j & 0xff) < 0xc0)
			fail("Bad value for fpgrouptab[%d]", i);
		entertable(COPR(k) + 8 + (((j & 0xff) - 0xc0) >> 3),
		OPFPGROUP, FPGROUP(i));
	}
	for (i = 0; i < NUMBER(sp_fpgrouptab); ++i) {
		unsigned int j = sp_fpgrouptab[i];
		unsigned int k = (j >> 8) - 0xd8;

		if (k > 8 || (j & 0xff) < 0xc0)
		fail("Bad value for sp_fpgrouptab[%d]", i);
		entertable(COPR(k) + 8 + (((j & 0xff) - 0xc0) >> 3),
		OPFPGROUP, SFPGROUP(i));
	}
	while (getline(f1)) {	/* loop over lines in the file */
		int mnem;
		int mn_alt;
		char *p, *p0, *pslash, *phash, *pstar;
		Boolean asm_only_line;
		unsigned char atab_addendum;

		asm_only_line = False;
		p0 = line;
		if (line[0] == '_') {
			asm_only_line = True;
			++p0;
		}
		atab_addendum = '\0';
		if (*p0 == '^') {
			static const unsigned char uptab[] =
			{ASM_AAX, ASM_DB, ASM_DW,
			ASM_DD, ASM_ORG, ASM_D32};

			++p0;
			atab_addendum = uptab[*p0++ - '0'];
		}
		p = strchr(p0, ' ');
		if (p == NULL) p = p0 + strlen(p0);

		/* check for '/', '#' and '*' separators */

		pslash = memchr(p0, '/', p - p0);
		phash = memchr(p0, '#', p - p0);
		pstar = memchr(p0, '*', p - p0);
		if (pslash != NULL) {
			mnem = entermn(p0, pslash);
			add_to_asmtab(ASM_D16);
			//++mnlist[mnem].asmoffset;	/* this one isn't 32 bit */
			++pslash;
			mn_alt = entermn(pslash, p);
			add_to_asmtab(ASM_D32);
		} else if (phash != NULL) {
			mnem = entermn(p0, phash);
			add_to_asmtab(ASM_D16);
			//++mnlist[mnem].asmoffset;	/* this one isn't 32 bit */
			++phash;
			mn_alt = entermn(phash, p);
			add_to_asmtab(ASM_D32);
		} else if (pstar != NULL) {
			mn_alt = entermn(p0, pstar);	/* note the reversal */
			add_to_asmtab(ASM_WAIT);
			++pstar;
			mnem = entermn(pstar, p);
		} else {
			mnem = entermn(p0, p);
		}

		if (atab_addendum != '\0') add_to_asmtab(atab_addendum);

		atab_addendum = ASM_END;
		bzero(ordsmall, n_keys * sizeof(Boolean));
		while (*p == ' ') {		/* loop over instruction variants */
			Boolean		lockable;
			Boolean		asm_only;
			Boolean		dis_only;
			unsigned char	machine;
			unsigned long	atab_inf;
			unsigned short	atab_key;
			unsigned char	atab_xtra = 0;

			while (*p == ' ') ++p;
			asm_only = asm_only_line;
			dis_only = False;
			if (*p == '_') {	/* if assembler only */
				++p;
				asm_only = True;
			}
			else if (*p == 'D') {	/* if disassembler only */
				++p;
				dis_only = True;
			}
			lockable = False;
			if (*p == 'L') {
				++p;
				lockable = True;
				if (dis_only == False)
					add_to_asmtab(ASM_LOCKABLE);
			}
			atab_inf = i = getbyte(&p);
			if (i == 0x0f) {
				i = getbyte(&p);
				atab_inf = 256 + i;
				i += SPARSE_BASE;
			}
			if (optype[i] == OPGROUP) {
				int j = getslash(&p);
				int k;

				for (k = 0;; ++k) {
					if (k >= n_agroups) {
						if (++n_agroups > MAX_AGROUP_ENTRIES)
							linenofail("Too many agroup entries");
						agroup_i[k] = i;
						agroup_inf[k] = atab_inf;
						break;
					}
					if (agroup_i[k] == i)
						break;
				}
				atab_inf = 0x240 + 8 * k + j;
				i = opinfo[i] + j;
			}
			if (optype[i] == OPCOPR) {
				if (*p == '/') {
					int j = getslash(&p);

					atab_inf = 0x200 + j * 8 + (i - 0xd8);
					i = opinfo[i] + j;
				} else {
					atab_xtra = getbyte(&p);
					if (atab_xtra < 0xc0)
						linenofail("Bad second escape byte");
					i = opinfo[i] + 8 + ((atab_xtra - 0xc0) >> 3);
					if (optype[i] == OPFPGROUP)
						i = opinfo[i] + (atab_xtra & 7);
				}
			}
			switch (*p++) {
			case '.':
				machine = getmachine(&p);
				if (!asm_only) {
					entertable(i, OPSIMPLE, mnem);
					opmach[i] = machine;
				}
				atab_key = 0;
				/* none of these are lockable */
				break;
			case '*':	/* lock or rep... prefix */
				add_to_asmtab(ASM_LOCKREP);
				add_to_asmtab(atab_inf);	/* special case */
				atab_addendum = '\0';
				break;
			case '&':	/* segment prefix */
				add_to_asmtab(ASM_SEG);
				add_to_asmtab(atab_inf);	/* special case */
				atab_addendum = '\0';
				break;
			case ':': {
				struct keytab *kp = lookupkey(getkey(&p));
				int width = kp->width;
				int j;

				machine = getmachine(&p);
				if (dis_only)
					; //atab_addendum = '\0';
				else {
					if (ordsmall[kp - olkeydict])
						linenofail("Variants out of order.");
					marksmall(kp);
				}
				atab_key = kp->value + 1;
				if ((i >= 256 && i < SPARSE_BASE)
					|| i >= SPARSE_BASE + 256) {
					if (width > 2)
						linenofail("width failure");
					width = 1;
				}
				if (i & (width - 1))
					linenofail("width alignment failure");
				if (!asm_only)
					for (j = (i == 0x90); j < width; ++j) {
						/*    ^^^^^^^^^  kludge for NOP instr. */
						entertable(i|j, oloffset[kp->value], mnem);
						opmach[i | j] = machine;
						if (lockable) {
							if (n_locktab >= MAX_LOCKTAB_ENTRIES)
								linenofail("Too many lockable "
										   "instructions");
							locktab[n_locktab] = i | j;
							++n_locktab;
						}
					}
			}
			break;
			default:
				linenofail("Syntax error.");
			}
			if (atab_addendum != '\0' && dis_only == False ) {
				atab_inf = atab_inf * (unsigned short) (n_ol_types + 1)
					+ atab_key;
				add_to_asmtab(atab_inf >> 8);
				if ((atab_inf >> 8) >= ASM_MACH0)
					fail("Assembler table is too busy");
				add_to_asmtab(atab_inf);
				if (atab_xtra != 0)
					add_to_asmtab(atab_xtra);
			}
			if (pslash != NULL) {
				if (n_slash_entries >= MAX_SLASH_ENTRIES)
					linenofail("Too many slash entries");
				slashtab_seq[n_slash_entries] = i;
				slashtab_mn[n_slash_entries] = mn_alt;
				++n_slash_entries;
			} else if (phash != NULL) {
				if (n_hash_entries >= MAX_HASH_ENTRIES)
					linenofail("Too many hash entries");
				hashtab_seq[n_hash_entries] = i;
				hashtab_mn[n_hash_entries] = mn_alt;
				++n_hash_entries;
			} else if (pstar != NULL) {
				if (n_star_entries >= MAX_STAR_ENTRIES)
					linenofail("Too many star entries");
				startab_seq[n_star_entries] = i;
				startab_mn[n_star_entries] = mn_alt;
				++n_star_entries;
			}
		} //end while variants
		if (*p != '\0')
			linenofail("Syntax error.");
		if (atab_addendum != '\0') {
			add_to_asmtab(atab_addendum);	/* ASM_END, if applicable */
		}
	}
}

/*
 *	Print everything onto the file.
 */

struct inforec {	/* strings to put into comment fields */
	int seqno;
	char *string;
} tblcomments[] = {
	{0, "main opcode part"},
	{GROUP(1), "Intel group 1"},
	{GROUP(3), "Intel group 2"},
	{GROUP(5), "Intel group 2a"},
	{GROUP(6), "Intel group 3"},
	{GROUP(7), "Intel group 5"},
	{GROUP(8), "Intel group 6"},
	{GROUP(9), "Intel group 7"},
	{COPR(0), "Coprocessor d8"},
	{COPR(1), "Coprocessor d9"},
	{COPR(2), "Coprocessor da"},
	{COPR(3), "Coprocessor db"},
	{COPR(4), "Coprocessor dc"},
	{COPR(5), "Coprocessor dd"},
	{COPR(6), "Coprocessor de"},
	{COPR(7), "Coprocessor df"},
	{FPGROUP(0), "Coprocessor groups"},
	{-1, NULL}};

void put_dw(FILE *f2, const char *label, int *datap, int n)
{
	const char *initstr;
	int i;

	fputs(label,f2);
	while (n > 0) {
		initstr = "\tdw ";
		for (i = (n <= 8 ? n : 8); i > 0; --i) {
			fputs(initstr, f2);
			initstr = ",";
			fprintf(f2, "0%xh", *datap++);
		}
		fputs("\n", f2);
		n -= 8;
	}
}

char *spectab[] = {"WAIT", "ORG", "DD", "DW", "DB"};
char *spectab2[] = {"LOCKREP", "SEG"};

void dumptables(FILE *f2)
{
	int offset;
	struct mnrec *mnp;
	int colsleft;
	char *auxstr;
	struct inforec *tblptr;
	int i;
	int j;
	unsigned int k;
	unsigned int l;
    char *pmne;

	if (num_mnrecs == 0)
	    fail("No assembler mnemonics!");

	/*
	 * Sort the mnemonics alphabetically.
	 */
#if SORTMN
	mnhead = mn_sort(mnlist, num_mnrecs);
#else
	mnhead = mnlist;
	for (i = 0; i < num_mnrecs; i++)
		mnlist[i].next = &mnlist[i+1];
    mnlist[num_mnrecs-1].next = NULL;
#endif

	fprintf(f2, "\n;--- This file was generated by mktables.exe.\n" );

	/*
	 * Print out oplists[]
	 */

	fputs( "\n;--- Operand type lists.\n"
		  ";--- They were read from file INSTR.KEY.\n\n"
		  "oplists label byte\n\topl\t;void - for instructions without operands\n", f2);
	for (i = 0; i < n_ol_types; ++i) {
#if 0
		unsigned char szKey[4];
		if (olkeydict[i].key > 0xFF) {
			szKey[0] = (unsigned char)(olkeydict[i].key >> 8);
			szKey[1] = (unsigned char)(olkeydict[i].key & 0xFF);
			szKey[2] = '\0';
		} else {
			szKey[0] = (unsigned char)(olkeydict[i].key);
			szKey[1] = '\0';
		}
		fprintf(f2, "\topl %s, %s\t; ofs=%Xh\n", szKey, olnames[i], oloffset[i]);
#else
		fprintf(f2, "\topl %s\t; idx=%u, ofs=%Xh\n", olnames[i], i+1, oloffset[i]);
#endif
	}

#if 0
	fprintf(f2, "\nOPLIST_27\tEQU 0%Xh\t; this is the OP_IMM8 key\n",
			oloffset[lookupkey('27')->value]);
	fprintf(f2, "OPLIST_41\tEQU 0%Xh\t; this is the OP_ES key\n",
			oloffset[lookupkey('41')->value]);
#endif

//	fprintf(f2, "\nASMMOD\tEQU %u\n", n_ol_types+1 );
	fprintf(f2, "\nASMMOD\tEQU opidx\n" );

	/*
	 * Dump out agroup_inf.
	 */

	fputs( "\n;--- Assembler: data on groups.\n"
		";--- If HiByte == 01, it's a \"0F-prefix\" group.\n\n"
		"agroups label word\n", f2);
	for (i = 0; i < n_agroups; ++i) {
	    fprintf(f2, "\tdw %03Xh\t;%u\n", agroup_inf[i],i);
	}

	/*
	 * Dump out asmtab.
	 */

	fputs( "\n;--- List of assembler mnemonics and data.\n"
		  ";--- variant's 1. argument (=a):\n"
		  ";---   if a < 0x100: one byte opcode.\n"
		  ";---   if a >= 0x100 && a < 0x200: two byte \"0F\"-opcode.\n"
		  ";---   if a >= 0x200 && a < 0x240: fp instruction.\n"
		  ";---   if a >= 0x240: refers to agroups [macro AGRP() is used].\n"
		  ";--- variant's 2. argument is index into array opindex.\n\n"
		  "mnlist label byte\n", f2);
	for (mnp = mnhead, offset = 0; mnp != NULL; mnp = mnp->next) {
		mnp->offset = offset + 2;
		offset += mnp->len + 2;
		fprintf(f2, "\tmne %s", mnp->string );

		i = mnp->asmoffset;

		if (asmtab[i] == ASM_D16 && asmtab[i+1] == ASM_D32) {
			//fprintf(f2, ", ASM_D16\t; ofs=%04x\n", i);
			fprintf(f2, ", ASM_D16\t; ofs=%Xh\n", i);
		} else if (asmtab[i] >= ASM_WAIT ) {
			fprintf(f2, ", ASM_%s\t; ofs=%Xh\n", spectab[asmtab[i] - ASM_WAIT], i );
		} else if ((asmtab[i] == ASM_SEG || asmtab[i] == ASM_LOCKREP)) {
			fprintf(f2, ", ASM_%s, %03xh\t; ofs=%Xh\n", spectab2[asmtab[i] - ASM_LOCKREP], asmtab[i+1], i);
		} else {
			j = i;
			while ( asmtab[j] > ASM_SEG && asmtab[j] < ASM_WAIT) {
				switch ( asmtab[j]) {
				case ASM_AAX:
					fprintf(f2, ", ASM_AAX");
					break;
				case ASM_D16:
					fprintf(f2, ", ASM_D16");
					break;
				case ASM_D32:
					fprintf(f2, ", ASM_D32");
					break;
				}
				j++;
			}
			fprintf(f2, "\t; ofs=%Xh\n", i );

			for (; j < n_asm_tab;) {
				char *lockstr = "";
				char machstr[12] = {""};
				if (asmtab[j] == 0xFF)
					break;

				if ( asmtab[j] == ASM_LOCKABLE) {
					lockstr = "ASM_LOCKABLE";
					j++;
				}
				/* there's a problem with DEC and INC! */
				if (asmtab[j] == 0xFF)
					break;
				if ( asmtab[j] >= ASM_MACH0 && asmtab[j] <= ASM_MACH6) {
					sprintf(machstr, "ASM_MACH%u", asmtab[j] - ASM_MACH0);
					j++;
				}

				k = (int)asmtab[j] * 256 + asmtab[j+1];
				l = k % (n_ol_types+1);
				k = k / (n_ol_types+1);

				if ( k >= 0xD8 && k <= 0xDF)
					fprintf( f2, "\t fpvariant ");
				else
					fprintf( f2, "\t variant ");

				if ( k >= 0x240 )
					fprintf(f2, "AGRP(%u,%u), %u", (k - 0x240) >> 3, (k - 0x240) & 7, l);
				else
					fprintf(f2, "%03xh, %u", k, l);
				j += 2;

				if ( k >= 0xD8 && k <= 0xDF) {
					fprintf(f2, ", %03xh", asmtab[j]);
					j++;
				}
				if (*lockstr == '\0' && machstr[0] == '\0')
					fprintf(f2, "\n");
				else if (machstr[0] == '\0')
					fprintf(f2, ", %s\n", lockstr);
				else
					fprintf(f2, ", %s, %s\n", lockstr, machstr);
			}
			fprintf(f2, "\t endvariant\n");
			i = j;
		}

	}
	fputs( "\nend_mnlist label byte\n\n", f2);

	if (offset >= (1 << MSHIFT)) {
		fprintf(stderr, "%d bytes of mnemonics.  That's too many.\n", offset);
		exit(1);
	}

#if 0
	/*
	 * Print the opindex array.
	 */

	auxstr = "\n;--- Array of byte offsets for the oplists array (above)."
		"\n;--- It is used by the assembler to save space.\n"
		"\nopindex label byte\n\tdb   0,";
	for (i = 1; i <= n_ol_types; ++i) {
		fprintf(f2, "%s%3d", auxstr, oloffset[i-1] - OPTYPES);
		if ((i & 7) == 7)
			auxstr = "\n\tdb ";
		else
			auxstr = ",";
	}
#endif

	/*
	 * Print out optype[]
	 */

	fputs( ";--- Disassembler: compressed table of the opcode types."
		  "\n;--- If the item has the format OT(xx), it refers to table 'oplists'."
		  "\n;--- Otherwise it's an offset for internal table 'disjmp'."
		  "\n\noptypes label byte", f2);
	auxstr = "\n\tdb ";
	tblptr = tblcomments;

	for (i = 0; i < SPARSE_BASE; i += 8) {
		for (j = 0; j < 8; ++j) {
			fputs(auxstr, f2);
			if ( optype[i + j] >= OPTYPES ) {
				int y = 0;
				if ( optype[i + j] > OPTYPES)
					for ( y = 1; y <= n_ol_types; y++ )
						if (oloffset[y-1] == optype[i + j])
							break;
				if (y <= n_ol_types)
					fprintf(f2, "OT(%02X)", y );
				else
					fail("offset not found for %u: %X", i+j, optype[i+j]);
			} else
				fprintf(f2, "  %03Xh", optype[i + j]);
			auxstr = ",";
		}
		fprintf(f2, "\t; %02x - %02x", i, i + 7);
		if (i == tblptr->seqno) {
			fprintf(f2, " (%s)", (tblptr++)->string);
		}
		auxstr = "\n\tdb ";
	}

	fprintf(f2, "SPARSE_BASE\tequ $ - optypes\n");

	auxstr = "\n;--- The rest of these are squeezed.\n" "\tdb      0,";
	for (i = SPARSE_BASE, k=1; i < NOPS; ++i)
		if ((j = optype[i]) != 0) {
			int y = 0;
			if ( j >= OPTYPES) {
				int y = 0;
				if ( j > OPTYPES)
					for ( y = 1; y <= n_ol_types; y++ )
						if (oloffset[y-1] == j )
							break;
				if (y <= n_ol_types)
					fprintf(f2, "%sOT(%02X)", auxstr, y );
				else
					fail("offset not found for %u: %X", i, j );
			} else
				fprintf(f2, "%s  %03Xh", auxstr, j);
			k++;
			if ((k & 7) == 0) {
				fprintf(f2, "\t;%02X", k-8);
				auxstr = "\n\tdb ";
			} else
				auxstr = ",";
		}
	fputs("\n", f2);

	/*
	 * Print out opinfo[]
	 */

	fputs("\n", f2);
	for (i = 1; i < 7; i++)
		fprintf(f2, "P%u86\tequ %Xh\n", i, i << MSHIFT );

	fputs( "\n\talign 2\n", f2 );

	fputs( "\n;--- Disassembler: compressed table of additional information."
		   "\n;--- Bits 0-11 usually are the offset of the mnemonics table."
		   "\n;--- Bits 12-15 are the cpu which introduced this opcode."
		  "\n\nopinfo label word\n", f2);

	for (i = 0; i < SPARSE_BASE; i += 4) {
		auxstr = "\tdw ";
		for (j = 0; j < 4; ++j) {
			fputs(auxstr, f2);
			if (opmach[i+j])
				fprintf(f2, " P%u86 +", opmach[i+j] );
			if (optype[i + j] >= OPTYPES) {
				fprintf(f2, " MN_%s", mnlist[opinfo[i+j]].string );
			} else
				fprintf(f2, " %04xh", opinfo[i+j] );
			auxstr = ",";
		}
		fprintf(f2, "\t; %02x\n", i);
	}
	auxstr = ";--- The rest of these are squeezed.\n" "\tdw  0,";
	for (i = SPARSE_BASE, k = 1; i < NOPS; ++i) {
		if ((j = optype[i]) != 0) {
			fprintf(f2, auxstr);
			if (opmach[i])
				fprintf(f2, " P%u86 +", opmach[i] );
			if (j >= OPTYPES) {
				fprintf(f2, " MN_%s", mnlist[opinfo[i]].string );
			} else
				fprintf(f2, " %04xh", opinfo[i] );
			k++;
			if ((k & 3) == 0) {
				fprintf(f2, "\t;%02X", k - 4);
				auxstr = "\n\t\dw ";
			} else
				auxstr = ",";
		}
	}
	fputs("\n", f2);

	/*
	 * Print out sqztab
	 */

	fputs( "\n;--- Disassembler: table converts unsqueezed numbers to squeezed."
		  "\n;--- 1E0-2DF are extended opcodes (0F xx).\n"
		  "\n\nsqztab label byte\n", f2);

	k = 0;
	for (i = SPARSE_BASE; i < NOPS; i += 8) {
		if ( i == SPARSE_BASE + 256 )
			fprintf(f2, "\n--- %u sparse groups\n\n", NSGROUPS );
		else if ( i == SPARSE_BASE + 256 + 8 * NSGROUPS ) {
			fprintf(f2, "\n--- %u sparse fpu groups\n\n", NUMBER(sp_fpgrouptab) );
			fprintf(f2, "SFPGROUPS equ SPARSE_BASE + ( $ - sqztab )\n" );
			fprintf(f2, "SFPGROUP3 equ SFPGROUPS + 8 * 3\n" );
		}
		auxstr = "\tdb ";
		for (j = 0; j < 8; ++j) {
			fprintf(f2, "%s%3d", auxstr, optype[i + j] == 0 ? 0 : ++k);
			auxstr = ",";
		}
		fprintf(f2, "\t;%X\n", i);
	}

	/*
	 * Print out the cleanup tables.
	 */

	fputs( "\n;--- Disassembler: table of mnemonics that change in the "
		  "presence of a WAIT" "\n;--- instruction.\n\n", f2);
	put_dw(f2, "wtab1", startab_seq, n_star_entries);
#if 0
	for (i = 0; i < n_star_entries; ++i)
		startab_mn[i] = mnlist[startab_mn[i]].offset;
	put_dw(f2, "wtab2", startab_mn, n_star_entries);
#else
	fputs("wtab2 label word\n", f2);
	for (i = 0; i < n_star_entries; ++i)
        fprintf(f2, "\tdw MN_%s\n", mnlist[startab_mn[i]].string);
#endif
	fprintf(f2, "N_WTAB\tequ ($ - wtab2) / 2\n");

	fputs( "\n;--- Disassembler: table for operands which have a different "
		"mnemonic for" "\n;--- their 32 bit versions (66h prefix).\n\n", f2);
	put_dw(f2, "ltabo1", slashtab_seq, n_slash_entries);
#if 0
	for (i = 0; i < n_slash_entries; ++i)
		slashtab_mn[i] = mnlist[slashtab_mn[i]].offset;
	put_dw(f2, "ltabo2", slashtab_mn, n_slash_entries);
#else
	fputs("ltabo2 label word\n", f2);
	for (i = 0; i < n_slash_entries; ++i)
        fprintf(f2, "\tdw MN_%s\n", mnlist[slashtab_mn[i]].string);
#endif
	fprintf(f2, "N_LTABO\tequ ($ - ltabo2) / 2\n" );

	fputs( "\n;--- Disassembler: table for operands which have a different "
		"mnemonic for"  "\n;--- their 32 bit versions (67h prefix).\n\n", f2);
	put_dw(f2, "ltaba1", hashtab_seq, n_hash_entries);
#if 0
	for (i = 0; i < n_hash_entries; ++i)
		hashtab_mn[i] = mnlist[hashtab_mn[i]].offset;
	put_dw(f2, "ltaba2", hashtab_mn, n_hash_entries);
#else
	fputs("ltaba2 label word\n", f2);
	for (i = 0; i < n_hash_entries; ++i)
        fprintf(f2, "\tdw MN_%s\n", mnlist[hashtab_mn[i]].string);
#endif
	fprintf(f2, "N_LTABA\tequ ($ - ltaba2) / 2\n" );

	fputs( "\n;--- Disassembler: table of lockable instructions\n\n" , f2);
	put_dw(f2, "locktab label word\n", locktab, n_locktab);
	fprintf( f2, "N_LOCK\tequ ($ - locktab) / 2\n" );

}

int cdecl main()
{
	FILE *f1;
	FILE *f2;
	int offset;

	/*
	 * Read in the key dictionary.
	 */

	f1 = openread("instr.key");
	offset = OPTYPES + 1;
	while (getline(f1)) {
		char *p = line;
		char *q = strchr(p, ';');
		int i;

		if (q) {
			*q = '\0';
			q--;
			while (q > p && (*q == ' ' || *q == '\t')) {
				*q = '\0';
				q--;
			}
		}

		if (n_keys >= MAX_OL_TYPES)
			fail("Too many keys.");
		olkeydict[n_keys].key = getkey(&p);
		p = skipwhite(p);
		for (i = 0;; ++i) {
			if (i >= n_ol_types) {
				char *q = xmalloc(strlen(p) + 1, "operand type name");

				strcpy(q, p);
				if (n_ol_types >= MAX_OL_TYPES)
					fail("Too many operand list types.");
				olnames[n_ol_types] = q;
				oloffset[n_ol_types] = offset;
				for (;;) {
					++offset;
					q = strchr(q, ',');
					if (q == NULL) break;
					++q;
				}
				++offset;
				++n_ol_types;
			}
			if (strcmp(p, olnames[i]) == 0)
				break;
		}
		olkeydict[n_keys].value = i;
		olkeydict[n_keys].width = 1;
		if (strstr(p, "OP_ALL") != NULL)
			olkeydict[n_keys].width = 2;
		else if (strstr(p, "OP_R_ADD") != NULL)
			olkeydict[n_keys].width = 8;
		++n_keys;
	}
	fclose(f1);
	if (offset >= 256) {
		fprintf(stderr, "%d bytes of operand lists.  That's too many.\n",
				offset);
		exit(1);
	}

	/*
	 * Read in the ordering relations.
	 */

	f1 = openread("instr.ord");
	while (getline(f1)) {
		char *p = line;

		if (n_ords >= MAX_N_ORDS)
			fail ("Too many ordering restrictions.");
		keyord1[n_ords] = lookupkey(getkey(&p));
		p = skipwhite(p);
		keyord2[n_ords] = lookupkey(getkey(&p));
		if (*p != '\0')
			fail("Syntax error in ordering file.");
		++n_ords;
	}
	fclose(f1);

	/*
	 * Do the main processing.
	 */

	f1 = openread("instr.set");
	read_is(f1);
	fclose(f1);

	/*
	 * Write the file.
	 */

	f2 = fopen("debugtbl.tmp", "w");
	if (f2 == NULL) {
		perror("debugtbl.tmp");
		exit(1);
	}

	dumptables(f2);

	fclose(f2);

	/*
	 * Move the file to its original position.
	 */

	unlink("debugtbl.old");

	if (rename("debugtbl.inc", "debugtbl.old") == -1) {
		perror("rename debugtbl.inc -> debugtbl.old");
		//return 1;
	}
	if (rename("debugtbl.tmp", "debugtbl.inc") == -1) {
		perror("rename debugtbl.tmp -> debugtbl.inc");
		return 1;
	}

	puts("Done.");

	return 0;
}
