diff --git a/Makefile b/Makefile
index b753b03..9153685 100644
--- a/Makefile
+++ b/Makefile
@@ -1,10 +1,21 @@
 # CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo
 # Released under the MIT license https://opensource.org/licenses/mit
 
+
+
+IS_RV64 := $(shell grep -E "^\`define\s+RV64" config.vh | wc -l)
+
+ifeq ($(strip $(IS_RV64)),1)
+GCC     := /home/archlab/yfutatsugi/RV32to64/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc
+GPP     := /home/archlab/yfutatsugi/RV32to64/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-g++
+OBJCOPY := /home/archlab/yfutatsugi/RV32to64/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objcopy
+OBJDUMP := /home/archlab/yfutatsugi/RV32to64/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objdump
+else
 GCC     := /var/archlab-modules/riscv-gnu-toolchain/2026.03.13/bin/riscv64-unknown-elf-gcc
 GPP     := /var/archlab-modules/riscv-gnu-toolchain/2026.03.13/bin/riscv64-unknown-elf-g++
 OBJCOPY := /var/archlab-modules/riscv-gnu-toolchain/2026.03.13/bin/riscv64-unknown-elf-objcopy
 OBJDUMP := /var/archlab-modules/riscv-gnu-toolchain/2026.03.13/bin/riscv64-unknown-elf-objdump
+endif
 VIVADO  := /var/archlab-modules/amd/2025.2/Vivado/bin/vivado
 VPP     := /var/archlab-modules/amd/2025.2/Vitis/bin/v++
 RTLSIM  := /var/archlab-modules/verilator/5.046/bin/verilator
@@ -29,13 +40,62 @@ build:
 	$(RTLSIM) --binary --trace --top-module top --Wno-WIDTHTRUNC --Wno-WIDTHEXPAND -o top *.v
 	gcc -O2 dispemu/dispemu.c -o build/dispemu -lcairo -lX11
 
+imem_size =	$(shell grep -oP "\`define\s+IMEM_SIZE\s+\(\K[^)]*" config.vh | bc)
+dmem_size =	$(shell grep -oP "\`define\s+DMEM_SIZE\s+\(\K[^)]*" config.vh | bc)
+
+
+
+
+ifeq ($(strip $(IS_RV64)),1)
+# =========================================================================
+# 64-bit version
+# =========================================================================
+prog:
+	mkdir -p buildS
+	$(GCC) -Os -march=rv64im -mabi=lp64 -mcmodel=medany -nostartfiles -Iapp -Tapp/link.ld -o build/main.elf app/crt0.s app/*.c *.c
+	make initf
+
+initf:
+	$(OBJDUMP) -D build/main.elf > build/main.dump
+	$(OBJCOPY) -O binary --only-section=.text build/main.elf build/memi.bin.tmp; \
+	$(OBJCOPY) -O binary --only-section=.data \
+						 --only-section=.rodata \
+						 --only-section=.bss \
+						 build/main.elf build/memd.bin.tmp; \
+	for suf in i d; do \
+		if [ "$$suf" = "i" ]; then \
+			mem_size=$(imem_size); \
+			hex_fmt='1/4 "%08x\n"'; \
+			v_prefix="32'h"; \
+		else \
+			mem_size=$(dmem_size); \
+			hex_fmt='1/8 "%016x\n"'; \
+			v_prefix="64'h"; \
+		fi; \
+		dd if=build/mem$$suf.bin.tmp of=build/mem$$suf.bin conv=sync bs=$$mem_size; \
+		rm -f build/mem$$suf.bin.tmp; \
+		hexdump -v -e "$$hex_fmt" build/mem$$suf.bin > build/mem$$suf.hex; \
+		tmp_IFS=$$IFS; IFS= ; \
+		cnt=0; \
+		{ \
+			echo "initial begin"; \
+			while read -r line; do \
+				echo "    $${suf}mem[$$cnt] = $${v_prefix}$$line;"; \
+				cnt=$$((cnt + 1)); \
+			done < build/mem$$suf.hex; \
+			echo "end"; \
+		} > mem$$suf.txt; \
+		IFS=$$tmp_IFS; \
+	done
+else
+# =========================================================================
+# 32-bit version
+# =========================================================================
 prog:
 	mkdir -p build
 	$(GCC) -Os -march=rv32im -mabi=ilp32 -nostartfiles -Iapp -Tapp/link.ld -o build/main.elf app/crt0.s app/*.c *.c
 	make initf
 
-imem_size =	$(shell grep -oP "\`define\s+IMEM_SIZE\s+\(\K[^)]*" config.vh | bc)
-dmem_size =	$(shell grep -oP "\`define\s+DMEM_SIZE\s+\(\K[^)]*" config.vh | bc)
 initf:
 	$(OBJDUMP) -D build/main.elf > build/main.dump
 	$(OBJCOPY) -O binary --only-section=.text build/main.elf build/memi.bin.tmp; \
@@ -64,6 +124,7 @@ initf:
 		} > mem$$suf.txt; \
 		IFS=$$tmp_IFS; \
 	done
+endif
 
 run:
 	./obj_dir/top
diff --git a/app/crt0.s b/app/crt0.s
index 9754827..a6b362e 100644
--- a/app/crt0.s
+++ b/app/crt0.s
@@ -46,7 +46,7 @@ _start:
     .text
     .globl finish
 finish:
-    la      t0, _tohost
+    li      t0, 0x80000000
     li      t1, CMD_FINISH
     sw      t1, 0(t0)
 1:  j       1b
diff --git a/app/perf.c b/app/perf.c
index 0779c76..ab590ba 100644
--- a/app/perf.c
+++ b/app/perf.c
@@ -2,19 +2,19 @@
 / Released under the MIT license https://opensource.org/licenses/mit           */
 
 unsigned long long pg_perf_cycle(void) {
-    unsigned int cycle =  *(volatile unsigned int *)0x40000004;
-    unsigned int cycleh = *(volatile unsigned int *)0x40000008;
+    unsigned int cycle =  *(volatile unsigned int *)0x40000004UL;
+    unsigned int cycleh = *(volatile unsigned int *)0x40000008UL;
     return ((unsigned long long)cycleh << 32) | cycle;
 }
 
 void pg_perf_reset(void) {
-    *(volatile char *)0x40000000 = 0;
+    *(volatile char *)0x40000000UL = 0;
 }
 
 void pg_perf_enable(void) {
-    *(volatile char *)0x40000000 = 1;
+    *(volatile char *)0x40000000UL = 1;
 }
 
 void pg_perf_disable(void) {
-    *(volatile char *)0x40000000 = 2;
-}
+    *(volatile char *)0x40000000UL = 2;
+}
\ No newline at end of file
diff --git a/app/st7789.c b/app/st7789.c
index 90553be..02ae273 100644
--- a/app/st7789.c
+++ b/app/st7789.c
@@ -157,7 +157,7 @@ char font8x8_basic[128][8] = {
 };
 
 void pg_lcd_draw_point(int x, int y, char color) {
-    *(volatile char *)(0x20000000 + y * 256 + x) = color;
+    *(volatile char *)(0x20000000UL + y * 256 + x) = color;
 }
 
 void pg_lcd_draw_char(int x, int y, char c, char color, int scale) {
@@ -251,4 +251,4 @@ void pg_lcd_prints(const char *str) {
 void pg_lcd_set_pos(int x, int y) {
     st7789_col = x;
     st7789_row = y;
-}
+}
\ No newline at end of file
diff --git a/app/util.c b/app/util.c
index 02095f3..edf98ca 100644
--- a/app/util.c
+++ b/app/util.c
@@ -2,11 +2,11 @@
 / Released under the MIT license https://opensource.org/licenses/mit           */
 
 void pg_exit() {
-    *(int *)0x80000000 = 0x00020000;
+    *(int *)0x80000000UL = 0x00020000;
 }
 
 void pg_printc(char c) {
-    *(char *)0x80000000 = c;
+    *(char *)0x80000000UL = c;
 }
 
 void pg_printd(long long x) {
@@ -29,7 +29,7 @@ void pg_printd(long long x) {
     }
 }
 
-void pg_printh(int x) {
+void pg_printh(unsigned long x) {
     char buf[16];
     int i = 0;
     while (x) {
@@ -46,4 +46,4 @@ void pg_prints(const char *str) {
         pg_printc(*str);
         str++;
     }
-}
+}
\ No newline at end of file
diff --git a/app/util.h b/app/util.h
index 2907e8e..5a8a4d9 100644
--- a/app/util.h
+++ b/app/util.h
@@ -4,5 +4,5 @@
 void pg_exit();
 void pg_printc(char c);
 void pg_printd(long long x);
-void pg_printh(int x);
+void pg_printh(unsigned long x);
 void pg_prints(const char *str);
diff --git a/cfu.v b/cfu.v
index 70f0236..3989b79 100644
--- a/cfu.v
+++ b/cfu.v
@@ -10,10 +10,10 @@ module cfu (
     input  wire        en_i,
     input  wire [ 2:0] funct3_i,
     input  wire [ 6:0] funct7_i,
-    input  wire [31:0] src1_i,
-    input  wire [31:0] src2_i,
+    input  wire [`XLEN-1:0] src1_i,
+    input  wire [`XLEN-1:0] src2_i,
     output wire        stall_o,
-    output wire [31:0] rslt_o
+    output wire [`XLEN-1:0] rslt_o
 );
     assign stall_o = 0;
     assign rslt_o  = (en_i) ? src1_i | src2_i : 0;
@@ -26,10 +26,10 @@ module cfu (
     input  wire        en_i,
     input  wire [ 2:0] funct3_i,
     input  wire [ 6:0] funct7_i,
-    input  wire [31:0] src1_i,
-    input  wire [31:0] src2_i,
+    input  wire [`XLEN-1:0] src1_i,
+    input  wire [`XLEN-1:0] src2_i,
     output wire        stall_o,
-    output wire [31:0] rslt_o
+    output wire [`XLEN-1:0] rslt_o
 );
 
     reg cfu_en = 0; always @(posedge clk_i) cfu_en <= (ap_ready) ? 0 : ap_start;
@@ -37,7 +37,7 @@ module cfu (
     wire ap_done;
     wire ap_idle;
     wire ap_ready;
-    wire [31:0] rslt;
+    wire [`XLEN-1:0] rslt;
     cfu_hls cfu_hls (
         .ap_clk         (clk_i          ),
         .ap_start       (ap_start       ),
diff --git a/config.vh b/config.vh
index 2e2c20c..fb47b35 100644
--- a/config.vh
+++ b/config.vh
@@ -11,7 +11,7 @@
 `define LCD_ROTATE 0 // 0: 0 degree, 1: 90 degree, 2: 180 degree, 3: 270 degree (Left Rotate)
 
 // cpu
-`define CLK_FREQ_MHZ 160  // operating clock frequency in MHz
+`define CLK_FREQ_MHZ 130  // operating clock frequency in MHz
 
 `define RESET_VECTOR 'h00000000
 
@@ -22,7 +22,7 @@
 `define DMEM_SIZE (16*1024) // data memory size in byte
 
 `define IMEM_ENTRIES (`IMEM_SIZE/4)
-`define DMEM_ENTRIES (`DMEM_SIZE/4)
+`define DMEM_ENTRIES (`DMEM_SIZE/`XBYTES)
 
 `define IMEM_ADDRW ($clog2(`IMEM_ENTRIES))
 `define DMEM_ADDRW ($clog2(`DMEM_ENTRIES))
@@ -40,8 +40,17 @@
 `define TOHOST_ADDR 'h40008000 // do not modify, this is hard coded in the interconnect
 
 // cpu
+`define RV64
+
+`ifdef RV64
+`define XLEN 64
+`define XBYTES (`XLEN/8)
+`define XLEN_LOG2 6
+`else
 `define XLEN 32
 `define XBYTES (`XLEN/8)
+`define XLEN_LOG2 5
+`endif
 
 `define NOP 32'h00000013 // addi  x0, x0, 0
 `define UNIMP 32'hC0001073 // csrrw x0, cycle, x0
@@ -79,7 +88,12 @@
 `define ALU_CTRL_IS_XOR_OR 6
 `define ALU_CTRL_IS_OR_AND 7
 `define ALU_CTRL_IS_SRC2 8
+`define ALU_CTRL_IS_W 9
+`ifdef RV64
+`define ALU_CTRL_WIDTH 10
+`else
 `define ALU_CTRL_WIDTH 9
+`endif
 
 // bru control
 `define BRU_CTRL_IS_CTRL_TSFR 0
@@ -99,7 +113,12 @@
 `define LSU_CTRL_IS_BYTE 3
 `define LSU_CTRL_IS_HALFWORD 4
 `define LSU_CTRL_IS_WORD 5
+`ifdef RV64
+`define LSU_CTRL_IS_DOUBLEWORD 6
+`define LSU_CTRL_WIDTH 7
+`else
 `define LSU_CTRL_WIDTH 6
+`endif
 
 // perf control
 `define PERF_CTRL_IS_CYCLE 0
@@ -113,13 +132,23 @@
 `define MUL_CTRL_IS_SRC1_SIGNED 1
 `define MUL_CTRL_IS_SRC2_SIGNED 2
 `define MUL_CTRL_IS_HIGH 3
+`ifdef RV64
+`define MUL_CTRL_IS_W 4
+`define MUL_CTRL_WIDTH 5
+`else
 `define MUL_CTRL_WIDTH 4
+`endif
 
 // div control
 `define DIV_CTRL_IS_DIV 0
 `define DIV_CTRL_IS_SIGNED 1
 `define DIV_CTRL_IS_REM 2
+`ifdef RV64
+`define DIV_CTRL_IS_W 3
+`define DIV_CTRL_WIDTH 4
+`else
 `define DIV_CTRL_WIDTH 3
+`endif
 
 // cfu control
 `define CFU_CTRL_IS_CFU 0
diff --git a/main.v b/main.v
index ff297f1..7dbdb63 100644
--- a/main.v
+++ b/main.v
@@ -38,7 +38,11 @@ module main (
 
     reg rdata_sel = 0;
     always @(posedge clk) rdata_sel <= dbus_addr[30];
+`ifdef RV64
+    assign dbus_rdata = (rdata_sel) ? {2{perf_rdata}} : dmem_rdata;
+`else
     assign dbus_rdata = (rdata_sel) ? perf_rdata : dmem_rdata;
+`endif
 
     cpu cpu (
         .clk_i         (clk),         // input  wire
@@ -59,12 +63,12 @@ module main (
         .rdata_o (imem_rdata)   // output reg  [DATA_WIDTH-1:0]
     );
 
-    wire [31:0] dmem_addr  = dbus_addr;
-    wire [31:0] dmem_wdata = dbus_wdata;
-    wire  [3:0] dmem_wstrb = dbus_wstrb;
+    wire [`XLEN-1:0] dmem_addr  = dbus_addr;
+    wire [`XLEN-1:0] dmem_wdata = dbus_wdata;
+    wire  [`XBYTES-1:0] dmem_wstrb = dbus_wstrb;
     wire        dmem_re    = !dbus_we & (dbus_addr[28]);
     wire        dmem_we    =  dbus_we & (dbus_addr[28]);
-    wire [31:0] dmem_rdata;
+    wire [`XLEN-1:0] dmem_rdata;
     m_dmem dmem (
         .clk_i   (clk),         // input  wire
         .we_i    (dmem_we),     // input  wire
@@ -75,6 +79,7 @@ module main (
         .rdata_o (dmem_rdata)   // output reg  [DATA_WIDTH-1:0]
     );
 
+    always @(posedge clk) if (dbus_we) $display("WE: addr=%x data=%x", dbus_addr, dbus_wdata);
     wire        vmem_we    = dbus_we & (dbus_addr[29]);
     wire [15:0] vmem_addr  = dbus_addr[15:0];
     wire  [2:0] vmem_wdata = dbus_wdata[2:0];
@@ -116,7 +121,7 @@ endmodule
 
 module m_imem (
     input  wire        clk_i,
-    input  wire [31:0] raddr_i,
+    input  wire [`XLEN-1:0] raddr_i,
     output wire [31:0] rdata_o
 );
 
@@ -136,24 +141,31 @@ module m_dmem (
     input  wire        clk_i,
     input  wire        re_i,
     input  wire        we_i,
-    input  wire [31:0] addr_i,
-    input  wire [31:0] wdata_i,
-    input  wire  [3:0] wstrb_i,
-    output wire [31:0] rdata_o
+    input  wire [`XLEN-1:0] addr_i,
+    input  wire [`XLEN-1:0] wdata_i,
+    input  wire  [`XBYTES-1:0] wstrb_i,
+    output wire [`XLEN-1:0] rdata_o
 );
 
-    (* ram_style = "block" *) reg [31:0] dmem[0:`DMEM_ENTRIES-1];
+    (* ram_style = "block" *) reg [`XLEN-1:0] dmem[0:`DMEM_ENTRIES-1];
     `include "memd.txt"
 
-    wire [`DMEM_ADDRW-1:0] valid_addr = addr_i[`DMEM_ADDRW+1:2];
+    localparam BYTE_OFFSET = $clog2(`XBYTES);
+    wire [`DMEM_ADDRW-1:0] valid_addr = addr_i[`DMEM_ADDRW+(BYTE_OFFSET-1):BYTE_OFFSET];
 
-    reg [31:0] rdata = 0;
+    reg [`XLEN-1:0] rdata = 0;
     always @(posedge clk_i) begin
         if (we_i) begin
             if (wstrb_i[0]) dmem[valid_addr][7:0]   <= wdata_i[7:0];
             if (wstrb_i[1]) dmem[valid_addr][15:8]  <= wdata_i[15:8];
             if (wstrb_i[2]) dmem[valid_addr][23:16] <= wdata_i[23:16];
             if (wstrb_i[3]) dmem[valid_addr][31:24] <= wdata_i[31:24];
+`ifdef RV64
+            if (wstrb_i[4]) dmem[valid_addr][39:32] <= wdata_i[39:32];
+            if (wstrb_i[5]) dmem[valid_addr][47:40] <= wdata_i[47:40];
+            if (wstrb_i[6]) dmem[valid_addr][55:48] <= wdata_i[55:48];
+            if (wstrb_i[7]) dmem[valid_addr][63:56] <= wdata_i[63:56];
+`endif
         end
         if (re_i) rdata <= dmem[valid_addr];
     end
diff --git a/proc.v b/proc.v
index 82d5da7..18aaf96 100644
--- a/proc.v
+++ b/proc.v
@@ -59,7 +59,7 @@ module cpu (
     reg [          `XLEN-1:0] IdEx_imm;
     reg                       IdEx_rf_we;
     reg [                4:0] IdEx_rd;
-    reg [               31:0] IdEx_j_pc4;
+    reg [          `XLEN-1:0] IdEx_j_pc4;
 
     // MA: Memory Access
     reg                       ExMa_v;
@@ -76,7 +76,7 @@ module cpu (
     reg                       ExMa_rf_we;
     reg [                4:0] ExMa_rd;
     reg [          `XLEN-1:0] ExMa_rslt;
-    reg [               31:0] ExMa_mdc_rslt;  // mul_div_cfu_rslt
+    reg [          `XLEN-1:0] ExMa_mdc_rslt;  // mul_div_cfu_rslt
     reg                       ExMa_j_b_insn;  // jump or branch insn
     reg                       ExMa_mul_stall;
     reg                       ExMa_div_stall;
@@ -100,7 +100,7 @@ module cpu (
     wire        Ma_br_misp     = (rst) ? 1 :
                                  (ExMa_v && ExMa_is_ctrl_tsfr &&
                                  ((Ma_br_tkn) ? ExMa_br_misp_rslt1 : ExMa_br_misp_rslt2));
-    wire [31:0] Ma_br_true_pc  = (rst) ?`RESET_VECTOR :
+    wire [`XLEN-1:0] Ma_br_true_pc  = (rst) ?`RESET_VECTOR :
                                  (ExMa_br_tkn) ? ExMa_br_tkn_pc : ExMa_pc+4;
 
     wire If_v = (Ma_br_misp) ? 0 : (IfId_load_muldiv_use) ? IfId_v : 1;
@@ -117,7 +117,7 @@ module cpu (
     wire If_pc_stall;
     wire [1:0] If_pat_hist;
     wire If_br_pred_tkn;
-    wire [31:0] If_br_pred_pc;
+    wire [`XLEN-1:0] If_br_pred_pc;
     wire [`ITYPE_W-1:0] If_instr_type;
     wire If_rf_we;
     wire [4:0] If_rd;
@@ -239,7 +239,7 @@ module cpu (
     wire Id_rs1_fwd_Wb_to_Ex = ExMa_v && ExMa_rf_we && (ExMa_rd == IfId_rs1);
     wire Id_rs2_fwd_Wb_to_Ex = ExMa_v && ExMa_rf_we && (ExMa_rd == IfId_rs2);
 
-    wire [31:0] Id_pc_in = (Id_src2_ctrl[`SRC2_CTRL_USE_AUIPC]) ? IfId_pc : 0;
+    wire [`XLEN-1:0] Id_pc_in = (Id_src2_ctrl[`SRC2_CTRL_USE_AUIPC]) ? IfId_pc : 0;
     wire Id_use_imm = Id_src2_ctrl[`SRC2_CTRL_USE_AUIPC] | Id_src2_ctrl[`SRC2_CTRL_USE_IMM];
 
     // source select
@@ -247,7 +247,7 @@ module cpu (
     wire [`XLEN-1:0] Id_src2 = (Id_rs2_fwd_Wb_to_Ex) ? Ma_rslt :
                                (Id_use_imm) ? Id_pc_in+Id_imm  : Id_xrs2 ;
 
-    wire [31:0] Id_j_pc4 = (Id_bru_ctrl[`BRU_CTRL_IS_JAL_JALR]) ? IfId_pc + 4 : 0;
+    wire [`XLEN-1:0] Id_j_pc4 = (Id_bru_ctrl[`BRU_CTRL_IS_JAL_JALR]) ? IfId_pc + 4 : 0;
 
     always @(posedge clk_i) if (!w_stall) begin
         if (rst) begin
@@ -373,10 +373,10 @@ module cpu (
         .en_i    (Ex_cfu_en),            // input  wire
         .funct3_i(IdEx_cfu_ctrl[3:1]),   // input  wire [ 2:0]
         .funct7_i(IdEx_cfu_ctrl[10:4]),  // input  wire [ 6:0]
-        .src1_i  (Ex_src1),              // input  wire [31:0]
-        .src2_i  (Ex_src2),              // input  wire [31:0]
+        .src1_i  (Ex_src1),              // input  wire [`XLEN-1:0]
+        .src2_i  (Ex_src2),              // input  wire [`XLEN-1:0]
         .stall_o (Ex_cfu_stall),         // output wire
-        .rslt_o  (Ex_cfu_rslt)           // output wire [31:0]
+        .rslt_o  (Ex_cfu_rslt)           // output wire [`XLEN-1:0]
     );
 
     always @(posedge clk_i) if (!w_stall) begin
@@ -442,7 +442,7 @@ module cpu (
 endmodule
 
 `define BTB_IDXW $clog2(`BTB_ENTRY)  // BTB index width
-`define BTB_OSTW $clog2(`XBYTES)     // BTB offset width
+`define BTB_OSTW $clog2(`IBUS_DATA_WIDTH/8)  // BTB offset width
 /******************************************************************************************/
 module bimodal (
     input  wire             clk_i,
@@ -499,7 +499,13 @@ module pre_decoder (
         (opcode == 5'b00000) ? `I_TYPE :  // LOAD
         (opcode == 5'b01000) ? `S_TYPE :  // STORE
         (opcode == 5'b00100) ? `I_TYPE :  // OP-IMM
+`ifdef RV64
+        (opcode == 5'b00110) ? `I_TYPE :  // OP-IMM-32
+`endif
         (opcode == 5'b01100) ? `R_TYPE :  // OP
+`ifdef RV64
+        (opcode == 5'b01110) ? `R_TYPE :  // OP-32
+`endif
         (opcode == 5'b00010) ? `R_TYPE : `NONE_TYPE;  // CUSTOM-0 : NONE
 
     assign rd_o = ((instr_type_o == `S_TYPE) | (instr_type_o == `B_TYPE)) ? 0 : ir_i[11:7];
@@ -514,14 +520,14 @@ module regfile (  ///// register file with bypassing
     input  wire        clk_i,
     input  wire [ 4:0] rs1_i,
     input  wire [ 4:0] rs2_i,
-    output wire [31:0] xrs1_o,
-    output wire [31:0] xrs2_o,
+    output wire [`XLEN-1:0] xrs1_o,
+    output wire [`XLEN-1:0] xrs2_o,
     input  wire        we_i,
     input  wire [ 4:0] rd_i,
-    input  wire [31:0] wdata_i
+    input  wire [`XLEN-1:0] wdata_i
 );
 
-    reg [31:0] ram[0:31];
+    reg [`XLEN-1:0] ram[0:31];
 
     assign xrs1_o = (rs1_i == 0) ? 0 : (we_i && rs1_i == rd_i) ? wdata_i : ram[rs1_i];
     assign xrs2_o = (rs2_i == 0) ? 0 : (we_i && rs2_i == rd_i) ? wdata_i : ram[rs2_i];
@@ -535,57 +541,83 @@ endmodule
 /******************************************************************************************/
 module alu (
     input  wire [`ALU_CTRL_WIDTH-1:0] alu_ctrl_i,
-    input  wire                [31:0] src1_i    ,
-    input  wire                [31:0] src2_i    ,
-    input  wire                [31:0] j_pc4_i   ,
-    output wire                [31:0] rslt_o
+    input  wire           [`XLEN-1:0] src1_i    ,
+    input  wire           [`XLEN-1:0] src2_i    ,
+    input  wire           [`XLEN-1:0] j_pc4_i   ,
+    output wire           [`XLEN-1:0] rslt_o
 );
 
     wire w_signed = alu_ctrl_i[`ALU_CTRL_IS_SIGNED];
     wire w_neg    = alu_ctrl_i[`ALU_CTRL_IS_NEG];
     wire w_less   = alu_ctrl_i[`ALU_CTRL_IS_LESS];
-
-    wire [33:0] adder_src1   = {w_signed && src1_i[31], src1_i, 1'b1};
-    wire [33:0] adder_src2   = {w_signed && src2_i[31], src2_i, 1'b0} ^ {34{w_neg}};
-    wire [33:0] adder_rslt_t = adder_src1+adder_src2;
-    wire        less_rslt    = w_less && adder_rslt_t[33];
-    wire [31:0] adder_rslt   = (alu_ctrl_i[`ALU_CTRL_IS_ADD]) ? adder_rslt_t[32:1] : 0;
-
-    wire signed  [32:0] right_shifter_src1 = {w_signed && src1_i[31], src1_i};
-    wire  [4:0] shamt              = src2_i[4:0];
-    wire [31:0] left_shifter_rslt  = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_LEFT] ) ?
+`ifdef RV64
+    wire w_is_w   = alu_ctrl_i[`ALU_CTRL_IS_W];
+`endif
+
+    wire [`XLEN+1:0] adder_src1   = {w_signed && src1_i[`XLEN-1], src1_i, 1'b1};
+    wire [`XLEN+1:0] adder_src2   = {w_signed && src2_i[`XLEN-1], src2_i, 1'b0} ^ {(`XLEN+2){w_neg}};
+    wire [`XLEN+1:0] adder_rslt_t = adder_src1+adder_src2;
+    wire        less_rslt    = w_less && adder_rslt_t[`XLEN+1];
+    wire [`XLEN-1:0] adder_rslt   = (alu_ctrl_i[`ALU_CTRL_IS_ADD]) ? adder_rslt_t[`XLEN:1] : 0;
+
+`ifdef RV64
+    wire [31:0] src1_32 = src1_i[31:0];
+    wire [ 4:0] shamt_32 = src2_i[4:0];
+    wire [31:0] left_shift_32 = src1_32 << shamt_32;
+    wire signed [32:0] right_shifter_src1_32 = {w_signed && src1_32[31], src1_32};
+    wire [32:0] arith_shift_32_tmp = right_shifter_src1_32 >>> shamt_32;
+    wire [31:0] right_shift_32 = arith_shift_32_tmp[31:0];
+`endif
+
+    wire signed  [`XLEN:0] right_shifter_src1 = {w_signed && src1_i[`XLEN-1], src1_i};
+    wire  [$clog2(`XLEN)-1:0] shamt              = src2_i[$clog2(`XLEN)-1:0];
+`ifdef RV64
+    wire [`XLEN:0] arith_shift_64_tmp = right_shifter_src1 >>> shamt;
+    wire [`XLEN-1:0] left_shifter_rslt  = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_LEFT] ) ?
+                                     (w_is_w ? {32'b0, left_shift_32} : src1_i << shamt) : 0;
+    wire [`XLEN-1:0] right_shifter_rslt = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_RIGHT]) ?
+                                     (w_is_w ? {32'b0, right_shift_32} : arith_shift_64_tmp[`XLEN-1:0]) : 0;
+`else
+    wire [`XLEN-1:0] left_shifter_rslt  = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_LEFT] ) ?
                                      src1_i <<  shamt : 0;
-    wire [31:0] right_shifter_rslt = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_RIGHT]) ?
+    wire [`XLEN-1:0] right_shifter_rslt = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_RIGHT]) ?
                                      right_shifter_src1 >>> shamt : 0;
+`endif
 
-    wire [31:0] bitwise_rslt       = ((alu_ctrl_i[`ALU_CTRL_IS_XOR_OR]) ?
+    wire [`XLEN-1:0] bitwise_rslt       = ((alu_ctrl_i[`ALU_CTRL_IS_XOR_OR]) ?
                                      (src1_i ^ src2_i) : 0) |
                                      ((alu_ctrl_i[`ALU_CTRL_IS_OR_AND])
                                       ? (src1_i & src2_i) : 0);
-    wire [31:0] lui_auipc_rslt     = (alu_ctrl_i[`ALU_CTRL_IS_SRC2]) ? src2_i : 0;
+    wire [`XLEN-1:0] lui_auipc_rslt     = (alu_ctrl_i[`ALU_CTRL_IS_SRC2]) ? src2_i : 0;
 
-    assign rslt_o = less_rslt | adder_rslt | left_shifter_rslt | right_shifter_rslt |
-                    bitwise_rslt | lui_auipc_rslt | j_pc4_i;
+    wire [`XLEN-1:0] rslt_t = less_rslt | adder_rslt | left_shifter_rslt | right_shifter_rslt |
+                              bitwise_rslt | lui_auipc_rslt | j_pc4_i;
+
+`ifdef RV64
+    assign rslt_o = w_is_w ? {{32{rslt_t[31]}}, rslt_t[31:0]} : rslt_t;
+`else
+    assign rslt_o = rslt_t;
+`endif
 endmodule
 
 /******************************************************************************************/
 module bru (
     input  wire [`BRU_CTRL_WIDTH-1:0] bru_ctrl_i,
-    input  wire [               31:0] src1_i,
-    input  wire [               31:0] src2_i,
-    input  wire [               31:0] pc_i,
-    input  wire [               31:0] imm_i,
-    input  wire [               31:0] npc_i,
+    input  wire [          `XLEN-1:0] src1_i,
+    input  wire [          `XLEN-1:0] src2_i,
+    input  wire [          `XLEN-1:0] pc_i,
+    input  wire [          `XLEN-1:0] imm_i,
+    input  wire [          `XLEN-1:0] npc_i,
     input  wire                       br_pred_tkn_i,
     output wire                       is_ctrl_tsfr_o,
     output wire                       br_tkn_o,
     output wire                       br_misp_rslt1_o,
     output wire                       br_misp_rslt2_o,
-    output wire [               31:0] br_tkn_pc_o
+    output wire [          `XLEN-1:0] br_tkn_pc_o
 );
 
-    wire signed [32:0] sext_src1 = {bru_ctrl_i[`BRU_CTRL_IS_SIGNED] && src1_i[31], src1_i};
-    wire signed [32:0] sext_src2 = {bru_ctrl_i[`BRU_CTRL_IS_SIGNED] && src2_i[31], src2_i};
+    wire signed [`XLEN:0] sext_src1 = {bru_ctrl_i[`BRU_CTRL_IS_SIGNED] && src1_i[`XLEN-1], src1_i};
+    wire signed [`XLEN:0] sext_src2 = {bru_ctrl_i[`BRU_CTRL_IS_SIGNED] && src2_i[`XLEN-1], src2_i};
 
     wire               w_eq = (src1_i == src2_i);  // equal
     wire               w_lt = (sext_src1 < sext_src2);  // less than
@@ -596,9 +628,9 @@ module bru (
                      (bru_ctrl_i[`BRU_CTRL_IS_BLT] &  w_lt) |
                      (bru_ctrl_i[`BRU_CTRL_IS_BGE] & !w_lt);
 
-    wire [31:0] br_tkn_pc_t;
+    wire [`XLEN-1:0] br_tkn_pc_t;
     assign br_tkn_pc_t     = ((bru_ctrl_i[`BRU_CTRL_IS_JALR]) ? src1_i : pc_i) + imm_i;
-    assign br_tkn_pc_o     = {br_tkn_pc_t[31:1], 1'b0};
+    assign br_tkn_pc_o     = {br_tkn_pc_t[`XLEN-1:1], 1'b0};
 
     assign is_ctrl_tsfr_o  = (bru_ctrl_i[`BRU_CTRL_IS_CTRL_TSFR] || br_pred_tkn_i);
 
@@ -615,11 +647,11 @@ module divider (
     input  wire        rst_i      ,
     input  wire        stall_i    ,
     input  wire        valid_i    ,
-    input  wire  [2:0] div_ctrl_i ,
-    input  wire [31:0] src1_i     ,
-    input  wire [31:0] src2_i     ,
+    input  wire [`DIV_CTRL_WIDTH-1:0] div_ctrl_i ,
+    input  wire [`XLEN-1:0] src1_i     ,
+    input  wire [`XLEN-1:0] src2_i     ,
     output wire        stall_o    ,
-    output wire [31:0] rslt_o
+    output wire [`XLEN-1:0] rslt_o
 );
 
     reg [1:0] state = `DIV_IDLE;
@@ -627,25 +659,44 @@ module divider (
 
     reg        is_dividend_neg;
     reg        is_divisor_neg;
-    reg [31:0] remainder;
-    reg [31:0] divisor;
-    reg [31:0] quotient;
+    reg [`XLEN-1:0] remainder;
+    reg [`XLEN-1:0] divisor;
+    reg [`XLEN-1:0] quotient;
     reg        is_div_rslt_neg;
     reg        is_rem_rslt_neg;
     reg        is_rem;
-    reg  [4:0] cntr;
-
-    wire [31:0] uintx_remainder = (is_dividend_neg) ? ~remainder+1 : remainder;
-    wire [31:0] uintx_divisor   = (is_divisor_neg ) ? ~divisor+1   : divisor;
-    wire [32:0] difference      = {remainder[30:0], quotient[31]} - divisor;
-    wire        q               = !difference[32];
-
+`ifdef RV64
+    reg        is_w;
+`endif
+    reg  [$clog2(`XLEN)-1:0] cntr;
+
+    wire [`XLEN-1:0] uintx_remainder = (is_dividend_neg) ? ~remainder+1 : remainder;
+    wire [`XLEN-1:0] uintx_divisor   = (is_divisor_neg ) ? ~divisor+1   : divisor;
+    wire [`XLEN:0] difference      = {remainder[`XLEN-2:0], quotient[`XLEN-1]} - divisor;
+    wire        q               = !difference[`XLEN];
+
+`ifdef RV64
+    wire [`XLEN-1:0] raw_rslt = (is_rem) ? ((is_rem_rslt_neg) ? ~remainder+1 : remainder) :
+                                      ((is_div_rslt_neg) ? ~quotient+1  : quotient ) ;
+    assign rslt_o = (state!=`DIV_RET) ? 0 :
+                    (is_w) ? {{32{raw_rslt[31]}}, raw_rslt[31:0]} : raw_rslt;
+`else
     assign rslt_o = (state!=`DIV_RET) ? 0 :
                     (is_rem) ? ((is_rem_rslt_neg) ? ~remainder+1 : remainder) :
                     ((is_div_rslt_neg) ? ~quotient+1  : quotient ) ;
+`endif
 
     wire w_div    = div_ctrl_i[`DIV_CTRL_IS_DIV];
     wire w_signed = div_ctrl_i[`DIV_CTRL_IS_SIGNED];
+`ifdef RV64
+    wire w_is_w   = div_ctrl_i[`DIV_CTRL_IS_W];
+    wire [`XLEN-1:0] s1 = (w_is_w) ? (w_signed ? {{32{src1_i[31]}}, src1_i[31:0]} : {32'd0, src1_i[31:0]}) : src1_i;
+    wire [`XLEN-1:0] s2 = (w_is_w) ? (w_signed ? {{32{src2_i[31]}}, src2_i[31:0]} : {32'd0, src2_i[31:0]}) : src2_i;
+`else
+    wire [`XLEN-1:0] s1 = src1_i;
+    wire [`XLEN-1:0] s2 = src2_i;
+`endif
+
     wire [1:0] w_state = (w_init) ? `DIV_CHECK :
                          (state==`DIV_CHECK && divisor==0) ? `DIV_RET : // Note
                          (state==`DIV_CHECK && divisor!=0) ? `DIV_EXEC :
@@ -654,52 +705,128 @@ module divider (
 
     wire w_init = (state==`DIV_IDLE && valid_i && w_div);
     always @(posedge clk_i) if (!stall_i) begin
-        is_rem            <= (w_init) ? div_ctrl_i[`DIV_CTRL_IS_REM] : is_rem;
-        is_dividend_neg   <= (w_init) ? w_signed && src1_i[31] : is_dividend_neg;
-        is_divisor_neg    <= (w_init) ? w_signed && src2_i[31] : is_divisor_neg;
-        is_div_rslt_neg   <= (w_init) ? w_signed && (src1_i[31] ^ src2_i[31]) :
-                             (state==`DIV_CHECK && divisor==0) ? 0 : is_div_rslt_neg;
-        is_rem_rslt_neg   <= (w_init) ? w_signed &&  src1_i[31] :
-                             (state==`DIV_CHECK && divisor==0) ? 0 : is_rem_rslt_neg;
-
-        divisor <= (w_init) ? src2_i :
-                   (state==`DIV_CHECK && divisor!=0) ? uintx_divisor : divisor;
-
-        {remainder, quotient} <= (w_init) ? {src1_i, 32'd0} :
-                   (state==`DIV_CHECK && divisor==0) ? {remainder, {32{1'b1}}} :
-                   (state==`DIV_CHECK && divisor!=0) ? {32'd0, uintx_remainder} :
-                   (state==`DIV_EXEC) ? ((q) ? {difference[31:0], quotient[30:0], 1'b1} :
-                                               {remainder[30:0], quotient, 1'b0}) :
-                   {remainder, quotient};
-
-        cntr <= (state==`DIV_CHECK) ? 31 : (state==`DIV_EXEC) ?  cntr-1 : cntr;
-        state <= w_state;
+        if (rst_i) begin
+            state <= `DIV_IDLE;
+        end else begin
+            is_rem            <= (w_init) ? div_ctrl_i[`DIV_CTRL_IS_REM] : is_rem;
+`ifdef RV64
+            is_w              <= (w_init) ? w_is_w : is_w;
+`endif
+            is_dividend_neg   <= (w_init) ? w_signed && s1[`XLEN-1] : is_dividend_neg;
+            is_divisor_neg    <= (w_init) ? w_signed && s2[`XLEN-1] : is_divisor_neg;
+            is_div_rslt_neg   <= (w_init) ? w_signed && (s1[`XLEN-1] ^ s2[`XLEN-1]) :
+                                 (state==`DIV_CHECK && divisor==0) ? 0 : is_div_rslt_neg;
+            is_rem_rslt_neg   <= (w_init) ? w_signed &&  s1[`XLEN-1] :
+                                 (state==`DIV_CHECK && divisor==0) ? 0 : is_rem_rslt_neg;
+
+            divisor <= (w_init) ? s2 :
+                       (state==`DIV_CHECK && divisor!=0) ? uintx_divisor : divisor;
+
+            {remainder, quotient} <= (w_init) ? {s1, {`XLEN{1'b0}}} :
+                       (state==`DIV_CHECK && divisor==0) ? {remainder, {`XLEN{1'b1}}} :
+                       (state==`DIV_CHECK && divisor!=0) ? {{`XLEN{1'b0}}, uintx_remainder} :
+                       (state==`DIV_EXEC) ? ((q) ? {difference[`XLEN-1:0], quotient[`XLEN-2:0], 1'b1} :
+                                                   {remainder[`XLEN-2:0], quotient, 1'b0}) :
+                       {remainder, quotient};
+
+            cntr <= (state==`DIV_CHECK) ? `XLEN-1 : (state==`DIV_EXEC) ?  cntr-1 : cntr;
+            state <= w_state;
+        end
     end
 endmodule
 
+`ifdef RV64
+`define MUL_IDLE   0
+`define MUL_EXEC_0 1
+`define MUL_EXEC_1 2
+`define MUL_EXEC_2 3
+`define MUL_EXEC_3 4
+`define MUL_RET    5
+`else
 `define MUL_IDLE 0
 `define MUL_EXEC 1
 `define MUL_RET 2
+`endif
 /******************************************************************************************/
 module multiplier (
     input  wire        clk_i,
     input  wire        rst_i,
     input  wire        stall_i,
     input  wire        valid_i,
-    input  wire [ 3:0] mul_ctrl_i,
-    input  wire [31:0] src1_i,
-    input  wire [31:0] src2_i,
+    input  wire [`MUL_CTRL_WIDTH-1:0] mul_ctrl_i,
+    input  wire [`XLEN-1:0] src1_i,
+    input  wire [`XLEN-1:0] src2_i,
     output wire        stall_o,
-    output wire [31:0] rslt_o
+    output wire [`XLEN-1:0] rslt_o
 );
+`ifdef RV64
+    parameter PIPE = 4; // Pipeline depth
+
+    wire w_mul         = mul_ctrl_i[`MUL_CTRL_IS_MUL];
+    wire w_src1_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC1_SIGNED];
+    wire w_src2_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC2_SIGNED];
+    wire w_is_high     = mul_ctrl_i[`MUL_CTRL_IS_HIGH];
+    wire w_is_w        = mul_ctrl_i[`MUL_CTRL_IS_W];
+
+    // Pre-process inputs (Sign/Zero extension for W instructions)
+    wire [`XLEN-1:0] a_op = w_is_w ? { {32{w_src1_signed & src1_i[31]}}, src1_i[31:0] } : src1_i;
+    wire [`XLEN-1:0] b_op = w_is_w ? { {32{w_src2_signed & src2_i[31]}}, src2_i[31:0] } : src2_i;
+
+    // Expand to 65 bits for signed multiplication
+    wire signed [`XLEN:0] mul_a = { w_src1_signed & a_op[(`XLEN-1)], a_op };
+    wire signed [`XLEN:0] mul_b = { w_src2_signed & b_op[(`XLEN-1)], b_op };
+
+    // Pipelined multiplier registers
+    (* srl_style = "register" *) reg signed [129:0] prod_pipe [PIPE-1:0];
+    reg [PIPE-1:0] is_w_pipe;
+    reg [PIPE-1:0] is_high_pipe;
+    
+    reg [3:0] count = 0;
+    integer i;
 
+    always @(posedge clk_i) begin
+        if (rst_i) begin
+            count <= 0;
+            is_w_pipe <= 0;
+            is_high_pipe <= 0;
+            for (i = 0; i < PIPE; i = i + 1) prod_pipe[i] <= 0;
+        end else if (!stall_i) begin
+            if (valid_i && w_mul && count == 0) begin
+                count <= PIPE;
+            end else if (count > 0) begin
+                count <= count - 1;
+            end
+
+            prod_pipe[0] <= mul_a * mul_b;
+            is_w_pipe    <= {is_w_pipe[PIPE-2:0], w_is_w};
+            is_high_pipe <= {is_high_pipe[PIPE-2:0], w_is_high};
+
+            for (i = 1; i < PIPE; i = i + 1) begin
+                prod_pipe[i] <= prod_pipe[i-1];
+            end
+        end
+    end
+
+    // stall_o is HIGH when we need to stall the CPU.
+    assign stall_o = (valid_i && w_mul && count == 0) || (count > 1);
+
+    // Output formatting
+    wire [129:0] product     = prod_pipe[PIPE-1];
+    wire         out_is_w    = is_w_pipe[PIPE-1];
+    wire         out_is_high = is_high_pipe[PIPE-1];
+    wire [31:0]  rslt_32     = product[31:0];
+
+    assign rslt_o = (count != 1) ? 0 : 
+                    (out_is_w) ? {{32{rslt_32[31]}}, rslt_32} :
+                    (out_is_high) ? product[2*`XLEN-1:`XLEN] : product[`XLEN-1:0];
+`else
     reg        [ 1:0] state = `MUL_IDLE;
-    reg signed [32:0] r_multiplicand;  // 33bit
-    reg signed [32:0] r_multiplier;  // 33bit
-    reg        [63:0] product;  // 64bit
+    reg signed [`XLEN:0] r_multiplicand;  // XLEN+1 bit
+    reg signed [`XLEN:0] r_multiplier;  // XLEN+1 bit
+    reg        [2*`XLEN-1:0] product;  // 2*XLEN bit
     reg               is_high;  //
 
-    assign rslt_o = (state != `MUL_RET) ? 0 : (is_high) ? product[63:32] : product[31:0];
+    assign rslt_o = (state != `MUL_RET) ? 0 : (is_high) ? product[2*`XLEN-1:`XLEN] : product[`XLEN-1:0];
 
     wire w_mul = mul_ctrl_i[`MUL_CTRL_IS_MUL];
     wire w_src1_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC1_SIGNED];
@@ -712,39 +839,47 @@ module multiplier (
         if (rst_i) begin
             state <= `MUL_IDLE;
         end else if (!stall_i) begin
-            if (state == `MUL_IDLE) r_multiplicand <= {w_src1_signed && src1_i[31], src1_i};
-            if (state == `MUL_IDLE) r_multiplier <= {w_src2_signed && src2_i[31], src2_i};
+            if (state == `MUL_IDLE) r_multiplicand <= {w_src1_signed && src1_i[`XLEN-1], src1_i};
+            if (state == `MUL_IDLE) r_multiplier <= {w_src2_signed && src2_i[`XLEN-1], src2_i};
             if (state == `MUL_IDLE) is_high <= w_is_high;
             if (state == `MUL_EXEC) product <= r_multiplicand * r_multiplier;
             state <= w_state;
         end
     end
     assign stall_o = (w_state != `MUL_IDLE);
+`endif
 endmodule
 
 /******************************************************************************************/
 module store_unit (
     input  wire        valid_i,
-    input  wire [ 5:0] lsu_ctrl_i,
-    input  wire [31:0] src1_i,
-    input  wire [31:0] src2_i,
-    input  wire [31:0] imm_i,
-    output wire [31:0] dbus_addr_o,
-    output wire [ 1:0] dbus_offset_o,
+    input  wire [`LSU_CTRL_WIDTH-1:0] lsu_ctrl_i,
+    input  wire [`XLEN-1:0] src1_i,
+    input  wire [`XLEN-1:0] src2_i,
+    input  wire [`XLEN-1:0] imm_i,
+    output wire [`XLEN-1:0] dbus_addr_o,
+    output wire [`DBUS_OFFSET_W-1:0] dbus_offset_o,
     output wire        dbus_wvalid_o,
-    output wire [31:0] dbus_wdata_o,
-    output wire [ 3:0] dbus_wstrb_o
+    output wire [`XLEN-1:0] dbus_wdata_o,
+    output wire [`DBUS_STRB_WIDTH-1:0] dbus_wstrb_o
 );
 
     assign dbus_addr_o   = (valid_i && (lsu_ctrl_i[`LSU_CTRL_IS_STORE] ||
                                         lsu_ctrl_i[`LSU_CTRL_IS_LOAD])) ? src1_i + imm_i : 0;
-    assign dbus_offset_o = dbus_addr_o[1:0];
+    assign dbus_offset_o = dbus_addr_o[`DBUS_OFFSET_W-1:0];
     assign dbus_wvalid_o = valid_i && lsu_ctrl_i[`LSU_CTRL_IS_STORE];
 
     wire w_sb = lsu_ctrl_i[`LSU_CTRL_IS_BYTE];
     wire w_sh = lsu_ctrl_i[`LSU_CTRL_IS_HALFWORD];
     wire w_sw = lsu_ctrl_i[`LSU_CTRL_IS_WORD];
 
+`ifdef RV64
+    assign dbus_wdata_o = (w_sb) ? {8{src2_i[7:0]}} :
+                          (w_sh) ? {4{src2_i[15:0]}} :
+                          (w_sw) ? {2{src2_i[31:0]}} : src2_i[`XLEN-1:0];
+    wire [`XBYTES-1:0] mask = (w_sb) ? 1 : (w_sh) ? 3 : (w_sw) ? 15 : {`XBYTES{1'b1}};
+    assign dbus_wstrb_o = mask << dbus_offset_o;
+`else
     assign dbus_wdata_o[7:0]   = src2_i[7:0];
     assign dbus_wdata_o[15:8]  = (w_sb) ? src2_i[7:0] : src2_i[15:8];
     assign dbus_wdata_o[23:16] = (w_sw) ? src2_i[23:16] : src2_i[7:0];
@@ -754,14 +889,15 @@ module store_unit (
     assign dbus_wstrb_o[1] = (w_sb && dbus_offset_o==1) || (w_sh && dbus_offset_o[1]==0) || w_sw;
     assign dbus_wstrb_o[2] = (w_sb && dbus_offset_o==2) || (w_sh && dbus_offset_o[1]==1) || w_sw;
     assign dbus_wstrb_o[3] = (w_sb && dbus_offset_o==3) || (w_sh && dbus_offset_o[1]==1) || w_sw;
+`endif
 endmodule
 
 /******************************************************************************************/
 module load_unit (
-    input  wire [ 5:0] lsu_ctrl_i,
-    input  wire [ 1:0] dbus_offset_i,
-    input  wire [31:0] dbus_rdata_i,
-    output wire [31:0] rslt_o
+    input  wire [`LSU_CTRL_WIDTH-1:0] lsu_ctrl_i,
+    input  wire [`DBUS_OFFSET_W-1:0] dbus_offset_i,
+    input  wire [`XLEN-1:0] dbus_rdata_i,
+    output wire [`XLEN-1:0] rslt_o
 );
 
     wire w_lb = lsu_ctrl_i[`LSU_CTRL_IS_BYTE];
@@ -769,8 +905,20 @@ module load_unit (
     wire w_lw = lsu_ctrl_i[`LSU_CTRL_IS_WORD];
     wire w_signed = lsu_ctrl_i[`LSU_CTRL_IS_SIGNED];
     wire w_load = lsu_ctrl_i[`LSU_CTRL_IS_LOAD];
-    wire [1:0] ost = dbus_offset_i;  // offset
-    wire [31:0] d = dbus_rdata_i;  // data
+`ifdef RV64
+    wire [`XLEN-1:0] d_shifted = dbus_rdata_i >> {dbus_offset_i, 3'b0};
+    wire [7:0] b = d_shifted[7:0];
+    wire [15:0] h = d_shifted[15:0];
+    wire [31:0] w = d_shifted[31:0];
+
+    assign rslt_o = (!w_load) ? 0 :
+                    (w_lb) ? {{(`XLEN-8){w_signed & b[7]}}, b} :
+                    (w_lh) ? {{(`XLEN-16){w_signed & h[15]}}, h} :
+                    (w_lw) ? {{(`XLEN-32){w_signed & w[31]}}, w} :
+                    d_shifted;
+`else
+    wire [`DBUS_OFFSET_W-1:0] ost = dbus_offset_i;  // offset
+    wire [`XLEN-1:0] d = dbus_rdata_i;  // data
 
     wire w_lb_sign = w_lb & ((ost==0) ? d[7] : (ost==1) ? d[15] :(ost==2) ? d[23] : d[31]) & w_signed;
     wire w_lh_sign = w_lh & ((ost[1] == 0) ? d[15] : d[31]) & w_signed;
@@ -784,13 +932,14 @@ module load_unit (
     assign w3 = (w_load == 0) ? 0 : (w_lw) ? d[23:16] : ((w_lb_sign) || (w_lh_sign)) ? 8'hff : 0;
     assign w4 = (w_load == 0) ? 0 : (w_lw) ? d[31:24] : ((w_lb_sign) || (w_lh_sign)) ? 8'hff : 0;
     assign rslt_o = {w4, w3, w2, w1};
+`endif
 endmodule
 
 /******************************************************************************************/
 module imm_gen (
     input  wire [        31:0] ir_i,
     input  wire [`ITYPE_W-1:0] instr_type_i,
-    output wire [        31:0] imm_o
+    output wire [   `XLEN-1:0] imm_o
 );
 
     wire [31:0] ir = ir_i;
@@ -806,7 +955,12 @@ module imm_gen (
     wire        imm11 = (i_ | s_) ? ir[31] : (b_) ? ir[7] : (j_) ? ir[20] : 0;
     wire [ 7:0] imm19_12 = (i_ | s_ | b_) ? {8{ir[31]}} : (u_ | j_) ? ir[19:12] : 0;
     wire [10:0] imm30_20 = (i_ | s_ | b_ | j_) ? {11{ir[31]}} : (u_) ? ir[30:20] : 0;
-    assign imm_o = {ir[31], imm30_20, imm19_12, imm11, imm10_5, imm4_1, imm0};
+    wire [31:0] imm32 = {ir[31], imm30_20, imm19_12, imm11, imm10_5, imm4_1, imm0};
+`ifdef RV64
+    assign imm_o = {{32{imm32[31]}}, imm32};
+`else
+    assign imm_o = imm32;
+`endif
 endmodule
 
 /******************************************************************************************/
@@ -829,7 +983,11 @@ module decoder (
     assign cfu_ctrl_o = (op == 5'b00010) ? {f7, f3, 1'b1} : 0;
 
     wire src2_c0 = (op == 5'b00101);  // AUIPC
+`ifdef RV64
+    wire src2_c1 = (op == 5'b01101) | (op == 5'b00100) | (op == 5'b00110);  // LUI, OP-IMM, OP-IMM-32
+`else
     wire src2_c1 = (op == 5'b01101) | (op == 5'b00100);  // LUI, OP-IMM
+`endif
     assign src2_ctrl_o = {src2_c1, src2_c0};
 
     wire bru_c0 = (op == 5'b11011) || (op == 5'b11001) || (op == 5'b11000);  // IS_CTRL_TSFR
@@ -847,35 +1005,71 @@ module decoder (
     wire lsu_c2 = (op == 0 && (f3 == 0 || f3 == 1 || f3 == 2));  // IS_SIGNED
     wire lsu_c3 = (op == 0 && (f3 == 0 || f3 == 4)) || (op == 8 && (f3 == 0));  // BYTE
     wire lsu_c4 = (op == 0 && (f3 == 1 || f3 == 5)) || (op == 8 && (f3 == 1));  // HALFWORD
+`ifdef RV64
+    wire lsu_c5 = (op == 0 && (f3 == 2 || f3 == 6)) || (op == 8 && (f3 == 2));  // WORD
+    wire lsu_c6 = (op == 0 && (f3 == 3)) || (op == 8 && (f3 == 3));  // DOUBLEWORD
+    assign lsu_ctrl_o = {lsu_c6, lsu_c5, lsu_c4, lsu_c3, lsu_c2, lsu_c1, lsu_c0};
+`else
     wire lsu_c5 = (op == 0 && (f3 == 2)) || (op == 8 && (f3 == 2));  // WORD
     assign lsu_ctrl_o = {lsu_c5, lsu_c4, lsu_c3, lsu_c2, lsu_c1, lsu_c0};
+`endif
 
+`ifdef RV64
+    wire mul_c0 = ((op == 12) && (f7 == 1) && (f3 == 0 || f3 == 1 || f3 == 2 || f3 == 3)) ||
+                  ((op == 14) && (f7 == 1) && (f3 == 0));  // IS_MUL
+`else
     wire mul_c0 = (op == 12) && (f7 == 1) && (f3 == 0 || f3 == 1 || f3 == 2 || f3 == 3);  // IS_MUL
+`endif
     wire mul_c1 = (op == 12) && (f7 == 1) && (f3 == 1 || f3 == 2);  // IS_SRC1_SIGNED
     wire mul_c2 = (op == 12) && (f7 == 1) && (f3 == 1);  // IS_SRC2_SIGNED
     wire mul_c3 = (op == 12) && (f7 == 1) && (f3 == 1 || f3 == 2 || f3 == 3);  // IS_HIGH
+`ifdef RV64
+    wire mul_c4 = (op == 14) && (f7 == 1) && (f3 == 0); // IS_W
+    assign mul_ctrl_o = {mul_c4, mul_c3, mul_c2, mul_c1, mul_c0};
+`else
     assign mul_ctrl_o = {mul_c3, mul_c2, mul_c1, mul_c0};
-
+`endif
+
+`ifdef RV64
+    wire div_c0 = ((op == 12) || (op == 14)) && (f7 == 1) && (f3 == 4 || f3 == 5 || f3 == 6 || f3 == 7);  // IS_DIV
+    wire div_c1 = ((op == 12) || (op == 14)) && (f7 == 1) && (f3 == 4 || f3 == 6);  // IS_SIGNED
+    wire div_c2 = ((op == 12) || (op == 14)) && (f7 == 1) && (f3 == 6 || f3 == 7);  // IS_REM
+    wire div_c3 = (op == 14) && (f7 == 1) && (f3 == 4 || f3 == 5 || f3 == 6 || f3 == 7); // IS_W
+    assign div_ctrl_o = {div_c3, div_c2, div_c1, div_c0};
+`else
     wire div_c0 = (op == 12) && (f7 == 1) && (f3 == 4 || f3 == 5 || f3 == 6 || f3 == 7);  // IS_DIV
     wire div_c1 = (op == 12) && (f7 == 1) && (f3 == 4 || f3 == 6);  // IS_SIGNED
     wire div_c2 = (op == 12) && (f7 == 1) && (f3 == 6 || f3 == 7);  // IS_REM
     assign div_ctrl_o = {div_c2, div_c1, div_c0};
+`endif
 
     wire [9:0] f10 = {f7, f3};
-    wire alu_c0 = (op==4 && f3==2) || (op==4 && f3==5 && f7==7'b0100000) ||
-                  (op==5'b01100 && (f10==10'b10 || f10==10'b0100000101)); // IS_SIGNED
-    wire alu_c1 = (op==4 && (f3==2 || f3==3)) || (op==5'b01100 &&
+`ifdef RV64
+    wire is_op_imm = (op == 5'b00100) || (op == 5'b00110); // OP-IMM, OP-IMM-32
+    wire is_op     = (op == 5'b01100) || (op == 5'b01110); // OP, OP-32
+`else
+    wire is_op_imm = (op == 5'b00100);
+    wire is_op     = (op == 5'b01100);
+`endif
+    wire alu_c0 = (is_op_imm && f3==2) || (is_op_imm && f3==5 && f7==7'b0100000) ||
+                  (is_op && (f10==10'b10 || f10==10'b0100000101)); // IS_SIGNED
+    wire alu_c1 = (is_op_imm && (f3==2 || f3==3)) || (is_op &&
                   (f10==10'b100000000 || f10==10'b10 || f10==10'b11)); // IS_NEG
-    wire alu_c2 = (op==4 && (f3==2 || f3==3)) ||
-                  (op==5'b01100 && (f10==10'b10 || f10==10'b11)); // IS_LESS
-    wire alu_c3 = (op==4 && f3==0) ||
-                  (op==5'b01100 && (f10==10'b0 || f10==10'b100000000)); // IS_ADD
-    wire alu_c4 = (op == 4 && f3 == 1 && f7 == 7'b0) || (op == 12 && f10 == 1);  // IS_SHIFT_LEFT
-    wire alu_c5 = (op==4 && f3==5 && (f7==7'b0 || f7==7'b100000)) || (op==12 &&
+    wire alu_c2 = (is_op_imm && (f3==2 || f3==3)) ||
+                  (is_op && (f10==10'b10 || f10==10'b11)); // IS_LESS
+    wire alu_c3 = (is_op_imm && f3==0) ||
+                  (is_op && (f10==10'b0 || f10==10'b100000000)); // IS_ADD
+    wire alu_c4 = (is_op_imm && f3 == 1 && f7[6:1] == 6'b0) || (is_op && f10 == 1);  // IS_SHIFT_LEFT
+    wire alu_c5 = (is_op_imm && f3==5 && (f7[6:1]==6'b0 || f7[6:1]==6'b010000)) || (is_op &&
                   (f10==10'b101 || f10==10'b0100000101)); // IS_SHIFT_RIGHT
-    wire alu_c6 = (op==4 && (f3==4 || f3==6)) || (op==12 && (f10==4 || f10==6));//IS_XOR_OR
-    wire alu_c7 = (op==4 && (f3==6 || f3==7)) || (op==12 && (f10==6 || f10==7));//IS_OR_AND
+    wire alu_c6 = (is_op_imm && (f3==4 || f3==6)) || (is_op && (f10==4 || f10==6));//IS_XOR_OR
+    wire alu_c7 = (is_op_imm && (f3==6 || f3==7)) || (is_op && (f10==6 || f10==7));//IS_OR_AND
     wire alu_c8 = (op == 5'b01101 || op == 5'b00101);  // IS_SRC2
+`ifdef RV64
+    wire alu_c9 = (op == 5'b00110 || op == 5'b01110);  // IS_W
+    assign alu_ctrl_o = {alu_c9, alu_c8, alu_c7, alu_c6, alu_c5, alu_c4, alu_c3, alu_c2, alu_c1, alu_c0};
+`else
     assign alu_ctrl_o = {alu_c8, alu_c7, alu_c6, alu_c5, alu_c4, alu_c3, alu_c2, alu_c1, alu_c0};
+`endif
 endmodule
 /******************************************************************************************/
diff --git a/top.v b/top.v
index fbacfbd..32a1295 100644
--- a/top.v
+++ b/top.v
@@ -87,7 +87,6 @@ module top;
 //==============================================================================
 // Debug Dump
 //------------------------------------------------------------------------------
-/*
     reg r_rst = 0;
     always @(posedge clk) r_rst <= !m0.rst;
     always @(posedge clk) if (r_rst) begin
@@ -108,7 +107,6 @@ module top;
 
         $write("\n");
     end
-*/
 
     wire sda, scl, dc, res;
     main m0 (
