#define UART_BASE 0x10000000L
#define UART_TX   0
void _start() {
  *(volatile char *)(UART_BASE + UART_TX) = 'A';
  *(volatile char *)(UART_BASE + UART_TX) = '\n';
  asm volatile("li a0, 0; ebreak");
  while (1);
}
