/* Minimal start-up for rabbit SoC (any RV32 core honouring rtl/cores contract).
 *   0x00 : 32-entry vector table (CLINT vectored mode, used by CV32E40P)
 *   0x80 : _start (BOOT_ADDR)
 */
#include "rabbit_sim.h"

    .section .vectors, "ax"
    .option push
    .option norvc               /* every vector slot must be exactly 4 bytes */
    .global __vectors
__vectors:
    .rept 32
    j   trap_entry
    .endr
    .option pop

    .section .text.start, "ax"
    .global _start
_start:
    .option push
    .option norelax
    la  gp, __global_pointer$
    .option pop
    la  sp, __stack_top

    /* zero .bss */
    la  t0, __bss_start
    la  t1, __bss_end
1:  bgeu t0, t1, 2f
    sw  zero, 0(t0)
    addi t0, t0, 4
    j   1b
2:
    call main
    /* main's return value becomes the simulation exit code (0 = PASS) */
    li  t0, RABBIT_SIM_EXIT
    sw  a0, 0(t0)
3:  wfi
    j   3b

/* Default trap handler: any unexpected trap ends the test with code 0xDEAD0000|mcause */
    .weak trap_entry
trap_entry:
    csrr a0, mcause
    andi a0, a0, 0x3ff
    li   t1, 0xDEAD0000
    or   a0, a0, t1
    li   t0, RABBIT_SIM_EXIT
    sw   a0, 0(t0)
4:  j    4b
