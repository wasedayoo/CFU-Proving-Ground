# CSR書き込み後のパイプラインflush

## 変更内容

- MA段でCSR書き込みがcommitされるときに`Ma_csr_flush`をアサートする。
- `Ma_csr_flush`を既存の`Ma_pc_redirect`へ追加する。
- CSR命令自身はretireさせ、IF・ID・EX段の若い命令だけを破棄する。
- CSR flush時は既存のデフォルトリダイレクト先である`ExMa_pc + 4`から再fetchする。
- CSRを更新しない読み出し命令は`ExMa_csr_we`が立たないためflushしない。
- CSR書き込み後の命令はcommit後に再fetchされるため、CSR値のMA→EX forwardingを削除する。
- 同じ理由により、`mepc`書き込みから直後の`mret`への専用forwardingも削除する。
- 通常の整数レジスタforwardingは変更しない。

## Diff

```diff
diff --git a/proc.v b/proc.v
index 808a3b4..d5423c3 100644
--- a/proc.v
+++ b/proc.v
@@ -120,10 +120,12 @@ module cpu (
     wire Ma_timer_irq = ExMa_v && timer_irq_i && csr_timer_irq_enabled &&
                         !ExMa_stall && !w_stall && !Ma_trap && !Ma_mret &&
                         !ExMa_csr_we;
+    wire        Ma_csr_flush   = ExMa_v && ExMa_csr_we && !ExMa_stall;
     wire        Ma_br_misp     = (rst) ? 1 :
                                  (ExMa_v && ExMa_is_ctrl_tsfr &&
                                  ((Ma_br_tkn) ? ExMa_br_misp_rslt1 : ExMa_br_misp_rslt2));
-    wire        Ma_pc_redirect = Ma_br_misp || Ma_mret || Ma_trap || Ma_timer_irq;
+    wire        Ma_pc_redirect = Ma_br_misp || Ma_mret || Ma_trap || Ma_timer_irq ||
+                                 Ma_csr_flush;
     wire [`XLEN-1:0] Ma_redirect_pc  = (rst)         ? `RESET_VECTOR :
                                        (Ma_trap)     ? csr_mtvec :
                                        (Ma_timer_irq)? csr_mtvec :
@@ -324,16 +326,11 @@ module cpu (
     wire [`XLEN-1:0] Ex_src2 = (IdEx_rs2_fwd_Ma_to_Ex) ? ExMa_rslt : IdEx_src2;
 
     ///// control and status registers
-    // csr_ctrl is the SYSTEM instruction's funct3 (zero means non-CSR).
     wire [      11:0] Ex_csr_addr = IdEx_ir[31:20];
     wire [ `XLEN-1:0] csr_rdata;
     wire [ `XLEN-1:0] csr_mepc;
     wire [ `XLEN-1:0] csr_mtvec;
     wire              csr_timer_irq_enabled;
-    wire              ExMa_csr_forward = ExMa_v && ExMa_csr_we &&
-                                             (ExMa_csr_addr == Ex_csr_addr);
-    wire [ `XLEN-1:0] Ex_csr_rdata =
-        ExMa_csr_forward ? ExMa_csr_wdata : csr_rdata;
     wire [ `XLEN-1:0] Ex_csr_src = IdEx_csr_ctrl[2] ?
                                    {{(`XLEN-5){1'b0}}, IdEx_ir[19:15]} : Ex_src1;
     wire              Ex_csr_rw = (IdEx_csr_ctrl[1:0] == 2'b01);
@@ -344,11 +341,9 @@ module cpu (
                                   (Ex_csr_rw || (IdEx_ir[19:15] != 0));
     wire [ `XLEN-1:0] Ex_csr_wdata =
         Ex_csr_rw ? Ex_csr_src :
-        Ex_csr_rs ? (Ex_csr_rdata | Ex_csr_src) :
-        Ex_csr_rc ? (Ex_csr_rdata & ~Ex_csr_src) : Ex_csr_rdata;
-    wire [ `XLEN-1:0] Ex_mret_pc =
-        (ExMa_v && ExMa_csr_we && (ExMa_csr_addr == 12'h341)) ?
-        ExMa_csr_wdata : csr_mepc;
+        Ex_csr_rs ? (csr_rdata | Ex_csr_src) :
+        Ex_csr_rc ? (csr_rdata & ~Ex_csr_src) : csr_rdata;
+    wire [ `XLEN-1:0] Ex_mret_pc = csr_mepc;
 
     csr_file csr (
         .clk_i  (clk_i),
@@ -485,7 +480,7 @@ module cpu (
             ExMa_dbus_offset   <= dbus_offset;
             ExMa_rf_we         <= IdEx_rf_we;
             ExMa_rd            <= IdEx_rd;
-            ExMa_rslt          <= (IdEx_csr_ctrl != 0) ? Ex_csr_rdata : Ex_alu_rslt;
+            ExMa_rslt          <= (IdEx_csr_ctrl != 0) ? csr_rdata : Ex_alu_rslt;
             ExMa_csr_we        <= Ex_csr_we;
             ExMa_csr_addr      <= Ex_csr_addr;
             ExMa_csr_wdata     <= Ex_csr_wdata;
```

`Ma_redirect_pc`の既存の最終選択肢は`ExMa_pc + 4`である。そのため、trap、
timer interrupt、`mret`、taken branchのいずれでもないCSR flushでは、CSR命令の
次のPCから命令を取り直す。

この再fetchによって、後続のCSR命令および`mret`はcommit済みのCSR値を直接
読み出せるため、削除したCSR専用forwardingと同じ依存関係を正しく処理できる。

## 検証結果

以下を実行し、正常終了を確認した。

```text
/var/archlab-modules/verilator/5.046/bin/verilator --lint-only \
  --top-module top --Wno-WIDTHTRUNC --Wno-WIDTHEXPAND *.v

make -C tests/mtkernel smoke-run
```

smokeテスト結果:

```text
MTKERNEL_SMOKE: PASS
```
