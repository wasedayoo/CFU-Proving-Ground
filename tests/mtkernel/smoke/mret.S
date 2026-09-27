#include <sys/machine.h>
#ifdef CPU_CORE_RISCV

	.section .text
	.balign 4
	.global mret_test
	.type mret_test, @function
mret_test:
	/* Return through MRET with MPP=M and MPIE=1. */
	la	t0, .Lmret_target
	csrw	mepc, t0
	li	t0, 0x00001880
	csrw	mstatus, t0
	mret

	/* Reaching this path means MRET did not redirect the PC. */
	li	a0, 1
	ret

	.balign 4
.Lmret_target:
	/* Expected after MRET on this M-mode-only core: MIE=1, MPIE=1, MPP=M. */
	csrr	a0, mstatus
	ret
	.size mret_test, .-mret_test

#endif /* CPU_CORE_RISCV */
