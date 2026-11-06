/* M-extension self-test for the rabbit SoC (runs on every core; CV32E40P is
 * the reference).
 *
 *   1. corner cases of all eight instructions (x/0, -2^31/-1, signs, ...)
 *   2. pseudo-random operands, checked against a software model that uses
 *      only shifts and adds (no MUL/DIV instructions)
 *   3. timing: cycles per MUL / DIV, and that they do not depend on the
 *      operands (rabbit cores only: CV32E40P's divider is data-dependent)
 *   4. an interrupt in the middle of a divide is taken at once, and the
 *      divide still gives the right result afterwards
 *
 * Returns the number of failed checks (0 = PASS).
 */
#include "rabbit_sim.h"

static int failures;

static void fail(const char *what, uint32_t a, uint32_t b, uint32_t got, uint32_t exp) {
    if (failures < 10) {
        sim_puts("  [FAIL] "); sim_puts(what);
        sim_puts(" a="); sim_puthex(a); sim_puts(" b="); sim_puthex(b);
        sim_puts(" got="); sim_puthex(got); sim_puts(" expected="); sim_puthex(exp);
        sim_putc('\n');
    }
    failures++;
}

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

/* ---- the eight instructions, exactly as written (no compiler tricks) ---- */
#define OP(name) \
    static inline uint32_t op_##name(uint32_t a, uint32_t b) { \
        uint32_t r; __asm__ volatile(#name " %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
OP(mul) OP(mulh) OP(mulhsu) OP(mulhu) OP(div) OP(divu) OP(rem) OP(remu)

/* ---- software model: shifts and adds only -------------------------------- */
static uint64_t umul64(uint32_t a, uint32_t b) {
    uint64_t acc = 0, x = a;
    while (b) {
        if (b & 1u) acc += x;
        x <<= 1;
        b >>= 1;
    }
    return acc;
}
static uint32_t neg(uint32_t x) { return ~x + 1u; }
static uint32_t abs32(uint32_t x) { return (x >> 31) ? neg(x) : x; }

/* high word of a*b with a and/or b read as signed: fix up the unsigned one */
static uint32_t model_mulh(uint32_t a, uint32_t b, int a_signed, int b_signed) {
    uint32_t hi = (uint32_t)(umul64(a, b) >> 32);
    if (a_signed && (a >> 31)) hi -= b;
    if (b_signed && (b >> 31)) hi -= a;
    return hi;
}

static void udivmod(uint32_t a, uint32_t b, uint32_t *q, uint32_t *r) {
    if (b == 0) { *q = 0xffffffffu; *r = a; return; }
    uint32_t quo = 0, rem = 0;
    for (int i = 31; i >= 0; i--) {
        rem = (rem << 1) | ((a >> i) & 1u);
        if (rem >= b) { rem -= b; quo |= 1u << i; }
    }
    *q = quo; *r = rem;
}

static uint32_t model(int op, uint32_t a, uint32_t b) {
    uint32_t q, r;
    switch (op) {
    case 0: return (uint32_t)umul64(a, b);
    case 1: return model_mulh(a, b, 1, 1);
    case 2: return model_mulh(a, b, 1, 0);
    case 3: return model_mulh(a, b, 0, 0);
    case 4: case 6:                                   /* DIV, REM */
        if (b == 0) return op == 4 ? 0xffffffffu : a;
        if (a == 0x80000000u && b == 0xffffffffu) return op == 4 ? a : 0;
        udivmod(abs32(a), abs32(b), &q, &r);
        if (op == 4) return ((a ^ b) >> 31) ? neg(q) : q;
        return (a >> 31) ? neg(r) : r;
    case 5: udivmod(a, b, &q, &r); return q;
    default: udivmod(a, b, &q, &r); return r;
    }
}

static uint32_t hw(int op, uint32_t a, uint32_t b) {
    switch (op) {
    case 0: return op_mul(a, b);
    case 1: return op_mulh(a, b);
    case 2: return op_mulhsu(a, b);
    case 3: return op_mulhu(a, b);
    case 4: return op_div(a, b);
    case 5: return op_divu(a, b);
    case 6: return op_rem(a, b);
    default: return op_remu(a, b);
    }
}

static const char *const names[8] = {"mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"};

/* ---- timing: cycles from one mcycle read to the next, around one instruction */
#define TIMED(insn) \
    static uint32_t time_##insn(uint32_t a, uint32_t b) { \
        uint32_t t0, t1, r; \
        __asm__ volatile("csrr %0, mcycle\n\t" #insn " %2, %3, %4\n\tcsrr %1, mcycle" \
                         : "=&r"(t0), "=&r"(t1), "=&r"(r) : "r"(a), "r"(b)); \
        (void)r; return t1 - t0; }
TIMED(add) TIMED(mul) TIMED(mulhu) TIMED(div) TIMED(remu)

/* ---- interrupt during a divide ---------------------------------------------- */
static volatile uint32_t n_irq, entry_cycle;

void __attribute__((interrupt("machine"))) trap_entry(void) {
    uint32_t now = sim_cycles();
    uint32_t cause = CSR_READ(mcause);
    if (!(cause & MCAUSE_IRQ)) {                  /* an exception: stop the test */
        REG32(RABBIT_SIM_EXIT) = 0xDEAD0000u | (cause & 0x3ff);
        for (;;) { }
    }
    entry_cycle = now;
    n_irq++;
    sim_irq_clear(1u << (cause & 0x1f));
}

static uint32_t xs = 0x2545F491u;                /* xorshift32 */
static uint32_t rnd(void) { xs ^= xs << 13; xs ^= xs >> 17; xs ^= xs << 5; return xs; }

int main(void) {
    sim_puts("\nrt-rabbit: M extension test\n");
    irq_global_disable();
    CSR_WRITE(mie, 0);

    /* 1. corner cases --------------------------------------------------------- */
    static const uint32_t v[] = {0, 1, 7, 0x7fffffffu, 0x80000000u, 0x80000001u,
                                 0xfffffffeu, 0xffffffffu, 0x0000ffffu, 0xdeadbeefu};
    const int nv = sizeof v / sizeof v[0];
    int before = failures;
    for (int op = 0; op < 8; op++)
        for (int i = 0; i < nv; i++)
            for (int j = 0; j < nv; j++) {
                uint32_t got = hw(op, v[i], v[j]), exp = model(op, v[i], v[j]);
                if (got != exp) fail(names[op], v[i], v[j], got, exp);
            }
    check("corner cases (8 ops x 10 x 10) failures", failures - before, 0);
    check("  div  -2^31 / -1", op_div(0x80000000u, 0xffffffffu), 0x80000000u);
    check("  rem  -2^31 % -1", op_rem(0x80000000u, 0xffffffffu), 0);
    check("  div  -7 / 0    ", op_div(neg(7), 0), 0xffffffffu);
    check("  rem  -7 % 0    ", op_rem(neg(7), 0), neg(7));
    check("  divu 7 / 0     ", op_divu(7, 0), 0xffffffffu);
    check("  mulhsu -1 * max", op_mulhsu(0xffffffffu, 0xffffffffu), 0xffffffffu);

    /* 2. random operands ------------------------------------------------------- */
    before = failures;
    for (int n = 0; n < 48; n++) {
        uint32_t a = rnd(), b = rnd();
        if (n & 1) b >>= (rnd() & 31);            /* small divisors too */
        for (int op = 0; op < 8; op++) {
            uint32_t got = hw(op, a, b), exp = model(op, a, b);
            if (got != exp) fail(names[op], a, b, got, exp);
        }
    }
    check("random (48 x 8 ops) failures          ", failures - before, 0);

    /* 3. timing ------------------------------------------------------------------ */
    uint32_t base = time_add(1, 2);
    uint32_t t_mul = time_mul(3, 5) - base, t_div = time_div(100, 7) - base;
    sim_puts("  extra cycles: mul = "); sim_puthex(t_mul);
    sim_puts("  mulhu = ");             sim_puthex(time_mulhu(0xffffffffu, 0xffffffffu) - base);
    sim_puts("  div = ");               sim_puthex(t_div);
    sim_putc('\n');
    int rabbit = !(CSR_READ(misa) & (1u << 2)); /* CV32E40P has C; its divider is data-dependent */
    if (rabbit) {
        static const uint32_t da[] = {0, 1, 0x80000000u, 0xffffffffu, 12345};
        static const uint32_t db[] = {0, 1, 0xffffffffu, 0x80000000u, 3};
        uint32_t same_div = 1, same_mul = 1;
        for (int i = 0; i < 5; i++)
            for (int j = 0; j < 5; j++) {
                same_div &= (time_div(da[i], db[j]) - base == t_div);
                same_div &= (time_remu(da[i], db[j]) - base == t_div);
                same_mul &= (time_mul(da[i], db[j]) - base == t_mul);
                same_mul &= (time_mulhu(da[i], db[j]) - base == t_mul);
            }
        check("mul time independent of data          ", same_mul, 1);
        check("div time independent of data          ", same_div, 1);
    }

    /* 4. interrupt in the middle of a divide ------------------------------------ */
    n_irq = 0;
    CSR_WRITE(mie, 1u << IRQ_FAST(0));
    irq_global_enable();
    uint32_t a = 1000000007u, b = 97u, q;
    uint32_t t0 = sim_cycles();
    __asm__ volatile(
        "sw   %[m], 0(%[irq])\n\t"      /* raise line 16 ... */
        "divu %[q], %[a], %[b]\n\t"     /* ... while this divide runs */
        : [q] "=&r"(q)
        : [m] "r"(1u << IRQ_FAST(0)), [irq] "r"(RABBIT_SIM_IRQ), [a] "r"(a), [b] "r"(b)
        : "memory");
    irq_global_disable();
    check("irq taken during divide               ", n_irq, 1);
    check("  divide result after MRET            ", q, 10309278u);
    sim_puts("  raise -> handler (cycles) = "); sim_puthex(entry_cycle - t0); sim_putc('\n');

    sim_puts(failures ? "RESULT: FAIL\n" : "RESULT: PASS\n");
    return failures;
}
