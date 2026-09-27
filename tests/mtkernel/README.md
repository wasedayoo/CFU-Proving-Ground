# micro T-Kernel regression tests

This directory owns all CFU-PG-specific micro T-Kernel regression code. The
production RTL, root `Makefile`, and the upstream-style `mtkernel_cfu` sources
must not contain test selection macros, pass/fail signatures, or test-only
applications.

Run the complete regression suite from the repository root with:

```sh
make -C tests/mtkernel check
```

Individual targets are `smoke-run`, `test9-run`, `test11-run`, `test12-run`,
and `test13`. Test 13 builds the FPGA-oriented LED/UART application; its final
behavior is checked on the Arty A7 board.

When adding a feature, add its application or low-level stimulus under this
directory, add the corresponding monitor to `top_test.v`, and add its build and
run targets to this directory's `Makefile`. Keep reusable implementation code
in the normal source tree and keep all test orchestration here.
