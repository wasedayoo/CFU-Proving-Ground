/* Simple micro T-Kernel task demonstration for the CFU-PG Arty A7. */

#include <tk/tkernel.h>
#include <tm/tmonitor.h>

#define CFU_LED_TOGGLE     (*(volatile UW *)0x80000008U)
#define TASK_STACK_SIZE    1024U
#define TASK_STACK_WORDS   (TASK_STACK_SIZE / sizeof(UW))

static void task1_main(INT stacd, void *exinf)
{
	for (;;) {
		CFU_LED_TOGGLE = 0x01U;
		(void)tk_dly_tsk(1000U);
	}
}

static void task2_main(INT stacd, void *exinf)
{
	for (;;) {
		CFU_LED_TOGGLE = 0x02U;
		(void)tk_dly_tsk(2000U);
	}
}

static void task3_main(INT stacd, void *exinf)
{
	for (;;) {
		CFU_LED_TOGGLE = 0x04U;
		(void)tk_dly_tsk(3000U);
	}
}

WEAK_FUNC EXPORT INT usermain(void)
{
	T_CTSK ctsk1 = {
		.task = (FP)task1_main,
		.itskpri = 10,
		.stksz = TASK_STACK_SIZE,
	};
	ID task1_id = tk_cre_tsk(&ctsk1);
	tk_sta_tsk(task1_id, 0);

	T_CTSK ctsk2 = {
		.task = (FP)task2_main,
		.itskpri = 10,
		.stksz = TASK_STACK_SIZE,
	};
	ID task2_id = tk_cre_tsk(&ctsk2);
	tk_sta_tsk(task2_id, 0);

	T_CTSK ctsk3 = {
		.task = (FP)task3_main,
		.itskpri = 10,
		.stksz = TASK_STACK_SIZE,
	};
	ID task3_id = tk_cre_tsk(&ctsk3);
	tk_sta_tsk(task3_id, 0);

	tk_slp_tsk(TMO_FEVR);
	return 0;
}
