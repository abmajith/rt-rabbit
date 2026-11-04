/* rabbit_soc_sim memory map: 64 KiB RAM at 0x0, vectors at 0x0, reset at 0x80 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
  .vectors 0x00000000 : { KEEP(*(.vectors)) } > RAM
  .text    0x00000080 : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
  .rodata  : { *(.rodata .rodata.* .srodata .srodata.*) } > RAM
  .data    : {
    *(.data .data.*)
    __global_pointer$ = . + 0x800;
    *(.sdata .sdata.*)
  } > RAM
  .bss (NOLOAD) : {
    . = ALIGN(4);
    __bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM

  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
