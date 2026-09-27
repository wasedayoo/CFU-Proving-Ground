# micro T-Kernel regression tests for CFU Proving Ground

ROOT := $(abspath ../..)
MTKERNEL_DIR ?= $(abspath ../../../mtkernel_cfu)
BUILD_DIR := build

GCC := /var/archlab-modules/riscv-gnu-toolchain/2026.03.13/bin/riscv64-unknown-elf-gcc
OBJCOPY := /var/archlab-modules/riscv-gnu-toolchain/2026.03.13/bin/riscv64-unknown-elf-objcopy
OBJDUMP := /var/archlab-modules/riscv-gnu-toolchain/2026.03.13/bin/riscv64-unknown-elf-objdump
RTLSIM := /var/archlab-modules/verilator/5.046/bin/verilator

IMEM_SIZE := $(shell grep -oP "\`define\s+IMEM_SIZE\s+\(\K[^)]*" $(ROOT)/config.vh | bc)
DMEM_SIZE := $(shell grep -oP "\`define\s+DMEM_SIZE\s+\(\K[^)]*" $(ROOT)/config.vh | bc)

RTL_SRCS := $(filter-out $(ROOT)/top.v,$(wildcard $(ROOT)/*.v)) top_test.v
VERILATOR_FLAGS := --binary --trace --top-module top_test -I$(ROOT) \
	--Wno-WIDTHTRUNC --Wno-WIDTHEXPAND

KERNEL_CFLAGS := -Os -std=gnu17 -march=rv32im_zicsr -mabi=ilp32 \
	-ffreestanding -fno-builtin -ffunction-sections -fdata-sections \
	-nostdlib -mno-relax
KERNEL_CPPFLAGS := -D_IOTE_RISCV_ -DCFU_MTKERNEL \
	-I$(MTKERNEL_DIR)/include -I$(MTKERNEL_DIR)/config \
	-I$(MTKERNEL_DIR)/kernel/knlinc -I$(MTKERNEL_DIR)/kernel/sysdepend
KERNEL_LDFLAGS := -Wl,--gc-sections -Wl,--build-id=none -Tld/mtkernel.ld
KERNEL_ASM_SRCS := \
	$(MTKERNEL_DIR)/kernel/sysdepend/cpu/core/riscv/startup.S \
	$(MTKERNEL_DIR)/kernel/sysdepend/cpu/core/riscv/dispatch.S
KERNEL_C_SRCS := \
	$(wildcard $(MTKERNEL_DIR)/kernel/tkernel/*.c) \
	$(wildcard $(MTKERNEL_DIR)/kernel/tstdlib/*.c) \
	$(MTKERNEL_DIR)/kernel/sysinit/sysinit.c \
	$(MTKERNEL_DIR)/kernel/inittask/inittask.c \
	$(wildcard $(MTKERNEL_DIR)/kernel/sysdepend/iote_riscv/*.c) \
	$(MTKERNEL_DIR)/kernel/sysdepend/cpu/core/riscv/cpu_cntl.c \
	$(MTKERNEL_DIR)/kernel/sysdepend/cpu/core/riscv/exc_hdr.c \
	$(MTKERNEL_DIR)/kernel/sysdepend/cpu/core/riscv/interrupt.c \
	$(MTKERNEL_DIR)/lib/libtm/libtm.c \
	$(MTKERNEL_DIR)/lib/libtm/libtm_printf.c \
	$(MTKERNEL_DIR)/lib/libtm/sysdepend/iote_riscv/tm_com.c

.PHONY: check smoke smoke-build smoke-run \
	test9 test9-build test9-run test11 test11-build test11-run \
	test12 test12-build test12-run test13 clean initf

define build_kernel_test
	mkdir -p $(BUILD_DIR)
	$(GCC) $(KERNEL_CFLAGS) $(KERNEL_CPPFLAGS) $(1) \
		$(KERNEL_LDFLAGS) -Wl,-Map,$(BUILD_DIR)/$(3).map \
		-o $(BUILD_DIR)/main.elf $(KERNEL_ASM_SRCS) \
		$(MTKERNEL_DIR)/kernel/sysdepend/cpu/core/riscv/reset_hdl.c \
		$(KERNEL_C_SRCS) $(2) -lc -lgcc
	$(MAKE) initf
endef

smoke:
	mkdir -p $(BUILD_DIR)
	$(GCC) -Os -march=rv32im_zicsr -mabi=ilp32 -ffreestanding \
		-nostdlib -mno-relax -D_IOTE_RISCV_ -I$(MTKERNEL_DIR)/include \
		-Wl,--build-id=none -Wl,-Map,$(BUILD_DIR)/smoke.map \
		-Tld/smoke.ld -o $(BUILD_DIR)/main.elf \
		$(MTKERNEL_DIR)/kernel/sysdepend/cpu/core/riscv/startup.S \
		smoke/reset_handler.c smoke/mret.S smoke/ecall.S smoke/timer_interrupt.S
	$(MAKE) initf

smoke-build: smoke
	CCACHE_DISABLE=1 $(RTLSIM) $(VERILATOR_FLAGS) -DMTKERNEL_SMOKE \
		--Mdir obj_dir_smoke -o top $(RTL_SRCS)

smoke-run: smoke-build
	./obj_dir_smoke/top

test9:
	$(call build_kernel_test,,apps/test9.c,test9)

test9-build: test9
	CCACHE_DISABLE=1 $(RTLSIM) $(VERILATOR_FLAGS) -DMTKERNEL_TEST9 \
		--Mdir obj_dir_test9 -o top $(RTL_SRCS)

test9-run: test9-build
	./obj_dir_test9/top
	awk -f scripts/annotate_retire_trace.awk $(BUILD_DIR)/main.dump \
		$(BUILD_DIR)/mtkernel-test9.trace > $(BUILD_DIR)/mtkernel-test9.trace.asm

test11:
	$(call build_kernel_test,,apps/test11.c,test11)

test11-build: test11
	CCACHE_DISABLE=1 $(RTLSIM) $(VERILATOR_FLAGS) -DMTKERNEL_TEST11 \
		--Mdir obj_dir_test11 -o top $(RTL_SRCS)

test11-run: test11-build
	./obj_dir_test11/top
	awk -f scripts/annotate_retire_trace.awk $(BUILD_DIR)/main.dump \
		$(BUILD_DIR)/mtkernel-test11.trace > $(BUILD_DIR)/mtkernel-test11.trace.asm

test12:
	$(call build_kernel_test,,apps/test12.c,test12)

test12-build: test12
	CCACHE_DISABLE=1 $(RTLSIM) $(VERILATOR_FLAGS) -DMTKERNEL_TEST12 \
		--Mdir obj_dir_test12 -o top $(RTL_SRCS)

test12-run: test12-build
	./obj_dir_test12/top
	awk -f scripts/annotate_retire_trace.awk $(BUILD_DIR)/main.dump \
		$(BUILD_DIR)/mtkernel-test12.trace > $(BUILD_DIR)/mtkernel-test12.trace.asm

# Test 13 is an FPGA-oriented build check; LED behavior is verified on hardware.
test13:
	$(call build_kernel_test,-DCFU_MTKERNEL_FPGA \
		-DCFU_MTKERNEL_TIMER_HZ=100000000UL,\
		$(MTKERNEL_DIR)/kernel/usermain/usermain.c,test13)

check:
	$(MAKE) smoke-run
	$(MAKE) test9-run
	$(MAKE) test11-run
	$(MAKE) test12-run
	$(MAKE) test13

initf:
	$(OBJDUMP) -D $(BUILD_DIR)/main.elf > $(BUILD_DIR)/main.dump
	$(OBJCOPY) -O binary --only-section=.text \
		$(BUILD_DIR)/main.elf $(BUILD_DIR)/memi.bin.tmp
	$(OBJCOPY) -O binary --only-section=.test_status \
		--only-section=.data --only-section=.rodata --only-section=.bss \
		$(BUILD_DIR)/main.elf $(BUILD_DIR)/memd.bin.tmp
	@for suf in i d; do \
		if [ "$$suf" = "i" ]; then \
			mem_size=$(IMEM_SIZE); \
		else \
			mem_size=$(DMEM_SIZE); \
		fi; \
		dd if=$(BUILD_DIR)/mem$$suf.bin.tmp of=$(BUILD_DIR)/mem$$suf.bin \
			conv=sync bs=$$mem_size; \
		rm -f $(BUILD_DIR)/mem$$suf.bin.tmp; \
		hexdump -v -e '1/4 "%08x\n"' $(BUILD_DIR)/mem$$suf.bin \
			> $(BUILD_DIR)/mem$$suf.32.hex; \
		cnt=0; \
		{ \
			echo "initial begin"; \
			while read -r line; do \
				echo "    $${suf}mem[$$cnt] = 32'h$$line;"; \
				cnt=$$((cnt + 1)); \
			done < $(BUILD_DIR)/mem$$suf.32.hex; \
			echo "end"; \
		} > $(BUILD_DIR)/mem$$suf.txt; \
		cp $(BUILD_DIR)/mem$$suf.txt $(ROOT)/mem$$suf.txt; \
	done

clean:
	rm -rf $(BUILD_DIR) obj_dir_smoke obj_dir_test9 obj_dir_test11 obj_dir_test12
