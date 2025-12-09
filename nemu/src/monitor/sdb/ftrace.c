#include "ftrace.h"

static Elf_Shdr symtab, strtab;
static FILE* fp;
static char* strtab_buf;
static Elf_Sym* symbols;

// itrace init
void readelf(const char* path) {
    if (path == NULL) return;

    fp = fopen(path, "r");
    Assert(fp != NULL, "%s\n", "ERROR: file does not exist"); 
    int number;

    // Read the ELF executable header
    Elf_Ehdr Ehdr;
    number = fread((void*)&Ehdr, sizeof(Elf_Ehdr), 1, fp);
    Assert(number == 1, "%s\n", "Faield to read offset"); 
    
    // Seek to section header table
    number = fseek(fp,Ehdr.e_shoff, SEEK_SET);
    Assert(number == 0, "%s\n", "Failed to direct to section table");

    Elf_Shdr tmp;
    for (int i = 0; i < Ehdr.e_shnum; i++) {
        // 依次读取每一个 Section Header
        number = fread((void*)&tmp, sizeof(Elf_Shdr), 1, fp);
        Assert(number == 1, "%s\n", "Failed to read section header");

        if (tmp.sh_type == SHT_SYMTAB) {
            symtab = tmp;
        } 
        else if (tmp.sh_type == SHT_STRTAB) {
            // 如果当前的索引 i 等于 Ehdr 中记录的 e_shstrndx
            // 我们需要的是 .strtab (用来存函数变量名的)
            if (i != Ehdr.e_shstrndx) {
                strtab = tmp;
            }
        }
    }

    // Allocate memory for string table
    strtab_buf = malloc(strtab.sh_size+1);
    fseek(fp, strtab.sh_offset, SEEK_SET); 
    fread(strtab_buf, strtab.sh_size, 1, fp);

    // Alloccate memory for symbol table
    uint32_t symtab_count = symtab.sh_size / sizeof(Elf_Sym);
    symbols = malloc(symtab_count * sizeof(Elf_Sym));
    fseek(fp, symtab.sh_offset, SEEK_SET);
    fread(symbols, sizeof(Elf_Sym), symtab_count, fp);
}

// implement ftrace
void ftrace(word_t pc) {
    printf("Hello from ftrace\n\
            Offset of symtab is 0x%x\n\
            Offset of strtab is 0x%x\n", 
            symtab.sh_offset,
            strtab.sh_offset);
}
