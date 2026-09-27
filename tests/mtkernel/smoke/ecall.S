#include <sys/machine.h>
#ifdef CPU_CORE_RISCV

	.section .text
	.balign 4
	.global ecall_test
	.global ecall_test_site
	.global ecall_trap_handler
	.type ecall_test, @function
ecall_test:
	addi	sp, sp, -16
	sw	ra, 12(sp)
	sw	s0, 8(sp)

	/* Direct all synchronous traps to the Test 7 handler. */
	la	t0, ecall_trap_handler
	csrw	mtvec, t0

	/* Verify that trap entry saves an enabled MIE into MPIE. */
	li	t0, 8
	csrs	mstatus, t0

	/* Values used to verify register preservation and wrong-path flushing. */
	li	s0, 0x13579bdf
	li	t0, 0x0badc0de
	li	t1, 0x10203040
	la	t3, trap_after_marker
	li	t4, 1

	.balign 4
ecall_test_site:
	ecall

	/* This store must be squashed at trap entry, then execute once after MRET. */
	sw	t4, 0(t3)

	li	t2, 0x0badc0de
	bne	t0, t2, .Lregister_fail
	li	t2, 0x10203040
	bne	t1, t2, .Lregister_fail
	li	t2, 0x13579bdf
	bne	s0, t2, .Lregister_fail
	csrr	a0, mstatus
	j	.Lecall_test_done

.Lregister_fail:
	li	a0, -1

.Lecall_test_done:
	lw	s0, 8(sp)
	lw	ra, 12(sp)
	addi	sp, sp, 16
	ret
	.size ecall_test, .-ecall_test

	.balign 4
	.type ecall_trap_handler, @function
ecall_trap_handler:
	/* Preserve every general-purpose register used by this test handler. */
	addi	sp, sp, -16
	sw	t0, 0(sp)
	sw	t1, 4(sp)

	/* Record all state before changing MEPC for the return. */
	csrr	t0, mcause
	la	t1, trap_mcause_actual
	sw	t0, 0(t1)

	csrr	t0, mepc
	la	t1, trap_mepc_actual
	sw	t0, 0(t1)

	csrr	t0, mstatus
	la	t1, trap_mstatus_entry
	sw	t0, 0(t1)

	/* A non-zero value here means the younger store was not squashed. */
	la	t0, trap_after_marker
	lw	t0, 0(t0)
	la	t1, trap_after_at_entry
	sw	t0, 0(t1)

	li	t0, 1
	la	t1, trap_seen
	sw	t0, 0(t1)

	/* Skip ECALL itself; otherwise MRET would immediately trap again. */
	csrr	t0, mepc
	addi	t0, t0, 4
	csrw	mepc, t0

	lw	t1, 4(sp)
	lw	t0, 0(sp)
	addi	sp, sp, 16
	mret
	.size ecall_trap_handler, .-ecall_trap_handler

#endif /* CPU_CORE_RISCV */
