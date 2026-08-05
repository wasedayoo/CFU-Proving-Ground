OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    imem (rx) : ORIGIN = 0x00000000, LENGTH = 0x00008000
    dmem (rw) : ORIGIN = 0x10000000, LENGTH = 0x00004000
}

SECTIONS
{
    .text : {
        . = ALIGN(4);
        KEEP(*(.text.startup))
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > imem

    .data : {
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
    } > dmem

    .bss (NOLOAD) : {
        . = ALIGN(4);
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
    } > dmem

    _stack_top = ORIGIN(dmem) + LENGTH(dmem);
}
