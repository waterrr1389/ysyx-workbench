#include "ftrace.h"
#include "callstack.h"
#include "debug.h"

static Elf_Shdr symtab, strtab;
static FILE *fp;
int32_t symtab_count;
static char *strtab_buf;
static Elf_Sym *symbols;

// itrace init
void readelf(const char *path) {
  if (path == NULL)
    return;

  fp = fopen(path, "r");
  Assert(fp != NULL, "%s\n", "ERROR: file does not exist");
  int number;

  // Read the ELF executable header
  Elf_Ehdr Ehdr;
  number = fread((void *)&Ehdr, sizeof(Elf_Ehdr), 1, fp);
  Assert(number == 1, "%s\n", "Faield to read offset");
  // Check magic number
  unsigned char *ident = Ehdr.e_ident;
  Assert(ident[0] == 0x7f && ident[1] == 'E' && ident[2] == 'L' &&
             ident[3] == 'F',
         "%s\n", "ERROR: Invalid ELF file");

  // Seek to section header table
  number = fseek(fp, Ehdr.e_shoff, SEEK_SET);
  Assert(number == 0, "%s\n", "Failed to direct to section table");

  Elf_Shdr tmp;
  for (int i = 0; i < Ehdr.e_shnum; i++) {
    // 依次读取每一个 Section Header
    number = fread((void *)&tmp, sizeof(Elf_Shdr), 1, fp);
    Assert(number == 1, "%s\n", "Failed to read section header");

    if (tmp.sh_type == SHT_SYMTAB) {
      symtab = tmp;
    } else if (tmp.sh_type == SHT_STRTAB) {
      // 如果当前的索引 i 等于 Ehdr 中记录的 e_shstrndx
      // 我们需要的是 .strtab (用来存函数变量名的)
      if (i != Ehdr.e_shstrndx) {
        strtab = tmp;
      }
    }
  }

  // Allocate memory for string table
  strtab_buf = malloc(strtab.sh_size + 1);
  fseek(fp, strtab.sh_offset, SEEK_SET);
  fread(strtab_buf, strtab.sh_size, 1, fp);

  // Alloccate memory for symbol table
  symtab_count = symtab.sh_size / sizeof(Elf_Sym);
  symbols = malloc(symtab_count * sizeof(Elf_Sym));
  fseek(fp, symtab.sh_offset, SEEK_SET);
  fread(symbols, sizeof(Elf_Sym), symtab_count, fp);

  // Initialize Call Stack
  init_stack();
}

// implement ftrace
void ftrace(word_t pc) {
  printf("Hello from ftrace\n\
            Offset of symtab is 0x%x\n\
            Offset of strtab is 0x%x\n",
         symtab.sh_offset, strtab.sh_offset);
}

void get_func_name(char *func_name, word_t addr) {
  if (symbols == NULL || strtab_buf == NULL)
    return;

  for (size_t i = 0; i < symtab_count; i++) {
    // 获取当前符号的类型
    // 注意：根据 ISA64 配置，Elf_Sym 可能是 Elf32_Sym 或 Elf64_Sym
    // 它们的 st_info 字段位置一样，我们可以用统一的宏处理
    unsigned char info = symbols[i].st_info;

    // 检查符号类型是否为函数 (STT_FUNC)
    if (ELF64_ST_TYPE(info) == STT_FUNC) {
      Elf_Addr value = symbols[i].st_value;
      Elf_Xword size = symbols[i].st_size;

      // 检查地址是否在这个函数的范围内
      if (addr >= value && addr < (value + size)) {
        // 找到了！从字符串表中获取名字
        // st_name 是字符串在 strtab 中的偏移量
        const char *name = strtab_buf + symbols[i].st_name;

        // 安全复制防止缓冲区溢出
        strncpy(func_name, name, FUNC_LENGH - 1);
        func_name[FUNC_LENGH - 1] = '\0'; // 确保结尾
        return;
      }
    }
  }
  // 如果没找到，可以填一个 unknown 或者不处理
  strncpy(func_name, "???", FUNC_LENGH - 1);
}

void print_indent(int depth) {
  for (int i = 0; i < depth; i++)
    printf("  ");
}

void call_record(word_t addr, word_t dst) {
  char func_name[FUNC_LENGH] = {0};

  // 1. 解析目标地址的函数名
  get_func_name(func_name, dst);

  // 2. 打印追踪日志
  int depth = get_stack_depth();
  print_indent(depth);
  // 这里的 addr 是 jal 指令的地址 (pc)
  // dst 是跳转的目标地址
  printf("0x%lx: call [%s@0x%lx]\n", (unsigned long)addr, func_name,
         (unsigned long)dst);

  // 3. 将调用信息入栈
  stack_push(addr, dst, func_name);
}

void ret_record(word_t addr) {
  // addr 是 ret 指令 (jalr x0, 0(ra)) 的地址
  // 1. 获取当前栈顶函数名 (也就是我们正在返回的函数)
  CallStackNode *stack_top = get_stack_top();
  const char *func_name = (stack_top) ? stack_top->func_name : "???";

  // 2. 打印返回日志
  int depth = get_stack_depth();
  if (depth > 0)
    depth--; // 返回时缩进减少一级
  print_indent(depth);
  printf("0x%lx: ret  [%s]\n", (unsigned long)addr, func_name);

  // 3. 出栈
  stack_pop();
}