/* Register map of rtl/soc/rabbit_sim_ctrl.sv (simulation-only peripheral). */
#ifndef RABBIT_SIM_H
#define RABBIT_SIM_H

#define RABBIT_SIM_BASE  0x10000000
#define RABBIT_SIM_PUTC  (RABBIT_SIM_BASE + 0x00)
#define RABBIT_SIM_EXIT  (RABBIT_SIM_BASE + 0x04)
#define RABBIT_SIM_CYCLE (RABBIT_SIM_BASE + 0x08)

#ifndef __ASSEMBLER__
#include <stdint.h>

#define REG32(a) (*(volatile uint32_t *)(a))

static inline void sim_putc(char c) { REG32(RABBIT_SIM_PUTC) = (uint8_t)c; }

static inline void sim_puts(const char *s) {
    while (*s) sim_putc(*s++);
}

static inline void sim_puthex(uint32_t v) {
    static const char hex[] = "0123456789abcdef";
    sim_puts("0x");
    for (int i = 28; i >= 0; i -= 4) sim_putc(hex[(v >> i) & 0xf]);
}

static inline uint32_t sim_cycles(void) { return REG32(RABBIT_SIM_CYCLE); }

static inline uint32_t csr_misa(void) {
    uint32_t v;
    __asm__ volatile("csrr %0, misa" : "=r"(v));
    return v;
}

static inline uint32_t csr_mcycle(void) {
    uint32_t v;
    __asm__ volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}
#endif
#endif
