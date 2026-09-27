/* CFU-PG micro T-Kernel regression Tests 9 and 10. */

#include <tk/tkernel.h>

__attribute__((section(".test_status"), used))
volatile UW cfu_test9_status = 0;
volatile UW cfu_test9_data = 0x13579bdfU;
volatile UW cfu_test9_bss;

volatile W cfu_test10_cre_result;
volatile W cfu_test10_sta_result;
volatile W cfu_test10_rot_result;
volatile W cfu_test10_ref_result;
volatile UW cfu_test10_task_state;
volatile UW cfu_test10_task_entered;
volatile UW cfu_test10_task_exiting;
volatile UW cfu_test10_task_sp;
volatile UW cfu_test10_stack_low;
volatile UW cfu_test10_stack_high;
volatile UW cfu_test10_stack_result;
volatile UW cfu_test10_task_error;

IMPORT void *knl_lowmem_top, *knl_lowmem_limit;
IMPORT const void *__bss_end;

__attribute__((noinline))
static UW cfu_test10_stack_call(UW a, UW b)
{
	volatile UW local[4];

	local[0] = a;
	local[1] = b;
	local[2] = local[0] + local[1];
	local[3] = local[2] ^ 0xa5a55a5aU;
	return local[3];
}

static void cfu_test10_task(INT stacd, void *exinf)
{
	UW sp;

	__asm__ volatile ("mv %0, sp" : "=r"(sp));
	cfu_test10_task_sp = sp;
	cfu_test10_task_entered = 1;

	if ((UW)stacd != 0x1357U || (UW)exinf != 0x2468ace0U) {
		cfu_test10_task_error = 0xdead00a5U;
	}
	if (sp < cfu_test10_stack_low || sp >= cfu_test10_stack_high ||
	    (sp & 7U) != 0U) {
		cfu_test10_task_error = 0xdead00a6U;
	}

	cfu_test10_stack_result =
		cfu_test10_stack_call(0x12340000U, 0x00005678U);
	if (cfu_test10_stack_result != 0xb7910c22U) {
		cfu_test10_task_error = 0xdead00a7U;
	}

	cfu_test10_task_exiting = 1;
	tk_ext_tsk();

	/* tk_ext_tsk() must never return. */
	cfu_test9_status = 0xdead00a8U;
	for (;;) {
	}
}

WEAK_FUNC EXPORT INT usermain(void)
{
	T_CTSK ctsk;
	T_RTSK rtsk;
	ID tskid;
	ER ercd;

	if (cfu_test9_data != 0x13579bdfU) {
		cfu_test9_status = 0xdead0091U;
		for (;;) {
		}
	}
	if (cfu_test9_bss != 0) {
		cfu_test9_status = 0xdead0092U;
		for (;;) {
		}
	}

	/* knl_init_Imalloc() consumes [__bss_end, knl_lowmem_limit). */
	cfu_test10_stack_low = (UW)&__bss_end;
	cfu_test10_stack_high = (UW)knl_lowmem_limit;
	if ((UW)knl_lowmem_top != (UW)knl_lowmem_limit ||
	    cfu_test10_stack_low >= cfu_test10_stack_high) {
		cfu_test9_status = 0xdead00a0U;
		for (;;) {
		}
	}

	ctsk.exinf = (void *)0x2468ace0U;
	ctsk.tskatr = TA_HLNG;
	ctsk.task = (FP)cfu_test10_task;
	ctsk.itskpri = 1;
	ctsk.stksz = 512;
	ctsk.bufptr = NULL;

	tskid = tk_cre_tsk(&ctsk);
	cfu_test10_cre_result = tskid;
	if (tskid <= 0) {
		cfu_test9_status = 0xdead00a1U;
		for (;;) {
		}
	}

	ercd = tk_sta_tsk(tskid, 0x1357);
	cfu_test10_sta_result = ercd;
	if (ercd != E_OK) {
		cfu_test9_status = 0xdead00a2U;
		for (;;) {
		}
	}

	/* Both tasks are priority 1. Rotate explicitly; no timer wait is used. */
	ercd = tk_rot_rdq(TPRI_RUN);
	cfu_test10_rot_result = ercd;
	if (ercd != E_OK) {
		cfu_test9_status = 0xdead00a3U;
		for (;;) {
		}
	}

	if (cfu_test10_task_entered != 1U ||
	    cfu_test10_task_exiting != 1U) {
		cfu_test9_status = 0xdead00a4U;
		for (;;) {
		}
	}
	if (cfu_test10_task_error != 0U) {
		cfu_test9_status = cfu_test10_task_error;
		for (;;) {
		}
	}

	ercd = tk_ref_tsk(tskid, &rtsk);
	cfu_test10_ref_result = ercd;
	if (ercd != E_OK) {
		cfu_test9_status = 0xdead00a9U;
		for (;;) {
		}
	}
	cfu_test10_task_state = rtsk.tskstat;
	if (rtsk.tskstat != TTS_DMT) {
		cfu_test9_status = 0xdead00aaU;
		for (;;) {
		}
	}

	cfu_test9_status = 0x12345679U;
	for (;;) {
		/* Keep the initial task alive after publishing the result. */
	}
}
