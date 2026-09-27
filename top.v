/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

`default_nettype none

module top;
    reg clk   = 1; always #5 clk <= ~clk;
    reg rst_n = 0; initial #50 rst_n = 1;

//==============================================================================
// Perfomance Counter
//------------------------------------------------------------------------------
    reg [63:0] mcycle = 0;
    always @(posedge clk) if (!m0.rst && !cpu_sim_fini) mcycle <= mcycle + 1;

    reg [63:0] minstret     = 0;
    reg [63:0] br_pred_cntr = 0;
    reg [63:0] br_misp_cntr = 0;
    always @(posedge clk) if (!m0.rst && !cpu_sim_fini && !m0.cpu.stall_i) begin
        if (!m0.cpu.stall && m0.cpu.Ma_v) minstret <= minstret + 1;
        if (m0.cpu.ExMa_v && m0.cpu.ExMa_is_ctrl_tsfr)
          br_pred_cntr <= br_pred_cntr + 1;
        if (m0.cpu.ExMa_v && m0.cpu.ExMa_is_ctrl_tsfr && m0.cpu.Ma_br_misp)
          br_misp_cntr <= br_misp_cntr + 1;
    end
//==============================================================================
// Dump
//------------------------------------------------------------------------------
/*
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, top);
    end
*/

//==============================================================================
// Condition for simulation to end
//------------------------------------------------------------------------------
    reg cpu_sim_fini = 0;
    always @(posedge clk) begin
        if (m0.cpu.dbus_addr_o == 32'h80000000 && m0.cpu.dbus_wvalid_o) begin
            if (m0.cpu.dbus_wdata[31:0] == 32'h00020000) cpu_sim_fini <= 1;
            else begin $write("%c", m0.cpu.dbus_wdata[7:0]); $fflush(); end
        end
        if (cpu_sim_fini) begin
            $finish(1);
        end
    end

    final begin
        $write("\n");
        $write("===> mcycle                                 : %10d\n", mcycle);
        $write("===> minstret                               : %10d\n", minstret);
        $write("===> Total number of branch predictions     : %10d\n", br_pred_cntr);
        $write("===> Total number of branch mispredictions  : %10d\n", br_misp_cntr);
        $write("===> simulation finish!!\n");
        $write("\n");
    end

//==============================================================================
// Debug Dump
//------------------------------------------------------------------------------
/*
    reg r_rst = 0;
    always @(posedge clk) r_rst <= !m0.rst;
    always @(posedge clk) if (r_rst) begin
        $write(" %06d: %x ", minstret, m0.cpu.r_pc);
        if (m0.cpu.IfId_v) $write("%x ", m0.cpu.IfId_pc); else $write("-------- ");
        if (m0.cpu.IdEx_v) $write("%x", m0.cpu.IdEx_pc); else $write("--------");
        if (m0.cpu.IdEx_v && m0.cpu.IdEx_bru_ctrl[0]) begin
          if(m0.cpu.IdEx_bru_ctrl[7:6]) $write("(J) "); else $write("(B) ");
        end
        else $write("( ) ");
        if (m0.cpu.ExMa_v) $write("%x ", m0.cpu.ExMa_pc); else $write("-------- ");
        if (m0.cpu.MaWb_v) $write("%x:", m0.cpu.MaWb_pc); else $write("--------:");
        if (m0.cpu.ExMa_v && m0.cpu.ExMa_is_ctrl_tsfr) begin
            $write(" JB_in_Ma:");
            if (m0.cpu.ExMa_is_ctrl_tsfr && m0.cpu.Ma_br_misp)
              $write(" miss"); else $write(" hit");
        end

        $write("\n");
    end
*/

    wire sda, scl, dc, res;
    main m0 (
        .clk_i      (clk),
        .st7789_SDA (sda),
        .st7789_SCL (scl),
        .st7789_DC  (dc),
        .st7789_RES (res)
    );
endmodule
