ENTRY(_start)

PHDRS {
  ph_text   PT_LOAD FLAGS(0x5);   /* R | X */
  ph_data   PT_LOAD FLAGS(0x6);   /* R | W */
}

MEMORY {
  irom (rx) : ORIGIN = 0x00000000, LENGTH = 64K
  dram (rw) : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS {
  .text : ALIGN(4) {
    *(.text._start)
    *(.text*)
  } > irom :ph_text

  .data : ALIGN(4) {
    *(.rodata*)
    *(.data*)
    *(.sdata*)
  } > dram :ph_data

  .bss : ALIGN(4) {
    *(.sbss*)
    *(.bss*)
  } > dram :ph_data
}
