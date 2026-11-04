/* First program for the rabbit SoC: identify the core, run a few self-checks,
 * measure a tiny loop in cycles. Returns number of failed checks (0 = PASS). */
#include "rabbit_sim.h"

static int failures;

static void check(const char *name, uint32_t got, uint32_t expected) {
    sim_puts(got == expected ? "  [ok]   " : "  [FAIL] ");
    sim_puts(name);
    sim_puts(" = ");
    sim_puthex(got);
    sim_putc('\n');
    if (got != expected) failures++;
}

/* volatile inputs stop the compiler from folding the checks at compile time */
static volatile uint32_t a = 1234567, b = 89, neg = (uint32_t)-77;

static uint32_t fib(uint32_t n) {
    uint32_t x = 0, y = 1;
    while (n--) { uint32_t t = x + y; x = y; y = t; }
    return x;
}

int main(void) {
    sim_puts("\nrt-rabbit: hello from rabbit_cpu\n");
    sim_puts("  misa  = "); sim_puthex(csr_misa()); sim_putc('\n');

    check("mul    ", a * b, 109876463u);
    check("div    ", a / b, 13871u);
    check("rem    ", a % b, 48u);
    check("divs   ", (uint32_t)((int32_t)neg / 7), (uint32_t)-11);
    check("fib(30)", fib(30), 832040u);

    uint32_t t0 = csr_mcycle();
    volatile uint32_t acc = 0;
    for (int i = 0; i < 100; i++) acc += i;
    uint32_t t1 = csr_mcycle();
    check("sum0_99", acc, 4950u);
    sim_puts("  loop cycles = "); sim_puthex(t1 - t0); sim_putc('\n');

    sim_puts(failures ? "RESULT: FAIL\n" : "RESULT: PASS\n");
    return failures;
}
