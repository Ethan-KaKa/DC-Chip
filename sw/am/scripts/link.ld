ENTRY(_start)

PHDRS {
  ph_text   PT_LOAD FLAGS(0x5);   /* R | X */
  ph_data   PT_LOAD FLAGS(0x6);   /* R | W */
}

MEMORY {
  irom (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
  dram (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS {
  /* IROM: Executable instructions only (Reset PC = 0x00000000) */
  . = ORIGIN(irom);
  .text : ALIGN(4) {
    _stext = .;
    KEEP(*(.text._start))
    KEEP(*(.text.entry))
    *(.text .text.*)
    _etext = .;
  } > irom :ph_text

  /* DRAM: All read-only and read-write data accessed via LSU */
  . = ORIGIN(dram);
  .rodata : ALIGN(4) {
    _srodata = .;
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    _erodata = .;
  } > dram :ph_data

  .data : ALIGN(4) {
    _sdata = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    _edata = .;
  } > dram :ph_data

  .bss (NOLOAD) : ALIGN(4) {
    _sbss = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    _ebss = .;
  } > dram :ph_data

  /* Heap and Stack layout in DRAM */
  . = ALIGN(16);
  _heap_start = .;
  _stack_size = 4K;
  _stack_top = ORIGIN(dram) + LENGTH(dram);
  _stack_bottom = _stack_top - _stack_size;
  _heap_end = _stack_bottom;

  /* Compatibility symbols */
  PROVIDE(_stack_pointer = _stack_top);
  PROVIDE(__stack_top = _stack_top);

  /* Discard unwanted sections to preserve precise zero entry address */
  /DISCARD/ : {
    *(.note.gnu.build-id)
    *(.comment)
    *(.eh_frame*)
  }
}
