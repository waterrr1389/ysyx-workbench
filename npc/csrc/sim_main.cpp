#include "sim_main.h"
#include "Vtop.h"
#include "verilated.h"
#include "verilated_fst_c.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>

namespace {
constexpr uint32_t kMbase = 0x80000000u;
constexpr uint32_t kNopInst = 0x00000013u;
uint32_t *g_inst_img = nullptr;
size_t g_inst_img_size = 0;

Vtop *top = nullptr;
VerilatedContext *contextp = nullptr;
VerilatedFstC *tfp = nullptr;
bool sim_running = false;

int pc_to_index(uint32_t pc) { return static_cast<int>((pc - kMbase) / 4u); }

bool load_inst_img(const char *img_path) {
  FILE *img_file = fopen(img_path, "rb");
  if (img_file == nullptr) {
    fprintf(stderr, "Failed to open instruction file: %s\n", img_path);
    return false;
  }

  if (fseek(img_file, 0, SEEK_END) != 0) {
    fprintf(stderr, "Failed to seek instruction file: %s\n", img_path);
    fclose(img_file);
    return false;
  }

  const long file_size = ftell(img_file);
  if (file_size <= 0) {
    fprintf(stderr, "Instruction file is empty: %s\n", img_path);
    fclose(img_file);
    return false;
  }

  if (fseek(img_file, 0, SEEK_SET) != 0) {
    fprintf(stderr, "Failed to seek instruction file: %s\n", img_path);
    fclose(img_file);
    return false;
  }

  if ((file_size % 4) != 0) {
    fprintf(stderr, "Instruction file size must be a multiple of 4 bytes: %s\n",
            img_path);
    fclose(img_file);
    return false;
  }

  uint8_t *raw_data =
      static_cast<uint8_t *>(malloc(static_cast<size_t>(file_size)));
  if (raw_data == nullptr) {
    fprintf(stderr, "Failed to allocate memory for instruction file: %s\n",
            img_path);
    fclose(img_file);
    return false;
  }

  const size_t read_bytes =
      fread(raw_data, 1, static_cast<size_t>(file_size), img_file);
  fclose(img_file);
  if (read_bytes != static_cast<size_t>(file_size)) {
    fprintf(stderr, "Failed to read instruction file: %s\n", img_path);
    free(raw_data);
    return false;
  }

  free(g_inst_img);
  g_inst_img =
      static_cast<uint32_t *>(malloc(static_cast<size_t>(file_size)));
  if (g_inst_img == nullptr) {
    fprintf(stderr, "Failed to allocate instruction image: %s\n", img_path);
    free(raw_data);
    return false;
  }

  g_inst_img_size = static_cast<size_t>(file_size) / 4u;
  for (size_t i = 0; i < g_inst_img_size; ++i) {
    const size_t byte_index = i * 4u;
    const uint32_t inst = static_cast<uint32_t>(raw_data[byte_index]) |
                          (static_cast<uint32_t>(raw_data[byte_index + 1]) << 8u) |
                          (static_cast<uint32_t>(raw_data[byte_index + 2]) << 16u) |
                          (static_cast<uint32_t>(raw_data[byte_index + 3]) << 24u);
    g_inst_img[i] = inst;
  }
  free(raw_data);

  return true;
}

void fetch_inst() {
  const int index = pc_to_index(top->pc);
  const int img_size = static_cast<int>(g_inst_img_size);

  if (index >= 0 && index < img_size) {
    top->inst = g_inst_img[index];
    return;
  }

  // PC 越界时喂 NOP，避免访问非法地址导致仿真崩溃
  top->inst = kNopInst;
}

void step_and_dump_wave() {
  top->eval();
  contextp->timeInc(1);
  tfp->dump(contextp->time());
  top->clk = !top->clk;
}
} // namespace

bool is_sim_running() { return sim_running; }

void stop_simulation() { sim_running = false; }

void step_one_cycle() {
  if (!sim_running) {
    return;
  }
  fetch_inst();
  step_and_dump_wave();
  step_and_dump_wave();
}

void sim_init() {
  contextp = new VerilatedContext;
  top = new Vtop{contextp};
  tfp = new VerilatedFstC;
  Verilated::traceEverOn(true);

  top->trace(tfp, 99);
  tfp->open("waveform.fst");

  top->reset = 1;
  top->clk = 0;
  top->inst = 0;
  sim_running = true;

  for (int i = 0; i < 11; ++i) {
    step_and_dump_wave();
  }
  top->reset = 0;
}

void sim_exit() {
  if (tfp != nullptr) {
    tfp->close();
    delete tfp;
    tfp = nullptr;
  }
  delete top;
  top = nullptr;
  delete contextp;
  contextp = nullptr;
  free(g_inst_img);
  g_inst_img = nullptr;
  g_inst_img_size = 0;
  sim_running = false;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "Usage: %s <inst_file_path>\n", argv[0]);
    return EXIT_FAILURE;
  }
  if (!load_inst_img(argv[1])) {
    return EXIT_FAILURE;
  }

  sim_init();
  while (is_sim_running()) {
    step_one_cycle();
  }
  sim_exit();

  return 0;
}
