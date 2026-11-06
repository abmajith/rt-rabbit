/* Interrupt self-test for the rabbit SoC. Runs on every core that honours the
 * rtl/cores contract (cv32e40p is the reference; rabbit3 is checked against it).
 *
 *   1. mip shows the request lines, and only the lines that exist
 *   2. mstatus.MIE = 0 holds an interrupt back; setting it takes the interrupt
 *   3. priority: several lines at once are handled 17 > 16 > 11 > 7
 *   4. a periodic timer "control loop" with WFI between ticks; lateness
 *   5. WFI with interrupts globally off: wakes up, but no handler runs
 *   6. latency from raising a line to the first handler instruction (printed)
 *
 * Returns the number of failed checks (0 = PASS).
 */
#include "rabbit_sim.h"

static int failures;

static void check(const char *name, uint32_t got, uint32_t expected) {
    sim_puts(got == expected ? "  [ok]   " : "  [FAIL] ");
    sim_puts(name);
    sim_puts(" = ");
    sim_puthex(got);
    if (got != expected) {
        sim_puts("  expected ");
        sim_puthex(expected);
        failures++;
    }
    sim_putc('\n');
}

/* ---- what the handler saw -------------------------------------------------- */
static volatile uint32_t n_irq;             /* interrupts handled */
static volatile uint32_t order[8];          /* their line numbers, in order */
static volatile uint32_t entry_cycle;       /* sim cycle counter at handler entry */
static volatile uint32_t tick_period;       /* timer: 0 = one-shot */
static volatile uint32_t tick_deadline;     /* timer: when the current tick was due */
static volatile uint32_t max_late;          /* timer: worst lateness seen (cycles) */

/* The crt0 vector table jumps here for every trap. GCC saves and restores
 * every register the handler uses and returns with MRET. */
void __attribute__((interrupt("machine"))) trap_entry(void) {
    uint32_t now = sim_cycles();
    uint32_t cause = CSR_READ(mcause);

    if (!(cause & MCAUSE_IRQ)) {             /* an exception: stop the test */
        REG32(RABBIT_SIM_EXIT) = 0xDEAD0000u | (cause & 0x3ff);
        for (;;) { }
    }
    uint32_t line = cause & 0x1f;
    if (n_irq < 8) order[n_irq] = line;
    n_irq++;
    entry_cycle = now;

    if (line == IRQ_MTI) {
        uint32_t late = mtime_lo() - tick_deadline;
        if (late > max_late) max_late = late;
        if (tick_period) {
            tick_deadline += tick_period;
            mtimecmp_set(tick_deadline);
        } else {
            mtimecmp_off();
        }
    } else {
        sim_irq_clear(1u << line);           /* the source is level: clear it */
    }
}

static void spin(int n) {
    for (volatile int i = 0; i < n; i++) { }
}

int main(void) {
    sim_puts("\nrt-rabbit: interrupt test\n");
    irq_global_disable();
    CSR_WRITE(mie, 0);

    /* 1. mip reflects the lines; line 0 does not exist ------------------------ */
    sim_irq_set((1u << IRQ_FAST(0)) | (1u << IRQ_MEI) | 1u);
    check("mip (lines 16,11)", CSR_READ(mip), (1u << IRQ_FAST(0)) | (1u << IRQ_MEI));
    sim_irq_clear(0xffffffffu);
    check("mip (none)       ", CSR_READ(mip), 0);

    /* 2. global enable holds back, then lets through ----------------------------- */
    CSR_WRITE(mie, 1u << IRQ_FAST(0));
    sim_irq_set(1u << IRQ_FAST(0));
    spin(20);
    check("held (MIE=0)     ", n_irq, 0);
    irq_global_enable();
    spin(5);
    check("taken (MIE=1)    ", n_irq, 1);
    check("  cause line     ", order[0], IRQ_FAST(0));
    check("  MIE back on    ", (CSR_READ(mstatus) >> 3) & 1, 1);

    /* 3. priority ----------------------------------------------------------------- */
    irq_global_disable();
    n_irq = 0;
    CSR_WRITE(mie, (1u << IRQ_FAST(1)) | (1u << IRQ_FAST(0)) | (1u << IRQ_MEI) | (1u << IRQ_MTI));
    tick_period = 0;
    tick_deadline = 0;
    mtimecmp_set(0);                          /* timer pending at once */
    sim_irq_set((1u << IRQ_FAST(0)) | (1u << IRQ_MEI) | (1u << IRQ_FAST(1)));
    irq_global_enable();
    spin(5);
    check("priority count   ", n_irq, 4);
    check("  1st (fast 1)   ", order[0], IRQ_FAST(1));
    check("  2nd (fast 0)   ", order[1], IRQ_FAST(0));
    check("  3rd (MEI)      ", order[2], IRQ_MEI);
    check("  4th (MTI)      ", order[3], IRQ_MTI);

    /* 4. periodic control loop: wake on the timer, do the work, sleep ------------- */
    irq_global_disable();
    CSR_WRITE(mie, 1u << IRQ_MTI);
    n_irq = 0;
    max_late = 0;
    tick_period = 300;
    tick_deadline = mtime_lo() + 300;
    mtimecmp_set(tick_deadline);
    irq_global_enable();
    uint32_t work = 0;
    while (n_irq < 5) {
        wfi();                                /* sleep until the next tick */
        work++;                               /* "control law" runs here */
    }
    irq_global_disable();
    tick_period = 0;
    mtimecmp_off();
    check("ticks            ", n_irq, 5);
    check("loop ran per tick", work, 5);
    sim_puts("  timer lateness (worst, cycles) = "); sim_puthex(max_late); sim_putc('\n');

    /* 5. WFI wakes with interrupts globally off; no handler ------------------------- */
    n_irq = 0;
    CSR_WRITE(mie, 1u << IRQ_MTI);
    mtimecmp_set(mtime_lo() + 100);
    wfi();
    check("woke, no handler ", n_irq, 0);
    check("  MTI pending    ", (CSR_READ(mip) >> IRQ_MTI) & 1, 1);
    mtimecmp_off();

    /* 6. latency: raise a line, count cycles to the handler's first sim access ------ */
    n_irq = 0;
    CSR_WRITE(mie, 1u << IRQ_FAST(2));
    irq_global_enable();
    uint32_t t0 = sim_cycles();
    REG32(RABBIT_SIM_IRQ) = 1u << IRQ_FAST(2);
    spin(5);
    irq_global_disable();
    check("latency irq taken", n_irq, 1);
    sim_puts("  raise -> handler (incl. register saving) = ");
    sim_puthex(entry_cycle - t0);
    sim_putc('\n');

    sim_puts(failures ? "RESULT: FAIL\n" : "RESULT: PASS\n");
    return failures;
}
