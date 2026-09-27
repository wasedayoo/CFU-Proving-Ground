/*
 * CFU-PG micro T-Kernel regression Test 11.
 *
 * Exercise periodic timer interrupts, delayed task wakeups, two task stacks,
 * and preservation of RISC-V callee-saved registers across dispatches.
 */

#include <tk/tkernel.h>

#define TEST11_PASS             0x1234567bU

#define EVENT_TASK_A_START      0xa1100001U
#define EVENT_TASK_B_START      0xb2200001U
#define EVENT_TASK_A_WAKE       0xa1100002U
#define EVENT_TASK_B_WAKE       0xb2200002U
#define EVENT_TASK_A_FINISH     0xa1100003U
#define EVENT_TASK_B_FINISH     0xb2200003U

#define TASK_STACK_SIZE         1024U
#define TASK_STACK_WORDS        (TASK_STACK_SIZE / sizeof(UW))

__attribute__((section(".test_status"), used))
volatile UW cfu_test11_status;

volatile UW cfu_test11_data = 0x13579bdfU;
volatile UW cfu_test11_bss;
volatile UW cfu_test11_log[6];
volatile UW cfu_test11_log_count;
volatile UW cfu_test11_log_overflow;
volatile UW cfu_test11_task_a_done;
volatile UW cfu_test11_task_b_done;
volatile UW cfu_test11_task_a_error;
volatile UW cfu_test11_task_b_error;
volatile UW cfu_test11_task_a_sp;
volatile UW cfu_test11_task_b_sp;
volatile W cfu_test11_task_a_delay1;
volatile W cfu_test11_task_a_delay2;
volatile W cfu_test11_task_b_delay1;
volatile W cfu_test11_task_b_delay2;
volatile W cfu_test11_initial_delay;
volatile W cfu_test11_ref_a;
volatile W cfu_test11_ref_b;
volatile UW cfu_test11_state_a;
volatile UW cfu_test11_state_b;
volatile UW cfu_test11_time_start;
volatile UW cfu_test11_time_end;

static UW cfu_test11_task_a_stack[TASK_STACK_WORDS]
	__attribute__((aligned(16)));
static UW cfu_test11_task_b_stack[TASK_STACK_WORDS]
	__attribute__((aligned(16)));

static void test11_fail(UW code)
{
	cfu_test11_status = code;
	for (;;) {
	}
}

__attribute__((noinline))
static void test11_log(UW event)
{
	UW index = cfu_test11_log_count;

	if (index < (UW)(sizeof(cfu_test11_log) / sizeof(cfu_test11_log[0]))) {
		cfu_test11_log[index] = event;
		cfu_test11_log_count = index + 1U;
	} else {
		cfu_test11_log_overflow = 1U;
	}
}

static UW test11_guard_ok(volatile UW *guard, UW seed)
{
	UW i;

	for (i = 0; i < 8U; ++i) {
		if (guard[i] != (seed ^ (0x01010101U * i))) {
			return 0U;
		}
	}
	return 1U;
}

static void test11_guard_init(volatile UW *guard, UW seed)
{
	UW i;

	for (i = 0; i < 8U; ++i) {
		guard[i] = seed ^ (0x01010101U * i);
	}
}

static void test11_task_a(INT stacd, void *exinf)
{
	volatile UW guard[8];
	register UW saved_s2 asm("s2") = 0xa2a2a2a2U;
	register UW saved_s3 asm("s3") = 0xa3a3a3a3U;
	register UW saved_s4 asm("s4") = 0xa4a4a4a4U;
	register UW saved_s5 asm("s5") = 0xa5a5a5a5U;
	UW sp;
	ER ercd;

	__asm__ volatile ("mv %0, sp" : "=r"(sp));
	cfu_test11_task_a_sp = sp;
	if ((UW)stacd != 0x11aU || (UW)exinf != 0xa11a11a1U ||
	    sp < (UW)cfu_test11_task_a_stack ||
	    sp >= (UW)(cfu_test11_task_a_stack + TASK_STACK_WORDS) ||
	    (sp & 7U) != 0U) {
		cfu_test11_task_a_error = 0xdead00c1U;
	}

	test11_guard_init(guard, 0xa55a0000U);
	__asm__ volatile ("" : "+r"(saved_s2), "+r"(saved_s3),
				       "+r"(saved_s4), "+r"(saved_s5));
	test11_log(EVENT_TASK_A_START);

	ercd = tk_dly_tsk(10);
	cfu_test11_task_a_delay1 = ercd;
	__asm__ volatile ("" : "+r"(saved_s2), "+r"(saved_s3),
				       "+r"(saved_s4), "+r"(saved_s5));
	if (ercd != E_OK || saved_s2 != 0xa2a2a2a2U ||
	    saved_s3 != 0xa3a3a3a3U || saved_s4 != 0xa4a4a4a4U ||
	    saved_s5 != 0xa5a5a5a5U) {
		cfu_test11_task_a_error = 0xdead00c2U;
	}
	if (!test11_guard_ok(guard, 0xa55a0000U)) {
		cfu_test11_task_a_error = 0xdead00c3U;
	}
	test11_log(EVENT_TASK_A_WAKE);

	ercd = tk_dly_tsk(10);
	cfu_test11_task_a_delay2 = ercd;
	__asm__ volatile ("" : "+r"(saved_s2), "+r"(saved_s3),
				       "+r"(saved_s4), "+r"(saved_s5));
	if (ercd != E_OK || saved_s2 != 0xa2a2a2a2U ||
	    saved_s3 != 0xa3a3a3a3U || saved_s4 != 0xa4a4a4a4U ||
	    saved_s5 != 0xa5a5a5a5U) {
		cfu_test11_task_a_error = 0xdead00c4U;
	}
	if (!test11_guard_ok(guard, 0xa55a0000U)) {
		cfu_test11_task_a_error = 0xdead00c5U;
	}
	test11_log(EVENT_TASK_A_FINISH);
	cfu_test11_task_a_done = 1U;
	tk_ext_tsk();
	test11_fail(0xdead00c6U);
}

static void test11_task_b(INT stacd, void *exinf)
{
	volatile UW guard[8];
	register UW saved_s2 asm("s2") = 0xb2b2b2b2U;
	register UW saved_s3 asm("s3") = 0xb3b3b3b3U;
	register UW saved_s4 asm("s4") = 0xb4b4b4b4U;
	register UW saved_s5 asm("s5") = 0xb5b5b5b5U;
	UW sp;
	ER ercd;

	__asm__ volatile ("mv %0, sp" : "=r"(sp));
	cfu_test11_task_b_sp = sp;
	if ((UW)stacd != 0x11bU || (UW)exinf != 0xb22b22b2U ||
	    sp < (UW)cfu_test11_task_b_stack ||
	    sp >= (UW)(cfu_test11_task_b_stack + TASK_STACK_WORDS) ||
	    (sp & 7U) != 0U) {
		cfu_test11_task_b_error = 0xdead00d1U;
	}

	test11_guard_init(guard, 0xb66b0000U);
	__asm__ volatile ("" : "+r"(saved_s2), "+r"(saved_s3),
				       "+r"(saved_s4), "+r"(saved_s5));
	test11_log(EVENT_TASK_B_START);

	ercd = tk_dly_tsk(20);
	cfu_test11_task_b_delay1 = ercd;
	__asm__ volatile ("" : "+r"(saved_s2), "+r"(saved_s3),
				       "+r"(saved_s4), "+r"(saved_s5));
	if (ercd != E_OK || saved_s2 != 0xb2b2b2b2U ||
	    saved_s3 != 0xb3b3b3b3U || saved_s4 != 0xb4b4b4b4U ||
	    saved_s5 != 0xb5b5b5b5U) {
		cfu_test11_task_b_error = 0xdead00d2U;
	}
	if (!test11_guard_ok(guard, 0xb66b0000U)) {
		cfu_test11_task_b_error = 0xdead00d3U;
	}
	test11_log(EVENT_TASK_B_WAKE);

	ercd = tk_dly_tsk(10);
	cfu_test11_task_b_delay2 = ercd;
	__asm__ volatile ("" : "+r"(saved_s2), "+r"(saved_s3),
				       "+r"(saved_s4), "+r"(saved_s5));
	if (ercd != E_OK || saved_s2 != 0xb2b2b2b2U ||
	    saved_s3 != 0xb3b3b3b3U || saved_s4 != 0xb4b4b4b4U ||
	    saved_s5 != 0xb5b5b5b5U) {
		cfu_test11_task_b_error = 0xdead00d4U;
	}
	if (!test11_guard_ok(guard, 0xb66b0000U)) {
		cfu_test11_task_b_error = 0xdead00d5U;
	}
	test11_log(EVENT_TASK_B_FINISH);
	cfu_test11_task_b_done = 1U;
	tk_ext_tsk();
	test11_fail(0xdead00d6U);
}

WEAK_FUNC EXPORT INT usermain(void)
{
	static const UW expected_log[6] = {
		EVENT_TASK_A_START,
		EVENT_TASK_B_START,
		EVENT_TASK_A_WAKE,
		EVENT_TASK_B_WAKE,
		EVENT_TASK_A_FINISH,
		EVENT_TASK_B_FINISH,
	};
	T_CTSK ctsk;
	T_RTSK rtsk;
	SYSTIM time;
	ID task_a;
	ID task_b;
	ER ercd;
	UW i;

	if (cfu_test11_data != 0x13579bdfU) {
		test11_fail(0xdead00b1U);
	}
	if (cfu_test11_bss != 0U) {
		test11_fail(0xdead00b2U);
	}

	ctsk.exinf = (void *)0xa11a11a1U;
	ctsk.tskatr = TA_HLNG | TA_USERBUF;
	ctsk.task = (FP)test11_task_a;
	ctsk.itskpri = 2;
	ctsk.stksz = TASK_STACK_SIZE;
	ctsk.bufptr = cfu_test11_task_a_stack;
	task_a = tk_cre_tsk(&ctsk);
	if (task_a <= 0) {
		test11_fail(0xdead00b3U);
	}

	ctsk.exinf = (void *)0xb22b22b2U;
	ctsk.task = (FP)test11_task_b;
	ctsk.bufptr = cfu_test11_task_b_stack;
	task_b = tk_cre_tsk(&ctsk);
	if (task_b <= 0 || task_b == task_a) {
		test11_fail(0xdead00b4U);
	}

	ercd = tk_sta_tsk(task_a, 0x11a);
	if (ercd != E_OK) {
		test11_fail(0xdead00b5U);
	}
	ercd = tk_sta_tsk(task_b, 0x11b);
	if (ercd != E_OK) {
		test11_fail(0xdead00b6U);
	}

	ercd = tk_get_otm(&time);
	if (ercd != E_OK) {
		test11_fail(0xdead00b7U);
	}
	cfu_test11_time_start = time.lo;

	/* Block the priority-1 initial task while the priority-2 tasks run. */
	ercd = tk_dly_tsk(100);
	cfu_test11_initial_delay = ercd;
	if (ercd != E_OK) {
		test11_fail(0xdead00b8U);
	}

	ercd = tk_get_otm(&time);
	if (ercd != E_OK) {
		test11_fail(0xdead00b9U);
	}
	cfu_test11_time_end = time.lo;
	if ((UW)(cfu_test11_time_end - cfu_test11_time_start) < 100U) {
		test11_fail(0xdead00baU);
	}

	if (cfu_test11_task_a_done != 1U || cfu_test11_task_b_done != 1U ||
	    cfu_test11_task_a_error != 0U || cfu_test11_task_b_error != 0U) {
		test11_fail(cfu_test11_task_a_error != 0U ?
			    cfu_test11_task_a_error :
			    (cfu_test11_task_b_error != 0U ?
			     cfu_test11_task_b_error : 0xdead00bbU));
	}
	if (cfu_test11_log_overflow != 0U || cfu_test11_log_count != 6U) {
		test11_fail(0xdead00bcU);
	}
	for (i = 0; i < 6U; ++i) {
		if (cfu_test11_log[i] != expected_log[i]) {
			test11_fail(0xdead00bdU);
		}
	}

	if ((UW)(cfu_test11_task_a_stack + TASK_STACK_WORDS) >
	    (UW)cfu_test11_task_b_stack &&
	    (UW)(cfu_test11_task_b_stack + TASK_STACK_WORDS) >
	    (UW)cfu_test11_task_a_stack) {
		test11_fail(0xdead00beU);
	}
	if (cfu_test11_task_a_sp == cfu_test11_task_b_sp) {
		test11_fail(0xdead00bfU);
	}

	cfu_test11_ref_a = tk_ref_tsk(task_a, &rtsk);
	cfu_test11_state_a = cfu_test11_ref_a == E_OK ? rtsk.tskstat : 0U;
	cfu_test11_ref_b = tk_ref_tsk(task_b, &rtsk);
	cfu_test11_state_b = cfu_test11_ref_b == E_OK ? rtsk.tskstat : 0U;
	if (cfu_test11_ref_a != E_OK || cfu_test11_ref_b != E_OK ||
	    cfu_test11_state_a != TTS_DMT || cfu_test11_state_b != TTS_DMT) {
		test11_fail(0xdead00c0U);
	}

	cfu_test11_status = TEST11_PASS;
	for (;;) {
	}
}
