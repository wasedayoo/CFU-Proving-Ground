#include <sys/machine.h>
#ifdef CPU_CORE_RISCV

	.section .text
	.balign 4
	.global timer_interrupt_test
	.global timer_trap_handler
	.global timer_wait_start
	.global timer_wait_end
	.type timer_interrupt_test, @function
timer_interrupt_test:
	addi	sp, sp, -16
	sw	ra, 12(sp)
	sw	s0, 8(sp)

	la	t0, timer_trap_handler
	csrw	mtvec, t0

	/* Program mtimecmp 128 timer ticks into the future. */
	li	t0, 0x6000bff8
	lw	t1, 0(t0)
	lw	t2, 4(t0)
	addi	t3, t1, 128
	sltu	t4, t3, t1
	add	t2, t2, t4
	la	t0, timer_compare_low
	sw	t3, 0(t0)

	li	t0, 0x60004000
	li	t5, -1
	sw	t5, 0(t0)
	sw	t2, 4(t0)
	sw	t3, 0(t0)

	/* Both enables are required before the pending request can be accepted. */
	li	t0, 0x80
	csrs	mie, t0
	li	t0, 0x08
	csrs	mstatus, t0

	li	s0, 0
	.balign 4
timer_wait_start:
	addi	s0, s0, 1
	la	t0, timer_trap_seen
	lw	t1, 0(t0)
	beqz	t1, timer_wait_start
timer_wait_end:
	/* Leave interrupts enabled briefly to detect a level that was not cleared. */
	li	t0, 32
.Lpost_interrupt_delay:
	addi	t0, t0, -1
	bnez	t0, .Lpost_interrupt_delay

	csrr	a0, mstatus
	li	t0, 0x08
	csrc	mstatus, t0
	li	t0, 0x80
	csrc	mie, t0

	li	t0, 1
	la	t1, timer_resume_marker
	sw	t0, 0(t1)

	lw	s0, 8(sp)
	lw	ra, 12(sp)
	addi	sp, sp, 16
	ret
	.size timer_interrupt_test, .-timer_interrupt_test

	.balign 4
	.type timer_trap_handler, @function
timer_trap_handler:
	/* This asynchronous handler must preserve every register it modifies. */
	addi	sp, sp, -16
	sw	t0, 0(sp)
	sw	t1, 4(sp)

	csrr	t0, mcause
	la	t1, timer_mcause_actual
	sw	t0, 0(t1)

	csrr	t0, mepc
	la	t1, timer_mepc_actual
	sw	t0, 0(t1)

	csrr	t0, mstatus
	la	t1, timer_mstatus_entry
	sw	t0, 0(t1)

	li	t0, 0x6000bff8
	lw	t0, 0(t0)
	la	t1, timer_mtime_at_trap
	sw	t0, 0(t1)

	/* Move mtimecmp to its maximum value before returning. */
	li	t0, 0x60004000
	li	t1, -1
	sw	t1, 0(t0)
	sw	t1, 4(t0)
	sw	t1, 0(t0)

	la	t0, timer_trap_seen
	lw	t1, 0(t0)
	addi	t1, t1, 1
	sw	t1, 0(t0)

	lw	t1, 4(sp)
	lw	t0, 0(sp)
	addi	sp, sp, 16
	mret
	.size timer_trap_handler, .-timer_trap_handler

#endif /* CPU_CORE_RISCV */
