CROSS := riscv64-linux-gnu-
build/char-test.bin: char-test.c
	@mkdir -p build
	$(CROSS)gcc -march=rv32e_zicsr_zifencei -mabi=ilp32e -O2 -nostdlib -ffreestanding -Wl,-Ttext=0x20000000 -Wl,-melf32lriscv -o build/char-test.elf $<
	$(CROSS)objcopy -O binary -j .text build/char-test.elf $@
