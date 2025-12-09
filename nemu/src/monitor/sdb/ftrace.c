#include "ftrace.h"

static Elf64_Shdr symtab, strtab;
static FILE* fp;
static char* strtab_buf;
static Elf64_Sym* symbols;

// itrace init
void readelf(const char* path) {
    fp = fopen(path, "r");
    Assert(fp == NULL, "%s\n", "ERROR: file does not exist"); 
    int number;

    // Seek for the section header offset
    number = fseek(fp, SH_OFF, SEEK_SET);
    Assert( number != SH_OFF, "%s\n", "Failed to direct to section header");

    Elf64_Ehdr Ehdr;
    // Read the section header table offset
    number = fread((void*)&Ehdr, sizeof(Elf64_Off), 1,fp);
    Assert(number != sizeof(Elf64_Off), "%s\n", "Faield to read offset"); 
    
    // fseek to section header table
    number = fseek(fp,Ehdr.e_shoff, SEEK_SET);
    Assert(number != sizeof(Elf64_Shdr), "%s\n", "Failed to read section table entry");

    Elf64_Shdr tmp;
    for (Elf64_Half count = Ehdr.e_shnum; count > 0; count--) {
        // Read .symtab && .strtab
        fread((void*)&tmp, sizeof(Elf64_Shdr), 1, fp);
        if (tmp.sh_type == SHT_STRTAB) { 
           strtab = tmp; 
        } else if (tmp.sh_type == SHT_SYMTAB) {
           symtab = tmp;
        }
    }

    // Allocate space for strtab
    strtab_buf = malloc(strtab.sh_size+1);
    fseek(fp, strtab.sh_offset, SEEK_SET); 
    fread(strtab_buf, strtab.sh_size, 1, fp);

    // Alloc memory for all the symbols
    uint32_t symtab_count = symtab.sh_size / sizeof(Elf64_Sym);
    symbols = malloc(symtab_count * sizeof(Elf64_Sym));
    fseek(fp, symtab.sh_offset, SEEK_SET);
    fread(symbols, sizeof(Elf64_Sym), symtab_count, fp);
}

// implement itrace
void func_todo(word_t pc) {
    

}

