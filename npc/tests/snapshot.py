#!/usr/bin/env python3
"""Exercise reported architectural state through the public debugger interface."""

import argparse
from pathlib import Path
import re
import struct
import subprocess
import tempfile

BASE = 0x80000000
NAMES = "$0 ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6".split()


def addi(rd, rs, imm):
    return ((imm & 0xfff) << 20) | (rs << 15) | (rd << 7) | 0x13


def csr(rd, address, rs, op):
    return (address << 20) | (rs << 15) | (op << 12) | (rd << 7) | 0x73


def run(model, directory, name, words, retired, expected, calls=()):
    image = directory / (name + ".bin")
    image.write_bytes(struct.pack("<" + "I" * len(words), *words))
    # Inspect reset state and the state just before EBREAK. No internal RTL access.
    commands = f"info\nsi {retired - 1}\ninfo\nc\nq\n"
    result = subprocess.run([str(model), str(image)], input=commands, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    assert result.returncode == 0, result.stdout
    values = re.findall(r"^(\$0|\w+): ([0-9a-f]{8})$", result.stdout, re.MULTILINE)
    assert len(values) == 64, result.stdout
    initial = dict(values[:32])
    final = dict(values[32:])
    assert all(int(initial[name], 16) == 0 for name in NAMES), initial
    for index, value in expected.items():
        assert int(final[NAMES[index]], 16) == value, (name, index, final)
    assert all(int(final[NAMES[i]], 16) == 0 for i in range(16, 32)), final
    assert "good-trap" in result.stdout, result.stdout
    assert re.search(rf"insts={retired}\b", result.stdout), result.stdout
    for target in calls:
        assert f"call [???@0x{target:x}]" in result.stdout, result.stdout
    print(f"{name}: passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    parser.add_argument("--ftrace", action="store_true")
    args = parser.parse_args()
    model = args.model.resolve()
    with tempfile.TemporaryDirectory(prefix="npc-snapshot-") as tmp:
        directory = Path(tmp)
        run(model, directory, "writeback", [addi(1, 0, 7), addi(0, 0, 9),
            addi(2, 1, -1), addi(10, 0, 0), 0x00100073], 5,
            {0: 0, 1: 7, 2: 6, 10: 0})
        run(model, directory, "csr_writeback", [addi(1, 0, 0x40),
            csr(1, 0x305, 1, 1), addi(2, 0, 4), csr(3, 0x305, 2, 2),
            csr(4, 0x305, 2, 3), csr(5, 0x305, 0, 2),
            csr(6, 0x300, 0, 2), addi(15, 0, 15), addi(10, 0, 0), 0x00100073],
            10, {1: 0, 2: 4, 3: 0x40, 4: 0x44, 5: 0x40, 6: 0x1800, 15: 15})
        # JALR overwrites the same register that supplies its target.
        run(model, directory, "jalr_overlap", [0x800000b7, addi(1, 1, 16),
            0x000080e7, 0x00000000, addi(10, 0, 0), 0x00100073], 5,
            {1: BASE + 12, 10: 0}, [BASE + 16] if args.ftrace else [])
        # ECALL updates two CSRs at once. The handler advances MEPC then returns.
        words = [0x800000b7, addi(1, 1, 40), csr(2, 0x305, 1, 1),
                 csr(3, 0x305, 0, 2), csr(4, 0x305, 0, 3), 0x00000073,
                 csr(5, 0x341, 0, 2), csr(6, 0x342, 0, 2),
                 addi(10, 0, 0), 0x00100073,
                 csr(7, 0x341, 0, 2), addi(7, 7, 4), csr(0, 0x341, 7, 1),
                 0x30200073]
        run(model, directory, "csr_trap", words, 14,
            {0: 0, 1: BASE + 40, 2: 0, 3: BASE + 40, 4: BASE + 40,
             5: BASE + 24, 6: 11, 7: BASE + 24, 10: 0})


if __name__ == "__main__":
    main()
