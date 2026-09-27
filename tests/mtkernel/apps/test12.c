/* CFU-PG micro T-Kernel regression Test 12: console output. */

#include <tk/tkernel.h>
#include <tm/tmonitor.h>

#define TEST12_PASS                  0x1234567cU
#define EVENT_TASK_A_START           0x12a00001U
#define EVENT_TASK_B_START           0x12b00001U
#define EVENT_TASK_A_WAKE            0x12a00002U
#define EVENT_TASK_B_WAKE            0x12b00002U

#define TASK_STACK_SIZE              1024U
#define TASK_STACK_WORDS             (TASK_STACK_SIZE / sizeof(UW))

__attribute__((section(".test_status"), used))
volatile UW cfu_test12_status;

volatile UW cfu_test12_data = 0x2468ace0U;
volatile UW cfu_test12_bss;
volatile UW cfu_test12_log[4];
volatile UW cfu_test12_log_count;
volatile UW cfu_test12_task_a_done;
volatile UW cfu_test12_task_b_done;
volatile UW cfu_test12_task_a_error;
volatile UW cfu_test12_task_b_error;
volatile W cfu_test12_initial_delay;
volatile W cfu_test12_ref_a;
volatile W cfu_test12_ref_b;
volatile UW cfu_test12_state_a;
volatile UW cfu_test12_state_b;

static UW cfu_test12_task_a_stack[TASK_STACK_WORDS]
	__attribute__((aligned(16)));
static UW cfu_test12_task_b_stack[TASK_STACK_WORDS]
	__attribute__((aligned(16)));

static void test12_fail(UW code)
{
	cfu_test12_status = code;
	for (;;) {
	}
}

static void test12_log(UW event)
{
	UW index = cfu_test12_log_count;

	if (index < 4U) {
		cfu_test12_log[index] = event;
		cfu_test12_log_count = index + 1U;
	} else {
		test12_fail(0xdead0121U);
	}
}

static void test12_task_a(INT stacd, void *exinf)
{
	ER ercd;

	if ((UW)stacd != 0x12aU || (UW)exinf != 0x12a12a12U) {
		cfu_test12_task_a_error = 0xdead0122U;
	}
	test12_log(EVENT_TASK_A_START);
	if (tm_printf((const UB *)"Task A: start value=%x\n", 0xa11aU) <= 0) {
		cfu_test12_task_a_error = 0xdead0123U;
	}

	ercd = tk_dly_tsk(10);
	if (ercd != E_OK) {
		cfu_test12_task_a_error = 0xdead0124U;
	}
	test12_log(EVENT_TASK_A_WAKE);
	if (tm_printf((const UB *)"Task A: wake delay=%d\n", 10) <= 0) {
		cfu_test12_task_a_error = 0xdead0125U;
	}

	cfu_test12_task_a_done = 1U;
	tk_ext_tsk();
	test12_fail(0xdead0126U);
}

static void test12_task_b(INT stacd, void *exinf)
{
	ER ercd;

	if ((UW)stacd != 0x12bU || (UW)exinf != 0x12b12b12U) {
		cfu_test12_task_b_error = 0xdead0127U;
	}
	test12_log(EVENT_TASK_B_START);
	if (tm_printf((const UB *)"Task B: start value=%x\n", 0xb22bU) <= 0) {
		cfu_test12_task_b_error = 0xdead0128U;
	}

	ercd = tk_dly_tsk(20);
	if (ercd != E_OK) {
		cfu_test12_task_b_error = 0xdead0129U;
	}
	test12_log(EVENT_TASK_B_WAKE);
	if (tm_printf((const UB *)"Task B: wake delay=%d\n", 20) <= 0) {
		cfu_test12_task_b_error = 0xdead012aU;
	}

	cfu_test12_task_b_done = 1U;
	tk_ext_tsk();
	test12_fail(0xdead012bU);
}

WEAK_FUNC EXPORT INT usermain(void)
{
	static const UW expected_log[4] = {
		EVENT_TASK_A_START,
		EVENT_TASK_B_START,
		EVENT_TASK_A_WAKE,
		EVENT_TASK_B_WAKE,
	};
	T_CTSK ctsk;
	T_RTSK rtsk;
	ID task_a;
	ID task_b;
	ER ercd;
	UW i;

	if (cfu_test12_data != 0x2468ace0U || cfu_test12_bss != 0U) {
		test12_fail(0xdead012cU);
	}
	if (tm_printf((const UB *)"MTKERNEL_TEST12: usermain\n") <= 0) {
		test12_fail(0xdead012dU);
	}

	ctsk.exinf = (void *)0x12a12a12U;
	ctsk.tskatr = TA_HLNG | TA_USERBUF;
	ctsk.task = (FP)test12_task_a;
	ctsk.itskpri = 2;
	ctsk.stksz = TASK_STACK_SIZE;
	ctsk.bufptr = cfu_test12_task_a_stack;
	task_a = tk_cre_tsk(&ctsk);
	if (task_a <= 0) {
		test12_fail(0xdead012eU);
	}

	ctsk.exinf = (void *)0x12b12b12U;
	ctsk.task = (FP)test12_task_b;
	ctsk.bufptr = cfu_test12_task_b_stack;
	task_b = tk_cre_tsk(&ctsk);
	if (task_b <= 0 || task_b == task_a) {
		test12_fail(0xdead012fU);
	}

	if (tk_sta_tsk(task_a, 0x12a) != E_OK) {
		test12_fail(0xdead0130U);
	}
	if (tk_sta_tsk(task_b, 0x12b) != E_OK) {
		test12_fail(0xdead0131U);
	}

	ercd = tk_dly_tsk(100);
	cfu_test12_initial_delay = ercd;
	if (ercd != E_OK || cfu_test12_task_a_done != 1U ||
	    cfu_test12_task_b_done != 1U || cfu_test12_task_a_error != 0U ||
	    cfu_test12_task_b_error != 0U) {
		test12_fail(cfu_test12_task_a_error != 0U ?
			    cfu_test12_task_a_error :
			    (cfu_test12_task_b_error != 0U ?
			     cfu_test12_task_b_error : 0xdead0132U));
	}

	if (cfu_test12_log_count != 4U) {
		test12_fail(0xdead0133U);
	}
	for (i = 0; i < 4U; ++i) {
		if (cfu_test12_log[i] != expected_log[i]) {
			test12_fail(0xdead0134U);
		}
	}

	cfu_test12_ref_a = tk_ref_tsk(task_a, &rtsk);
	cfu_test12_state_a = cfu_test12_ref_a == E_OK ? rtsk.tskstat : 0U;
	cfu_test12_ref_b = tk_ref_tsk(task_b, &rtsk);
	cfu_test12_state_b = cfu_test12_ref_b == E_OK ? rtsk.tskstat : 0U;
	if (cfu_test12_ref_a != E_OK || cfu_test12_ref_b != E_OK ||
	    cfu_test12_state_a != TTS_DMT || cfu_test12_state_b != TTS_DMT) {
		test12_fail(0xdead0135U);
	}

	if (tm_printf((const UB *)"MTKERNEL_TEST12: PASS events=%d\n", 4) <= 0) {
		test12_fail(0xdead0136U);
	}
	cfu_test12_status = TEST12_PASS;
	for (;;) {
	}
}
