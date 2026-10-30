#include <verilated.h>

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "VysyxSoCFull.h"
#include "difftest.h"
#include "mem.h"

#ifdef TRACE
#include <verilated_fst_c.h>
#endif

#ifdef NVBOARD
#include <nvboard.h>
void nvboard_bind_all_pins(VysyxSoCFull *top);
#endif

namespace {

struct Retire {
  uint32_t pc, wdata, mem_addr;
  uint8_t rd, rd_wen, trap, ebreak, skip, mem_access;
};

std::vector<Retire> retired;

constexpr uint32_t RESET_PC = 0x30000000;
constexpr uint64_t WATCHDOG = 1000000;  // cycles without a retirement before giving up

// Serial line model on the SoC UART pins, 8N1. The TX decoder lets input wait for a prompt.
class SerialLine {
 public:
  explicit SerialLine(int cycles_per_bit) : bit(cycles_per_bit) {}

  void queue(const std::string &s, const std::string &after) {
    pending = s;
    trigger = after;
    armed = trigger.empty();
  }

  // Called once per cycle with the TX pin; returns the RX pin level.
  bool step(bool tx) {
    decode(tx);
    if (!armed && seen.size() >= trigger.size() &&
        seen.compare(seen.size() - trigger.size(), trigger.size(), trigger) == 0)
      armed = true;
    if (rx_bits == 0) {
      if (!armed || pending.empty()) return true;
      uint8_t c = pending[0];
      pending.erase(0, 1);
      rx_frame = (1u << 9) | ((uint32_t)c << 1);  // start bit 0, data LSB first, stop bit 1
      rx_bits = 10;
      rx_cnt = 0;
      armed = trigger.empty() || c != '\n';  // after a newline, wait for the next prompt
      if (!armed) seen.clear();
    }
    bool level = rx_frame & 1;
    if (++rx_cnt == bit) {
      rx_cnt = 0;
      rx_frame >>= 1;
      rx_bits--;
    }
    return level;
  }

 private:
  void decode(bool tx) {
    if (tx_bits == 0) {
      if (!tx) { tx_bits = 10; tx_cnt = bit / 2; tx_data = 0; }
      return;
    }
    if (--tx_cnt > 0) return;
    tx_cnt = bit;
    tx_bits--;
    if (tx_bits >= 1 && tx_bits <= 8) tx_data |= (uint32_t)tx << (8 - tx_bits);
    if (tx_bits == 0) {
      seen.push_back((char)tx_data);
      if (seen.size() > 256) seen.erase(0, seen.size() - 256);
    }
  }

  int bit;
  std::string pending, trigger, seen;
  bool armed = true;
  uint32_t rx_frame = 0, tx_data = 0;
  int rx_bits = 0, rx_cnt = 0, tx_bits = 0, tx_cnt = 0;
};

// PS/2 device side: sends queued scan code bytes as 11-bit frames; data changes while the clock
// is high and the controller samples it on the falling edge.
class Ps2Device {
 public:
  void queue_bytes(const std::vector<uint8_t> &b, uint64_t start) {
    bytes = b;
    start_cycle = start;
  }
  void step(uint64_t cycle, uint8_t &clk, uint8_t &data) {
    clk = 1;
    data = 1;
    if (cycle < start_cycle || (idx >= bytes.size() && bit == 0)) return;
    if (bit == 0) {
      uint8_t b = bytes[idx++];
      uint8_t parity = !__builtin_parity(b);
      frame = (1u << 10) | ((uint32_t)parity << 9) | ((uint32_t)b << 1);
      bit = 11;
      phase = 0;
    }
    int half = HALF;
    clk = phase < half ? 1 : 0;
    data = frame & 1;
    if (++phase == 2 * half) {
      phase = 0;
      frame >>= 1;
      if (--bit == 0) start_cycle = cycle + GAP;
    }
  }

 private:
  // About 16.7 kHz PS/2 clock and 1 ms between bytes at a 100 MHz core clock.
  static constexpr int HALF = 3000, GAP = 100000;
  std::vector<uint8_t> bytes;
  size_t idx = 0;
  uint64_t start_cycle = ~0ull;
  uint32_t frame = 0;
  int bit = 0, phase = 0;
};

// Captures one frame from the VGA pins into a PPM image.
class VgaCapture {
 public:
  void arm(const std::string &path, int skip_frames) { file = path; skip = skip_frames; }
  void step(bool hsync, bool vsync, bool valid, uint8_t r, uint8_t g, uint8_t b) {
    if (file.empty() || done) return;
    if (prev_vsync && !vsync) {  // start of vertical sync pulse: a frame ended
      if (capturing) { write(); done = true; return; }
      if (skip-- <= 0) { capturing = true; pix.clear(); }
    }
    prev_vsync = vsync;
    (void)hsync;
    if (capturing && valid) { pix.push_back(r); pix.push_back(g); pix.push_back(b); }
  }

 private:
  void write() {
    FILE *fp = fopen(file.c_str(), "wb");
    if (!fp) return;
    fprintf(fp, "P6\n640 480\n255\n");
    pix.resize(640 * 480 * 3);
    fwrite(pix.data(), 1, pix.size(), fp);
    fclose(fp);
    fprintf(stderr, "[sim] VGA frame written to %s\n", file.c_str());
  }
  std::string file;
  int skip = 0;
  bool prev_vsync = true, capturing = false, done = false;
  std::vector<uint8_t> pix;
};

struct Options {
  std::string vga_dump;
  int vga_skip = 1;
  uint16_t switches = 0;
  bool trace_gpio = false;
  std::vector<uint8_t> ps2;
  uint64_t ps2_at = 0;
  std::string mrom, flash, wave, uart_input, uart_after;
  int uart_bit = 16;
  bool difftest = false;
  uint64_t max_cycles = 2000000000ull;
};

std::string unescape(const std::string &s) {
  std::string r;
  for (size_t i = 0; i < s.size(); i++) {
    if (s[i] == '\\' && i + 1 < s.size()) {
      char c = s[++i];
      r += c == 'n' ? '\n' : c == 'r' ? '\r' : c == 't' ? '\t' : c;
    } else {
      r += s[i];
    }
  }
  return r;
}

void usage(const char *prog) {
  fprintf(stderr,
          "usage: %s [--mrom IMG] [--flash IMG] [--difftest] [--max-cycles N] [--wave FILE]\n"
          "          [--uart-input STR [--uart-after PROMPT]] [--uart-bit CYCLES]\n"
          "          [--switches V] [--trace-gpio] [--ps2 HEX,HEX,... [--ps2-at CYCLE]]\n"
          "          [--vga-dump FILE.ppm [--vga-skip FRAMES]]\n"
          "  --uart-input types STR on the serial port; with --uart-after each line waits for PROMPT\n", prog);
  exit(2);
}

Options parse(int argc, char **argv) {
  Options o;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= argc) usage(argv[0]);
      return argv[++i];
    };
    if (a == "--mrom") o.mrom = next();
    else if (a == "--flash") o.flash = next();
    else if (a == "--difftest") o.difftest = true;
    else if (a == "--max-cycles") o.max_cycles = strtoull(next().c_str(), nullptr, 0);
    else if (a == "--wave") o.wave = next();
    else if (a == "--uart-input") o.uart_input = unescape(next());
    else if (a == "--uart-after") o.uart_after = unescape(next());
    else if (a == "--uart-bit") o.uart_bit = atoi(next().c_str());
    else if (a == "--switches") o.switches = strtoul(next().c_str(), nullptr, 0);
    else if (a == "--trace-gpio") o.trace_gpio = true;
    else if (a == "--vga-dump") o.vga_dump = next();
    else if (a == "--vga-skip") o.vga_skip = atoi(next().c_str());
    else if (a == "--ps2-at") o.ps2_at = strtoull(next().c_str(), nullptr, 0);
    else if (a == "--ps2") {
      std::string list = next();
      for (size_t pos = 0; pos < list.size();) {
        size_t end = list.find(',', pos);
        if (end == std::string::npos) end = list.size();
        o.ps2.push_back((uint8_t)strtoul(list.substr(pos, end - pos).c_str(), nullptr, 16));
        pos = end + 1;
      }
    }
    else if (a.rfind("+", 0) == 0) continue;  // plusargs are for Verilator
    else usage(argv[0]);
  }
  return o;
}

}  // namespace

extern "C" void sim_retire(int pc, char rd, char rd_wen, int wdata, char trap, char ebreak, char skip,
                           char mem_access, int mem_addr) {
  retired.push_back(Retire{(uint32_t)pc, (uint32_t)wdata, (uint32_t)mem_addr, (uint8_t)rd,
                           (uint8_t)rd_wen, (uint8_t)trap, (uint8_t)ebreak, (uint8_t)skip,
                           (uint8_t)mem_access});
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Options opt = parse(argc, argv);
  if (!opt.mrom.empty()) mem::load(opt.mrom, mem::mrom, mem::MROM_SIZE);
  if (!opt.flash.empty()) mem::load(opt.flash, mem::flash, mem::FLASH_SIZE);

  auto *top = new VysyxSoCFull;
#ifdef TRACE
  VerilatedFstC *tfp = nullptr;
  if (!opt.wave.empty()) {
    Verilated::traceEverOn(true);
    tfp = new VerilatedFstC;
    top->trace(tfp, 99);
    tfp->open(opt.wave.c_str());
  }
#endif
#ifdef NVBOARD
  // NVBoard owns the board-side pins (switches, keyboard, serial terminal).
  nvboard_bind_all_pins(top);
  nvboard_init();
#endif
  SerialLine serial(opt.uart_bit);
  serial.queue(opt.uart_input, opt.uart_after);
  top->externalPins_uart_rx = 1;
  Ps2Device ps2;
  ps2.queue_bytes(opt.ps2, opt.ps2_at);
  VgaCapture vga;
  vga.arm(opt.vga_dump, opt.vga_skip);
  uint16_t last_led = 0;
  uint64_t last_seg = 0;

  uint64_t cycle = 0;
  auto tick = [&]() {
#ifdef NVBOARD
    nvboard_update();
#else
    top->externalPins_uart_rx = serial.step(top->externalPins_uart_tx);
    top->externalPins_gpio_in = opt.switches;
    ps2.step(cycle, top->externalPins_ps2_clk, top->externalPins_ps2_data);
    vga.step(top->externalPins_vga_hsync, top->externalPins_vga_vsync, top->externalPins_vga_valid,
             top->externalPins_vga_r, top->externalPins_vga_g, top->externalPins_vga_b);
    if (opt.trace_gpio) {
      uint64_t seg = 0;
      const uint8_t segs[8] = {top->externalPins_gpio_seg_0, top->externalPins_gpio_seg_1,
                               top->externalPins_gpio_seg_2, top->externalPins_gpio_seg_3,
                               top->externalPins_gpio_seg_4, top->externalPins_gpio_seg_5,
                               top->externalPins_gpio_seg_6, top->externalPins_gpio_seg_7};
      for (int i = 0; i < 8; i++) seg |= (uint64_t)segs[i] << (8 * i);
      if (top->externalPins_gpio_out != last_led || seg != last_seg) {
        last_led = top->externalPins_gpio_out;
        last_seg = seg;
        fprintf(stderr, "[gpio] cycle %" PRIu64 " led=%04x seg=%016" PRIx64 "\n", cycle, last_led, seg);
      }
    }
#endif
    top->clock = 0;
    top->eval();
#ifdef TRACE
    if (tfp) tfp->dump(cycle * 2);
#endif
    top->clock = 1;
    top->eval();
#ifdef TRACE
    if (tfp) tfp->dump(cycle * 2 + 1);
#endif
    cycle++;
  };

  top->reset = 1;
  for (int i = 0; i < 20; i++) tick();
  top->reset = 0;
  retired.clear();
  cycle = 0;

  if (opt.difftest) difftest::init(RESET_PC);

  uint32_t gpr[16] = {0};
  uint64_t insts = 0, last_retire = 0;
  int status = -1;  // -1 running, 0 good trap, 1 failure
  std::string reason;

  while (status < 0) {
    if (cycle >= opt.max_cycles) {
      status = 1;
      reason = "cycle limit reached";
      break;
    }
    tick();
    if (Verilated::gotFinish()) {
      status = 1;
      reason = "$finish in RTL";
      break;
    }
    if (retired.empty()) {
      if (cycle - last_retire > WATCHDOG) {
        status = 1;
        reason = "no instruction retired for too long";
      }
      continue;
    }
    last_retire = cycle;
    for (const Retire &r : retired) {
      if (opt.difftest && difftest::pc() != r.pc) {
        fprintf(stderr, "difftest: pc mismatch, dut 0x%08x ref 0x%08x\n", r.pc, difftest::pc());
        status = 1;
        reason = "difftest failure";
        break;
      }
      if (r.ebreak) {
        status = gpr[10] == 0 ? 0 : 1;
        reason = gpr[10] == 0 ? "HIT GOOD TRAP" : "HIT BAD TRAP";
        insts++;
        break;
      }
      if (r.rd_wen) gpr[r.rd] = r.wdata;
      insts++;
      if (!opt.difftest) continue;
      bool device = r.mem_access && !difftest::is_memory(r.mem_addr);
      if (r.skip || (device && !r.trap)) {
        difftest::sync(gpr, r.pc + 4);
        continue;
      }
      difftest::step();
      for (int i = 1; i < 16; i++) {
        if (difftest::gpr(i) != gpr[i]) {
          fprintf(stderr, "difftest: after pc 0x%08x x%d dut 0x%08x ref 0x%08x\n", r.pc, i, gpr[i],
                  difftest::gpr(i));
          status = 1;
          reason = "difftest failure";
        }
      }
      if (status >= 0) break;
    }
    retired.clear();
  }

#ifdef TRACE
  if (tfp) tfp->close();
#endif
  fflush(stdout);
  fprintf(stderr, "\n[sim] %s at cycle %" PRIu64 ", %" PRIu64 " instructions, IPC %.4f\n", reason.c_str(),
          cycle, insts, cycle ? (double)insts / cycle : 0.0);
#ifdef NVBOARD
  nvboard_quit();
#endif
  top->final();
  delete top;
  return status;
}
