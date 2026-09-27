#include <stdint.h>

/* Method 4: .rodata and .data are preloaded directly into DMEM. */
__attribute__((section(".test_status")))
volatile uint32_t test_status = 0xc001d00d;

volatile const uint32_t rodata_value = 0xa5a55a5a;
volatile uint32_t initialized_data = 0x13579bdf;
volatile uint32_t zero_initialized_data;
volatile uint32_t csr_actual;
volatile uint32_t trap_seen;
volatile uint32_t trap_mcause_actual;
volatile uint32_t trap_mepc_actual;
volatile uint32_t trap_mstatus_entry;
volatile uint32_t trap_after_at_entry;
volatile uint32_t trap_after_marker;
volatile uint32_t timer_trap_seen;
volatile uint32_t timer_mcause_actual;
volatile uint32_t timer_mepc_actual;
volatile uint32_t timer_mstatus_entry;
volatile uint32_t timer_resume_marker;
volatile uint32_t timer_mtime_before;
volatile uint32_t timer_mtime_after;
volatile uint32_t timer_compare_low;
volatile uint32_t timer_mtime_at_trap;

extern uint32_t __bss_start[];
extern uint32_t __bss_end[];
extern uint32_t mret_test(void);
extern uint32_t ecall_test(void);
extern void ecall_test_site(void);
extern uint32_t timer_interrupt_test(void);
extern void timer_trap_handler(void);
extern void timer_wait_start(void);
extern void timer_wait_end(void);

#define MTIME_L        (*(volatile uint32_t *)0x6000bff8u)
#define MTIMECMP_L     (*(volatile uint32_t *)0x60004000u)
#define MTIMECMP_H     (*(volatile uint32_t *)0x60004004u)

static void clear_bss(void)
{
    uint32_t *p;

    for (p = __bss_start; p < __bss_end; p++) {
        *p = 0;
    }
}

__attribute__((noinline))
static uint32_t stack_test(uint32_t high, uint32_t low)
{
    volatile uint32_t local[4];

    local[0] = high;
    local[1] = low;
    local[2] = local[0] + local[1];
    local[3] = local[2];

    return local[3];
}

static inline void write_mstatus(uint32_t value)
{
    __asm__ volatile ("csrw mstatus, %0" : : "r" (value));
}

static inline uint32_t read_mstatus(void)
{
    uint32_t value;

    __asm__ volatile ("csrr %0, mstatus" : "=r" (value));
    return value;
}

static inline void write_mie(uint32_t value)
{
    __asm__ volatile ("csrw mie, %0" : : "r" (value));
}

static inline uint32_t read_mie(void)
{
    uint32_t value;

    __asm__ volatile ("csrr %0, mie" : "=r" (value));
    return value;
}

static inline void write_mtvec(uint32_t value)
{
    __asm__ volatile ("csrw mtvec, %0" : : "r" (value));
}

static inline uint32_t read_mtvec(void)
{
    uint32_t value;

    __asm__ volatile ("csrr %0, mtvec" : "=r" (value));
    return value;
}

static inline void write_mepc(uint32_t value)
{
    __asm__ volatile ("csrw mepc, %0" : : "r" (value));
}

static inline uint32_t read_mepc(void)
{
    uint32_t value;

    __asm__ volatile ("csrr %0, mepc" : "=r" (value));
    return value;
}

static inline void write_mcause(uint32_t value)
{
    __asm__ volatile ("csrw mcause, %0" : : "r" (value));
}

static inline uint32_t read_mcause(void)
{
    uint32_t value;

    __asm__ volatile ("csrr %0, mcause" : "=r" (value));
    return value;
}

static inline void clear_mstatus_bits(uint32_t mask)
{
    __asm__ volatile ("csrc mstatus, %0" : : "r" (mask));
}

static uint32_t csr_test(void)
{
    uint32_t actual;

    write_mstatus(0x00000008);
    actual = read_mstatus();
    if (actual != 0x00000008) {
        csr_actual = actual;
        return 0xdead0004;
    }

    write_mstatus(0x00000000);
    actual = read_mstatus();
    if (actual != 0x00000000) {
        csr_actual = actual;
        return 0xdead0005;
    }

    write_mie(0x00000080);
    actual = read_mie();
    if (actual != 0x00000080) {
        csr_actual = actual;
        return 0xdead0006;
    }

    write_mie(0x00000000);
    actual = read_mie();
    if (actual != 0x00000000) {
        csr_actual = actual;
        return 0xdead0007;
    }

    return 0;
}

static uint32_t startup_csr_test(void)
{
    uint32_t actual;

    actual = read_mstatus();
    if (actual != 0x00000000) {
        csr_actual = actual;
        return 0xdead0008;
    }

    actual = read_mie();
    if (actual != 0x00000000) {
        csr_actual = actual;
        return 0xdead0009;
    }

    return 0;
}

static uint32_t mret_csr_test(void)
{
    uint32_t actual;
    uint32_t handler = (uint32_t)(uintptr_t)&mret_test;

    write_mtvec(handler);
    actual = read_mtvec();
    if (actual != handler) {
        csr_actual = actual;
        return 0xdead000a;
    }

    write_mepc(0x00000100);
    actual = read_mepc();
    if (actual != 0x00000100) {
        csr_actual = actual;
        return 0xdead000b;
    }

    write_mcause(0x0000000b);
    actual = read_mcause();
    if (actual != 0x0000000b) {
        csr_actual = actual;
        return 0xdead000c;
    }

    write_mstatus(0x00000088);
    clear_mstatus_bits(0x00000008);
    actual = read_mstatus();
    if (actual != 0x00000080) {
        csr_actual = actual;
        return 0xdead000d;
    }

    actual = mret_test();
    if (actual != 0x00001888) {
        csr_actual = actual;
        return 0xdead000e;
    }

    write_mstatus(0);
    return 0;
}

static uint32_t ecall_round_trip_test(void)
{
    uint32_t actual;
    uint32_t expected_mepc = (uint32_t)(uintptr_t)&ecall_test_site;

    trap_seen = 0;
    trap_mcause_actual = 0;
    trap_mepc_actual = 0;
    trap_mstatus_entry = 0;
    trap_after_at_entry = 0;
    trap_after_marker = 0;

    /* Prove that ECALL, rather than Test 6, writes the exception cause. */
    write_mcause(0x00000055);
    actual = ecall_test();

    if (trap_seen != 1) {
        csr_actual = trap_seen;
        return 0xdead000f;
    }
    if (trap_mcause_actual != 0x0000000b) {
        csr_actual = trap_mcause_actual;
        return 0xdead0010;
    }
    if (trap_mepc_actual != expected_mepc) {
        csr_actual = trap_mepc_actual;
        return 0xdead0011;
    }
    if (trap_mstatus_entry != 0x00001880) {
        csr_actual = trap_mstatus_entry;
        return 0xdead0012;
    }
    if (trap_after_at_entry != 0) {
        csr_actual = trap_after_at_entry;
        return 0xdead0013;
    }
    if (trap_after_marker != 1) {
        csr_actual = trap_after_marker;
        return 0xdead0014;
    }
    if (actual != 0x00001888) {
        csr_actual = actual;
        return 0xdead0015;
    }

    write_mstatus(0);
    return 0;
}

static void write_mtimecmp(uint32_t high, uint32_t low)
{
    /* RV32-safe sequence: suppress a transient compare match while updating. */
    MTIMECMP_L = 0xffffffffu;
    MTIMECMP_H = high;
    MTIMECMP_L = low;
}

static void wait_until_mtime(uint32_t target)
{
    while ((int32_t)(MTIME_L - target) < 0) {
    }
}

static uint32_t timer_interrupt_round_trip_test(void)
{
    uint32_t actual;
    uint32_t deadline;
    uint32_t interrupt_pc;
    uint32_t wait_start = (uint32_t)(uintptr_t)&timer_wait_start;
    uint32_t wait_end = (uint32_t)(uintptr_t)&timer_wait_end;

    timer_trap_seen = 0;
    timer_mcause_actual = 0;
    timer_mepc_actual = 0;
    timer_mstatus_entry = 0;
    timer_resume_marker = 0;
    timer_compare_low = 0;
    timer_mtime_at_trap = 0;

    write_mstatus(0);
    write_mie(0);
    write_mtvec((uint32_t)(uintptr_t)&timer_trap_handler);

    timer_mtime_before = MTIME_L;
    timer_mtime_after = MTIME_L;
    if (timer_mtime_after <= timer_mtime_before) {
        csr_actual = timer_mtime_after;
        return 0xdead0016;
    }

    /* A pending timer request must be masked while global MIE is clear. */
    deadline = MTIME_L + 32;
    write_mtimecmp(0, deadline);
    wait_until_mtime(deadline + 16);
    if (timer_trap_seen != 0) {
        csr_actual = timer_trap_seen;
        return 0xdead0017;
    }

    /* Global MIE alone must not be sufficient while mie.MTIE remains clear. */
    write_mstatus(0x00000008);
    deadline = MTIME_L + 16;
    wait_until_mtime(deadline);
    if (timer_trap_seen != 0) {
        csr_actual = timer_trap_seen;
        return 0xdead0018;
    }

    /* MTIE alone must not be sufficient while mstatus.MIE remains clear. */
    write_mstatus(0);
    write_mie(0x00000080);
    deadline = MTIME_L + 16;
    wait_until_mtime(deadline);
    if (timer_trap_seen != 0) {
        csr_actual = timer_trap_seen;
        return 0xdead0019;
    }

    write_mie(0);
    write_mtimecmp(0xffffffffu, 0xffffffffu);
    actual = timer_interrupt_test();

    if (timer_trap_seen != 1) {
        csr_actual = timer_trap_seen;
        return 0xdead001a;
    }
    if (timer_mcause_actual != 0x80000007u) {
        csr_actual = timer_mcause_actual;
        return 0xdead001b;
    }
    if ((int32_t)(timer_mtime_at_trap - timer_compare_low) < 0) {
        csr_actual = timer_mtime_at_trap;
        return 0xdead0020;
    }

    interrupt_pc = timer_mepc_actual;
    if ((interrupt_pc < wait_start) || (interrupt_pc >= wait_end) ||
        ((interrupt_pc & 3u) != 0)) {
        csr_actual = interrupt_pc;
        return 0xdead001c;
    }
    if (timer_mstatus_entry != 0x00001880) {
        csr_actual = timer_mstatus_entry;
        return 0xdead001d;
    }
    if (timer_resume_marker != 1) {
        csr_actual = timer_resume_marker;
        return 0xdead001e;
    }
    if (actual != 0x00001888) {
        csr_actual = actual;
        return 0xdead001f;
    }

    write_mstatus(0);
    write_mie(0);
    return 0;
}

void Reset_Handler(void)
{
    uint32_t result;

    /* Make the BSS clear observable instead of relying on BRAM power-up data. */
    zero_initialized_data = 0xffffffff;
    clear_bss();

    result = startup_csr_test();
    if (result == 0) {
        result = csr_test();
    }
    if (result == 0) {
        result = mret_csr_test();
    }
    if (result == 0) {
        result = ecall_round_trip_test();
    }
    if (result == 0) {
        result = timer_interrupt_round_trip_test();
    }

    if (result != 0) {
        /* The failing test has already set a diagnostic result. */
    } else if (rodata_value != 0xa5a55a5a) {
        result = 0xdead0001;
    } else if (initialized_data != 0x13579bdf) {
        result = 0xdead0002;
    } else if (zero_initialized_data != 0) {
        result = 0xdead0003;
    } else {
        result = stack_test(0x12340000, 0x00005678);
    }

    test_status = result;

    while (1) {
    }
}
