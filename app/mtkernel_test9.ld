OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    imem (rx) : ORIGIN = 0x00000000, LENGTH = 0x00020000
    dmem (rw) : ORIGIN = 0x10000000, LENGTH = 0x00010000
}

SECTIONS
{
    .text : {
        . = ALIGN(4);
        KEEP(*(.text.startup))
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > imem

    .test_status : {
        . = ALIGN(4);
        KEEP(*(.test_status))
        . = ALIGN(4);
    } > dmem

    .rodata : {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(4);
    } > dmem

    .data : {
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);
        __data_start = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > dmem
    __data_org = ADDR(.data);

    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        PROVIDE(__noinit_start = .);
        *(.noinit)
        PROVIDE(__noinit_end = .);
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
        __end = .;
    } > dmem

    _stack_top = ORIGIN(dmem) + LENGTH(dmem);

    ASSERT(SIZEOF(.text) <= LENGTH(imem), "Test 9 IMEM overflow")
    ASSERT(__bss_end <= _stack_top, "Test 9 DMEM overflow")
}
