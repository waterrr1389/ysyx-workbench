#pragma once
#include <common.h>
#define SHT_SYMTAB 2 /* Symbol table */
#define SHT_STRTAB 3 /* String table */
#define STT_FUNC 2   /* Symbol is a code object */

#define FUNC_LENGH 64

// 用于提取符号信息的宏
#define ELF32_ST_TYPE(i) ((i) & 0xf)
#define ELF64_ST_TYPE(i) ((i) & 0xf)

/* Type for a 16-bit quantity.  */
typedef uint16_t Elf32_Half;
typedef uint16_t Elf64_Half;

/* Types for signed and unsigned 32-bit quantities.  */
typedef uint32_t Elf32_Word;
typedef int32_t Elf32_Sword;
typedef uint32_t Elf64_Word;
typedef int32_t Elf64_Sword;

/* Types for signed and unsigned 64-bit quantities.  */
typedef uint64_t Elf32_Xword;
typedef int64_t Elf32_Sxword;
typedef uint64_t Elf64_Xword;
typedef int64_t Elf64_Sxword;

/* Type of addresses.  */
typedef uint32_t Elf32_Addr;
typedef uint64_t Elf64_Addr;

/* Type of file offsets.  */
typedef uint32_t Elf32_Off;
typedef uint64_t Elf64_Off;

/* Type for section indices, which are 16-bit quantities.  */
typedef uint16_t Elf32_Section;
typedef uint16_t Elf64_Section;

/* Type for version symbol information.  */
typedef Elf32_Half Elf32_Versym;
typedef Elf64_Half Elf64_Versym;

/* The ELF file header.  This appears at the start of every ELF file.  */

#define EI_NIDENT (16)

typedef struct {
  unsigned char e_ident[EI_NIDENT]; /* Magic number and other info */
  Elf32_Half e_type;                /* Object file type */
  Elf32_Half e_machine;             /* Architecture */
  Elf32_Word e_version;             /* Object file version */
  Elf32_Addr e_entry;               /* Entry point virtual address */
  Elf32_Off e_phoff;                /* Program header table file offset */
  Elf32_Off e_shoff;                /* Section header table file offset */
  Elf32_Word e_flags;               /* Processor-specific flags */
  Elf32_Half e_ehsize;              /* ELF header size in bytes */
  Elf32_Half e_phentsize;           /* Program header table entry size */
  Elf32_Half e_phnum;               /* Program header table entry count */
  Elf32_Half e_shentsize;           /* Section header table entry size */
  Elf32_Half e_shnum;               /* Section header table entry count */
  Elf32_Half e_shstrndx;            /* Section header string table index */
} Elf32_Ehdr;

typedef struct {
  unsigned char e_ident[EI_NIDENT]; /* Magic number and other info */
  Elf64_Half e_type;                /* Object file type */
  Elf64_Half e_machine;             /* Architecture */
  Elf64_Word e_version;             /* Object file version */
  Elf64_Addr e_entry;               /* Entry point virtual address */
  Elf64_Off e_phoff;                /* Program header table file offset */
  Elf64_Off e_shoff;                /* Section header table file offset */
  Elf64_Word e_flags;               /* Processor-specific flags */
  Elf64_Half e_ehsize;              /* ELF header size in bytes */
  Elf64_Half e_phentsize;           /* Program header table entry size */
  Elf64_Half e_phnum;               /* Program header table entry count */
  Elf64_Half e_shentsize;           /* Section header table entry size */
  Elf64_Half e_shnum;               /* Section header table entry count */
  Elf64_Half e_shstrndx;            /* Section header string table index */
} Elf64_Ehdr;

/* Section header.  */

typedef struct {
  Elf32_Word sh_name;      /* Section name (string tbl index) */
  Elf32_Word sh_type;      /* Section type */
  Elf32_Word sh_flags;     /* Section flags */
  Elf32_Addr sh_addr;      /* Section virtual addr at execution */
  Elf32_Off sh_offset;     /* Section file offset */
  Elf32_Word sh_size;      /* Section size in bytes */
  Elf32_Word sh_link;      /* Link to another section */
  Elf32_Word sh_info;      /* Additional section information */
  Elf32_Word sh_addralign; /* Section alignment */
  Elf32_Word sh_entsize;   /* Entry size if section holds table */
} Elf32_Shdr;

typedef struct {
  Elf64_Word sh_name;       /* Section name (string tbl index) */
  Elf64_Word sh_type;       /* Section type */
  Elf64_Xword sh_flags;     /* Section flags */
  Elf64_Addr sh_addr;       /* Section virtual addr at execution */
  Elf64_Off sh_offset;      /* Section file offset */
  Elf64_Xword sh_size;      /* Section size in bytes */
  Elf64_Word sh_link;       /* Link to another section */
  Elf64_Word sh_info;       /* Additional section information */
  Elf64_Xword sh_addralign; /* Section alignment */
  Elf64_Xword sh_entsize;   /* Entry size if section holds table */
} Elf64_Shdr;

/* Symbol table entry.  */
typedef struct {
  Elf32_Word st_name;     /* Symbol name (string tbl index) */
  Elf32_Addr st_value;    /* Symbol value */
  Elf32_Word st_size;     /* Symbol size */
  unsigned char st_info;  /* Symbol type and binding */
  unsigned char st_other; /* Symbol visibility */
  Elf32_Section st_shndx; /* Section index */
} Elf32_Sym;

typedef struct {
  Elf64_Word st_name;     /* Symbol name (string tbl index) */
  unsigned char st_info;  /* Symbol type and binding */
  unsigned char st_other; /* Symbol visibility */
  Elf64_Section st_shndx; /* Section index */
  Elf64_Addr st_value;    /* Symbol value */
  Elf64_Xword st_size;    /* Symbol size */
} Elf64_Sym;

#ifdef CONFIG_ISA64
typedef Elf64_Ehdr Elf_Ehdr;
typedef Elf64_Shdr Elf_Shdr;
typedef Elf64_Sym Elf_Sym;
typedef Elf64_Off Elf_Off;
typedef Elf64_Addr Elf_Addr;
typedef Elf64_Half Elf_Half;
typedef Elf64_Xword Elf_Xword;
#else
typedef Elf32_Ehdr Elf_Ehdr;
typedef Elf32_Shdr Elf_Shdr;
typedef Elf32_Sym Elf_Sym;
typedef Elf32_Off Elf_Off;
typedef Elf32_Addr Elf_Addr;
typedef Elf32_Half Elf_Half;
typedef Elf32_Xword Elf_Xword;
#endif

void ftrace(word_t pc);
void call_record(word_t addr, word_t dst);
void ret_record(word_t addr);