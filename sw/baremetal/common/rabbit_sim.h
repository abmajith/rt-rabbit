/* Register maps of rtl/soc/rabbit_sim_ctrl.sv (simulation-only peripheral)
 * and rtl/soc/rabbit_timer.sv (machine timer), plus small CSR helpers. */
#ifndef RABBIT_SIM_H
#define RABBIT_SIM_H

#define RABBIT_SIM_BASE  0x10000000
#define RABBIT_SIM_PUTC  (RABBIT_SIM_BASE + 0x00)
#define RABBIT_SIM_EXIT  (RABBIT_SIM_BASE + 0x04)
#define RABBIT_SIM_CYCLE (RABBIT_SIM_BASE + 0x08)
#define RABBIT_SIM_IRQ   (RABBIT_SIM_BASE + 0x0C)   /* bit i drives interrupt line i */

#define RABBIT_TIMER_BASE     0x20000000
#define RABBIT_MTIME_LO       (RABBIT_TIMER_BASE + 0x00)
#define RABBIT_MTIME_HI       (RABBIT_TIMER_BASE + 0x04)
#define RABBIT_MTIMECMP_LO    (RABBIT_TIMER_BASE + 0x08)
#define RABBIT_MTIMECMP_HI    (RABBIT_TIMER_BASE + 0x0C)

/* Interrupt lines (bit numbers in mip / mie / mcause) */
#define IRQ_MSI   3
#define IRQ_MTI   7
#define IRQ_MEI   11
#define IRQ_FAST(n) (16 + (n))      /* n = 0..15 */
#define MCAUSE_IRQ 0x80000000u

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

/* ---- interrupts ---------------------------------------------------------- */
#define CSR_READ(name) ({ uint32_t v_; __asm__ volatile("csrr %0, " #name : "=r"(v_)); v_; })
#define CSR_WRITE(name, val) __asm__ volatile("csrw " #name ", %0" :: "r"((uint32_t)(val)) : "memory")
#define CSR_SET(name, val)   __asm__ volatile("csrs " #name ", %0" :: "r"((uint32_t)(val)) : "memory")
#define CSR_CLEAR(name, val) __asm__ volatile("csrc " #name ", %0" :: "r"((uint32_t)(val)) : "memory")

static inline void irq_global_enable(void)  { CSR_SET(mstatus, 1u << 3); }
static inline void irq_global_disable(void) { CSR_CLEAR(mstatus, 1u << 3); }
static inline void wfi(void) { __asm__ volatile("wfi" ::: "memory"); }

/* simulation interrupt lines (rabbit_sim_ctrl IRQ register).
 * The read-back makes sure the write has reached the peripheral. */
static inline void sim_irq_set(uint32_t mask) {
    REG32(RABBIT_SIM_IRQ) = REG32(RABBIT_SIM_IRQ) | mask;
    (void)REG32(RABBIT_SIM_IRQ);
}
static inline void sim_irq_clear(uint32_t mask) {
    REG32(RABBIT_SIM_IRQ) = REG32(RABBIT_SIM_IRQ) & ~mask;
    (void)REG32(RABBIT_SIM_IRQ);
}

/* machine timer: only the low 32 bits are used by the tests (short runs) */
static inline uint32_t mtime_lo(void) { return REG32(RABBIT_MTIME_LO); }
static inline void mtimecmp_set(uint32_t t) {
    REG32(RABBIT_MTIMECMP_LO) = 0xffffffffu;  /* no false match while updating */
    REG32(RABBIT_MTIMECMP_HI) = 0;
    REG32(RABBIT_MTIMECMP_LO) = t;
    (void)REG32(RABBIT_MTIMECMP_LO);
}
static inline void mtimecmp_off(void) {
    REG32(RABBIT_MTIMECMP_HI) = 0xffffffffu;
    REG32(RABBIT_MTIMECMP_LO) = 0xffffffffu;
    (void)REG32(RABBIT_MTIMECMP_LO);
}
#endif
#endif
