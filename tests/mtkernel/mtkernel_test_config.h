#ifndef MTKERNEL_TEST_CONFIG_H
#define MTKERNEL_TEST_CONFIG_H

/* Start with the unmodified micro T-Kernel configuration. */
#include "../../../mtkernel_cfu/config/config.h"

/* Keep CFU-PG regression tests independent of unsupported subsystems. */
#undef USE_SHUTDOWN
#define USE_SHUTDOWN		(0)

#undef USE_DBGSPT
#define USE_DBGSPT		(0)

#undef USE_SYSTEM_MESSAGE
#define USE_SYSTEM_MESSAGE	(0)

#undef USE_EXCEPTION_DBG_MSG
#define USE_EXCEPTION_DBG_MSG	(0)

#undef USE_PTMR
#define USE_PTMR		(0)

#undef USE_DEVICE
#define USE_DEVICE		(0)

#endif /* MTKERNEL_TEST_CONFIG_H */
