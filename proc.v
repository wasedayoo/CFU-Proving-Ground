/******************************************************************************************/
`default_nettype none
`include "config.vh"
/******************************************************************************************/
`define DBUS_OFFSET_W $clog2(`XBYTES)
`define PC_W $clog2(`IMEM_SIZE)  // PC width
`define ITYPE_W `INSTR_TYPE_WIDTH

/******************************************************************************************/
module cpu (
    input  wire                        clk_i,
    input  wire                        rst_i,
    input  wire                        stall_i,
    output wire [`IBUS_ADDR_WIDTH-1:0] ibus_araddr_o,
    input  wire [`IBUS_DATA_WIDTH-1:0] ibus_rdata_i,
    output wire [`DBUS_ADDR_WIDTH-1:0] dbus_addr_o,
    output wire                        dbus_wvalid_o,
    output wire [`DBUS_DATA_WIDTH-1:0] dbus_wdata_o,
    output wire [`DBUS_STRB_WIDTH-1:0] dbus_wstrb_o,
    input  wire [`DBUS_DATA_WIDTH-1:0] dbus_rdata_i
);
    wire w_stall = stall_i;

//------------------------------------------------------------------------------
// pipeline registers
//------------------------------------------------------------------------------
    // IF: Instruction Fetch
    reg [          `XLEN-1:0] r_pc;  // program counter

    // ID: Instruction Decode
    reg                       IfId_v;
    reg [          `XLEN-1:0] IfId_pc;
    reg [               31:0] IfId_ir;
    reg                       IfId_br_pred_tkn;
    reg [                1:0] IfId_pat_hist;
    reg                       IfId_load_muldiv_use;
    reg [       `ITYPE_W-1:0] IfId_instr_type;
    reg                       IfId_rf_we;
    reg [                4:0] IfId_rd;
    reg [                4:0] IfId_rs1;
    reg [                4:0] IfId_rs2;

    // EX: Execution
    reg                       IdEx_v;
    reg [          `XLEN-1:0] IdEx_pc;
    reg [               31:0] IdEx_ir;
    reg                       IdEx_br_pred_tkn;
    reg [                1:0] IdEx_pat_hist;
    reg [`ALU_CTRL_WIDTH-1:0] IdEx_alu_ctrl;
    reg [`BRU_CTRL_WIDTH-1:0] IdEx_bru_ctrl;
    reg [`LSU_CTRL_WIDTH-1:0] IdEx_lsu_ctrl;
    reg [`MUL_CTRL_WIDTH-1:0] IdEx_mul_ctrl;
    reg [`DIV_CTRL_WIDTH-1:0] IdEx_div_ctrl;
    reg [`CFU_CTRL_WIDTH-1:0] IdEx_cfu_ctrl;
    reg                       IdEx_rs1_fwd_Ma_to_Ex;
    reg                       IdEx_rs2_fwd_Ma_to_Ex;
    reg [          `XLEN-1:0] IdEx_src1;
    reg [          `XLEN-1:0] IdEx_src2;
    reg [          `XLEN-1:0] IdEx_imm;
    reg                       IdEx_rf_we;
    reg [                4:0] IdEx_rd;
    reg [          `XLEN-1:0] IdEx_j_pc4;

    // MA: Memory Access
    reg                       ExMa_v;
    reg [          `XLEN-1:0] ExMa_pc;
    reg [               31:0] ExMa_ir;
    reg [                1:0] ExMa_pat_hist;
    reg                       ExMa_is_ctrl_tsfr;
    reg                       ExMa_br_tkn;
    reg                       ExMa_br_misp_rslt1;
    reg                       ExMa_br_misp_rslt2;
    reg [          `XLEN-1:0] ExMa_br_tkn_pc;
    reg [`LSU_CTRL_WIDTH-1:0] ExMa_lsu_ctrl;
    reg [ `DBUS_OFFSET_W-1:0] ExMa_dbus_offset;
    reg                       ExMa_rf_we;
    reg [                4:0] ExMa_rd;
    reg [          `XLEN-1:0] ExMa_rslt;
    reg [          `XLEN-1:0] ExMa_mdc_rslt;  // mul_div_cfu_rslt
    reg                       ExMa_j_b_insn;  // jump or branch insn
    reg                       ExMa_mul_stall;
    reg                       ExMa_div_stall;
    reg                       ExMa_stall;

    // WB: Write Back
    reg                       MaWb_v;
    reg [          `XLEN-1:0] MaWb_pc;
    reg [               31:0] MaWb_ir;
    reg                       MaWb_rf_we;
    reg [                4:0] MaWb_rd;
    reg [          `XLEN-1:0] MaWb_rslt;

//------------------------------------------------------------------------------
// pipeline control
//------------------------------------------------------------------------------
    reg                       rst;
    always @(posedge clk_i) if (!w_stall) rst <= rst_i;

    wire Ma_br_tkn = (ExMa_v && ExMa_br_tkn);
    wire        Ma_br_misp     = (rst) ? 1 :
                                 (ExMa_v && ExMa_is_ctrl_tsfr &&
                                 ((Ma_br_tkn) ? ExMa_br_misp_rslt1 : ExMa_br_misp_rslt2));
    wire [`XLEN-1:0] Ma_br_true_pc  = (rst) ?`RESET_VECTOR :
                                 (ExMa_br_tkn) ? ExMa_br_tkn_pc : ExMa_pc+4;

    wire If_v = (Ma_br_misp) ? 0 : (IfId_load_muldiv_use) ? IfId_v : 1;
    wire Id_v = (Ma_br_misp || IfId_load_muldiv_use) ? 0 : IfId_v;
    wire Ex_v = (Ma_br_misp) ? 0 : IdEx_v;
    wire Ma_v = ExMa_v;
    wire stall = ExMa_stall;

//------------------------------------------------------------------------------
// IF: Instruction Fetch
//------------------------------------------------------------------------------
    wire [`PC_W-1:0] If_pc;  // the program counter of the next clock cycle
    wire [`PC_W-1:0] If_pc_inc;  //
    wire If_pc_stall;
    wire [1:0] If_pat_hist;
    wire If_br_pred_tkn;
    wire [`XLEN-1:0] If_br_pred_pc;
    wire [`ITYPE_W-1:0] If_instr_type;
    wire If_rf_we;
    wire [4:0] If_rd;
    wire [4:0] If_rs1;
    wire [4:0] If_rs2;
    wire [31:0] If_ir;  // instruction from imem

    assign ibus_araddr_o = If_pc;  // read address of imem
    assign If_ir = ibus_rdata_i;  // instruction from imem

    bimodal bimodal (
        .clk_i        (clk_i),           // input  wire
        .rst_i        (rst),             // input  wire
        .stall_i      (w_stall),         // input  wire
        .raddr_i      (If_pc),           // input  wire [`XLEN-1:0]
        .pat_hist_o   (If_pat_hist),     // output reg        [1:0]
        .br_pred_tkn_o(If_br_pred_tkn),  // output wire
        .br_pred_pc_o (If_br_pred_pc),   // output reg  [`XLEN-1:0]
        .br_tkn_i     (Ma_br_tkn),       // input  wire
        .br_tsfr_i    (ExMa_j_b_insn),   // input  wire
        .waddr_i      (ExMa_pc),         // input  wire [`XLEN-1:0]
        .pat_hist_i   (ExMa_pat_hist),   // input  wire       [1:0]
        .br_tkn_pc_i  (ExMa_br_tkn_pc)   // input  wire [`XLEN-1:0]
    );

    assign If_pc_stall = ExMa_stall || IfId_load_muldiv_use;
    assign If_pc_inc = (If_pc_stall) ? 0 : 4;
    assign If_pc = (w_stall) ? r_pc :
                   (Ma_br_misp                   ) ? Ma_br_true_pc :
                   (!If_pc_stall & If_br_pred_tkn) ? If_br_pred_pc : r_pc+If_pc_inc;

    pre_decoder pre_decoder (
        .ir_i        (If_ir),          // input  wire         [31:0]
        .instr_type_o(If_instr_type),  // output wire [`ITYPE_W-1:0]
        .rf_we_o     (If_rf_we),       // output wire
        .rd_o        (If_rd),          // output wire          [4:0]
        .rs1_o       (If_rs1),         // output wire          [4:0]
        .rs2_o       (If_rs2)          // output wire          [4:0]
    );

    wire If_load_muldiv_use = IfId_v && !Ma_br_misp && !IfId_load_muldiv_use
                              && (Id_lsu_ctrl[`LSU_CTRL_IS_LOAD] ||
                                  Id_mul_ctrl[`MUL_CTRL_IS_MUL] ||
                                  Id_div_ctrl[`DIV_CTRL_IS_DIV] ||
                                  Id_cfu_ctrl[`CFU_CTRL_IS_CFU]  )
                              && IfId_rf_we && ((IfId_rd==If_rs1) || (IfId_rd==If_rs2));

    always @(posedge clk_i) if (!w_stall) begin
        r_pc <= If_pc;  // update pc
        if (rst) begin
            IfId_v  <= 0;
            IfId_pc <= 0;
            IfId_ir <= `NOP;
        end else if (!ExMa_stall) begin
            IfId_v               <= If_v;
            IfId_load_muldiv_use <= If_load_muldiv_use;
            if (!IfId_load_muldiv_use) begin
                IfId_pc          <= r_pc;
                IfId_ir          <= If_ir;
                IfId_br_pred_tkn <= If_br_pred_tkn;
                IfId_pat_hist    <= If_pat_hist;
                IfId_instr_type  <= If_instr_type;
                IfId_rf_we       <= If_rf_we;
                IfId_rd          <= If_rd;
                IfId_rs1         <= If_rs1;
                IfId_rs2         <= If_rs2;
            end
        end
    end

//------------------------------------------------------------------------------
// ID: Instruction Decode
//------------------------------------------------------------------------------
    // instruction decoder
    wire [`SRC2_CTRL_WIDTH-1:0] Id_src2_ctrl;
    wire [ `ALU_CTRL_WIDTH-1:0] Id_alu_ctrl;
    wire [ `BRU_CTRL_WIDTH-1:0] Id_bru_ctrl;
    wire [ `LSU_CTRL_WIDTH-1:0] Id_lsu_ctrl;
    wire [ `MUL_CTRL_WIDTH-1:0] Id_mul_ctrl;
    wire [ `DIV_CTRL_WIDTH-1:0] Id_div_ctrl;
    wire [ `CFU_CTRL_WIDTH-1:0] Id_cfu_ctrl;
    decoder decoder (
        .ir_i       (IfId_ir),       // input  wire                 [31:0]
        .src2_ctrl_o(Id_src2_ctrl),  // output wire [`SRC2_CTRL_WIDTH-1:0]
        .alu_ctrl_o (Id_alu_ctrl),   // output wire  [`ALU_CTRL_WIDTH-1:0]
        .bru_ctrl_o (Id_bru_ctrl),   // output wire  [`BRU_CTRL_WIDTH-1:0]
        .lsu_ctrl_o (Id_lsu_ctrl),   // output wire  [`LSU_CTRL_WIDTH-1:0]
        .mul_ctrl_o (Id_mul_ctrl),   // output wire  [`MUL_CTRL_WIDTH-1:0]
        .div_ctrl_o (Id_div_ctrl),   // output wire  [`DIV_CTRL_WIDTH-1:0]
        .cfu_ctrl_o (Id_cfu_ctrl)    // output wire  [`CFU_CTRL_WIDTH-1:0]
    );

    // immediate value generator
    wire [`XLEN-1:0] Id_imm;
    imm_gen imm_gen (
        .ir_i        (IfId_ir),          // input  wire         [31:0]
        .instr_type_i(IfId_instr_type),  // input  wire [`ITYPE_W-1;0]
        .imm_o       (Id_imm)            // output wire    [`XLEN-1:0]
    );

    // register file
    wire [`XLEN-1:0] Id_xrs1;
    wire [`XLEN-1:0] Id_xrs2;
    wire             Wb_xreg_we = MaWb_v && MaWb_rf_we && !ExMa_stall;
    regfile xreg (
        .clk_i  (clk_i),       // input  wire
        .rs1_i  (IfId_rs1),    // input  wire       [4:0]
        .rs2_i  (IfId_rs2),    // input  wire       [4:0]
        .xrs1_o (Id_xrs1),     // output wire [`XLEN-1:0]
        .xrs2_o (Id_xrs2),     // output wire [`XLEN-1:0]
        .we_i   (Wb_xreg_we && !w_stall),  // input  wire
        .rd_i   (MaWb_rd),     // input  wire       [4:0]
        .wdata_i(MaWb_rslt)    // input  wire [`XLEN-1:0]
    );

    // data forwarding
    wire Id_rs1_fwd_Ma_to_Ex = IdEx_v && IdEx_rf_we && (IdEx_rd == IfId_rs1);
    wire Id_rs2_fwd_Ma_to_Ex = IdEx_v && IdEx_rf_we && (IdEx_rd == IfId_rs2);
    wire Id_rs1_fwd_Wb_to_Ex = ExMa_v && ExMa_rf_we && (ExMa_rd == IfId_rs1);
    wire Id_rs2_fwd_Wb_to_Ex = ExMa_v && ExMa_rf_we && (ExMa_rd == IfId_rs2);

    wire [`XLEN-1:0] Id_pc_in = (Id_src2_ctrl[`SRC2_CTRL_USE_AUIPC]) ? IfId_pc : 0;
    wire Id_use_imm = Id_src2_ctrl[`SRC2_CTRL_USE_AUIPC] | Id_src2_ctrl[`SRC2_CTRL_USE_IMM];

    // source select
    wire [`XLEN-1:0] Id_src1 = (Id_rs1_fwd_Wb_to_Ex) ? Ma_rslt : Id_xrs1;
    wire [`XLEN-1:0] Id_src2 = (Id_rs2_fwd_Wb_to_Ex) ? Ma_rslt :
                               (Id_use_imm) ? Id_pc_in+Id_imm  : Id_xrs2 ;

    wire [`XLEN-1:0] Id_j_pc4 = (Id_bru_ctrl[`BRU_CTRL_IS_JAL_JALR]) ? IfId_pc + 4 : 0;

    always @(posedge clk_i) if (!w_stall) begin
        if (rst) begin
            IdEx_v  <= 0;
            IdEx_pc <= 0;
            IdEx_ir <= `NOP;
        end else if (!ExMa_stall) begin
            IdEx_v                <= Id_v;
            IdEx_pc               <= IfId_pc;
            IdEx_j_pc4            <= Id_j_pc4;
            IdEx_ir               <= IfId_ir;
            IdEx_br_pred_tkn      <= IfId_br_pred_tkn;
            IdEx_pat_hist         <= IfId_pat_hist;
            IdEx_alu_ctrl         <= Id_alu_ctrl;
            IdEx_bru_ctrl         <= Id_bru_ctrl;
            IdEx_lsu_ctrl         <= Id_lsu_ctrl;
            IdEx_mul_ctrl         <= Id_mul_ctrl;
            IdEx_div_ctrl         <= Id_div_ctrl;
            IdEx_rs1_fwd_Ma_to_Ex <= Id_rs1_fwd_Ma_to_Ex;
            IdEx_rs2_fwd_Ma_to_Ex <= Id_rs2_fwd_Ma_to_Ex;
            IdEx_src1             <= Id_src1;
            IdEx_src2             <= Id_src2;
            IdEx_imm              <= Id_imm;
            IdEx_rf_we            <= IfId_rf_we;
            IdEx_rd               <= IfId_rd;
            IdEx_cfu_ctrl         <= Id_cfu_ctrl;  // Note
        end
    end

//------------------------------------------------------------------------------
// EX: Execution
//------------------------------------------------------------------------------
    wire Ex_valid = IdEx_v && !Ma_br_misp && !ExMa_stall;

    ///// data forwarding
    wire [`XLEN-1:0] Ex_src1 = (IdEx_rs1_fwd_Ma_to_Ex) ? ExMa_rslt : IdEx_src1;
    wire [`XLEN-1:0] Ex_src2 = (IdEx_rs2_fwd_Ma_to_Ex) ? ExMa_rslt : IdEx_src2;

    ///// arithmetic logic unit
    wire [`XLEN-1:0] Ex_alu_rslt;
    alu alu (
        .alu_ctrl_i(IdEx_alu_ctrl),  // input  wire [`ALU_CTRL_WIDTH-1:0]
        .src1_i    (Ex_src1),        // input  wire           [`XLEN-1:0]
        .src2_i    (Ex_src2),        // input  wire           [`XLEN-1:0]
        .j_pc4_i   (IdEx_j_pc4),     // input  wire           [`XLEN-1:0]
        .rslt_o    (Ex_alu_rslt)     // output wire           [`XLEN-1:0]
    );

    ///// branch resolution unit
    wire             Ex_is_ctrl_tsfr;
    wire             Ex_br_tkn;
    wire             Ex_br_misp_rslt1;
    wire             Ex_br_misp_rslt2;
    wire [`XLEN-1:0] Ex_br_tkn_pc;
    bru bru (
        .bru_ctrl_i     (IdEx_bru_ctrl),     // input  wire [`BRU_CTRL_WIDTH-1:0]
        .src1_i         (Ex_src1),           // input  wire           [`XLEN-1:0]
        .src2_i         (Ex_src2),           // input  wire           [`XLEN-1:0]
        .pc_i           (IdEx_pc),           // input  wire           [`XLEN-1:0]
        .imm_i          (IdEx_imm),          // input  wire           [`XLEN-1:0]
        .npc_i          (IfId_pc),           // input  wire           [`XLEN-1:0]
        .br_pred_tkn_i  (IdEx_br_pred_tkn),  // input  wire
        .is_ctrl_tsfr_o (Ex_is_ctrl_tsfr),   // output wire
        .br_tkn_o       (Ex_br_tkn),         // output wire
        .br_misp_rslt1_o(Ex_br_misp_rslt1),  // output wire
        .br_misp_rslt2_o(Ex_br_misp_rslt2),  // output wire
        .br_tkn_pc_o    (Ex_br_tkn_pc)       // output wire           [`XLEN-1:0]
    );

    ///// store unit
    wire [         `XLEN-1:0] dbus_addr = dbus_addr_o;  // for simulation
    wire [         `XLEN-1:0] dbus_wdata = dbus_wdata_o;  // for simulation
    wire [`DBUS_OFFSET_W-1:0] dbus_offset;  // Note
    store_unit store_unit (
        .valid_i      (Ex_valid && !w_stall), // input  wire
        .lsu_ctrl_i   (IdEx_lsu_ctrl),  // input  wire [`LSU_CTRL_WIDTH-1:0]
        .src1_i       (Ex_src1),        // input  wire           [`XLEN-1:0]
        .src2_i       (Ex_src2),        // input  wire           [`XLEN-1:0]
        .imm_i        (IdEx_imm),       // input  wire           [`XLEN-1:0]
        .dbus_addr_o  (dbus_addr_o),    // output wire           [`XLEN-1:0]
        .dbus_offset_o(dbus_offset),    // output wire    [OFFSET_WIDTH-1:0]
        .dbus_wvalid_o(dbus_wvalid_o),  // output wire
        .dbus_wdata_o (dbus_wdata_o),   // output wire           [`XLEN-1:0]
        .dbus_wstrb_o (dbus_wstrb_o)    // output wire         [`XBYTES-1:0]
    );

    ///// multiplier unit
    wire             Ex_mul_stall;
    wire [`XLEN-1:0] Ex_mul_rslt;
    multiplier multiplier (
        .clk_i     (clk_i),          // input  wire
        .rst_i     (rst),            // input  wire // Note
        .stall_i   (w_stall),        // input  wire
        .valid_i   (Ex_valid),       // input  wire
        .mul_ctrl_i(IdEx_mul_ctrl),  // input  wire [`MUL_CTRL_WIDTH-1:0]
        .src1_i    (Ex_src1),        // input  wire           [`XLEN-1:0]
        .src2_i    (Ex_src2),        // input  wire           [`XLEN-1:0]
        .stall_o   (Ex_mul_stall),   // output wire
        .rslt_o    (Ex_mul_rslt)     // output wire           [`XLEN-1:0]
    );

    ///// divider unit
    wire             Ex_div_stall;
    wire [`XLEN-1:0] Ex_div_rslt;
    divider divider (
        .clk_i     (clk_i),          // input  wire
        .rst_i     (rst),            // input  wire
        .stall_i   (w_stall),        // input  wire // Note
        .valid_i   (Ex_valid),       // input  wire
        .div_ctrl_i(IdEx_div_ctrl),  // input  wire [`DIV_CTRL_WIDTH-1:0]
        .src1_i    (Ex_src1),        // input  wire           [`XLEN-1:0]
        .src2_i    (Ex_src2),        // input  wire           [`XLEN-1:0]
        .stall_o   (Ex_div_stall),   // output wire
        .rslt_o    (Ex_div_rslt)     // output wire           [`XLEN-1:0]
    );

    ///// custom function unit
    wire             Ex_cfu_en = IdEx_cfu_ctrl[0] & Ex_valid;
    wire             Ex_cfu_stall;
    wire [`XLEN-1:0] Ex_cfu_rslt;
    cfu cfu (
        .clk_i   (clk_i),                // input  wire
        .en_i    (Ex_cfu_en),            // input  wire
        .funct3_i(IdEx_cfu_ctrl[3:1]),   // input  wire [ 2:0]
        .funct7_i(IdEx_cfu_ctrl[10:4]),  // input  wire [ 6:0]
        .src1_i  (Ex_src1),              // input  wire [`XLEN-1:0]
        .src2_i  (Ex_src2),              // input  wire [`XLEN-1:0]
        .stall_o (Ex_cfu_stall),         // output wire
        .rslt_o  (Ex_cfu_rslt)           // output wire [`XLEN-1:0]
    );

    always @(posedge clk_i) if (!w_stall) begin
        ExMa_mul_stall <= Ex_mul_stall;
        ExMa_div_stall <= Ex_div_stall;
        ExMa_stall     <= Ex_mul_stall | Ex_div_stall | Ex_cfu_stall;
        ExMa_mdc_rslt  <= Ex_mul_rslt | Ex_div_rslt | Ex_cfu_rslt;
        if (rst) begin
            ExMa_v  <= 0;
            ExMa_pc <= 0;
            ExMa_ir <= `NOP;
        end else if (!ExMa_stall) begin
            ExMa_v             <= Ex_v;
            ExMa_pc            <= IdEx_pc;
            ExMa_ir            <= IdEx_ir;
            ExMa_pat_hist      <= IdEx_pat_hist;
            ExMa_is_ctrl_tsfr  <= Ex_is_ctrl_tsfr;
            ExMa_br_tkn        <= Ex_br_tkn;
            ExMa_br_misp_rslt1 <= Ex_br_misp_rslt1;
            ExMa_br_misp_rslt2 <= Ex_br_misp_rslt2;
            ExMa_br_tkn_pc     <= Ex_br_tkn_pc;
            ExMa_lsu_ctrl      <= IdEx_lsu_ctrl;
            ExMa_dbus_offset   <= dbus_offset;
            ExMa_rf_we         <= IdEx_rf_we;
            ExMa_rd            <= IdEx_rd;
            ExMa_rslt          <= Ex_alu_rslt;
            ExMa_j_b_insn      <= IdEx_bru_ctrl[0] & Ex_v;
        end
    end

//------------------------------------------------------------------------------
// MA: Memory Access
//------------------------------------------------------------------------------
    // load unit
    wire [`XLEN-1:0] Ma_load_rslt;
    load_unit load_unit (
        .lsu_ctrl_i   (ExMa_lsu_ctrl),     // input  wire [`LSU_CTRL_WIDTH-1:0]
        .dbus_offset_i(ExMa_dbus_offset),  // input  wire    [OFFSET_WIDTH-1:0]
        .dbus_rdata_i (dbus_rdata_i),      // input  wire           [`XLEN-1:0]
        .rslt_o       (Ma_load_rslt)       // output wire           [`XLEN-1:0]
    );

    wire [`XLEN-1:0] Ma_rslt = ExMa_rslt | ExMa_mdc_rslt | Ma_load_rslt;

    always @(posedge clk_i) if (!w_stall) begin
        if (rst) begin
            MaWb_v  <= 0;
            MaWb_pc <= 0;
            MaWb_ir <= `NOP;
        end else if (!ExMa_stall) begin
            MaWb_v     <= Ma_v;
            MaWb_pc    <= ExMa_pc;
            MaWb_ir    <= ExMa_ir;
            MaWb_rf_we <= ExMa_rf_we;
            MaWb_rd    <= ExMa_rd;
            MaWb_rslt  <= Ma_rslt;
        end
    end

//------------------------------------------------------------------------------
// WB: Write Back
//------------------------------------------------------------------------------
endmodule

`define BTB_IDXW $clog2(`BTB_ENTRY)  // BTB index width
`define BTB_OSTW $clog2(`XBYTES)     // BTB offset width
/******************************************************************************************/
module bimodal (
    input  wire             clk_i,
    input  wire             rst_i,
    input  wire             stall_i,
    input  wire [     31:0] raddr_i,
    output wire [      1:0] pat_hist_o,
    output wire             br_pred_tkn_o,
    output wire [`PC_W-1:0] br_pred_pc_o,
    input  wire             br_tkn_i,
    input  wire             br_tsfr_i,
    input  wire [     31:0] waddr_i,
    input  wire [      1:0] pat_hist_i,
    input  wire [     31:0] br_tkn_pc_i
);

    integer i;
    (* ram_style = "block" *) reg [`PC_W-1:0] btb[0:`BTB_ENTRY-1];  // BTB, branch target buf
    initial for (i = 0; i < `BTB_ENTRY; i = i + 1) btb[i] = 0;  // init with weak untaken

    wire [1:0] w_cnt = (br_tkn_i) ? pat_hist_i + (pat_hist_i < 3) : pat_hist_i - (pat_hist_i > 0);
    wire [`BTB_IDXW-1:0] btb_ridx = raddr_i[`BTB_IDXW+`BTB_OSTW-1:`BTB_OSTW];
    wire [`BTB_IDXW-1:0] btb_widx = waddr_i[`BTB_IDXW+`BTB_OSTW-1:`BTB_OSTW];

    reg [31:0] r_btb_entry;
    always @(posedge clk_i) if (!stall_i) begin
        r_btb_entry <= btb[btb_ridx];
        if (br_tsfr_i) begin
            btb[btb_widx] <= {br_tkn_pc_i[`PC_W-1:2], w_cnt};  // lower tow bits for counter
        end
    end

    assign pat_hist_o    = r_btb_entry[1:0];
    assign br_pred_tkn_o = r_btb_entry[1];
    assign br_pred_pc_o  = {r_btb_entry[`PC_W-1:2], 2'b0};
endmodule

/******************************************************************************************/
module pre_decoder (
    input  wire [31:0] ir_i,
    output wire [ 2:0] instr_type_o,
    output wire        rf_we_o,
    output wire [ 4:0] rd_o,
    output wire [ 4:0] rs1_o,
    output wire [ 4:0] rs2_o
);

    wire [4:0] opcode = ir_i[6:2];
    assign instr_type_o = (opcode == 5'b01101) ? `U_TYPE :  // LUI
        (opcode == 5'b00101) ? `U_TYPE :  // AUIPC
        (opcode == 5'b11011) ? `J_TYPE :  // JAL
        (opcode == 5'b11001) ? `I_TYPE :  // JALR
        (opcode == 5'b11000) ? `B_TYPE :  // BRANCH
        (opcode == 5'b00000) ? `I_TYPE :  // LOAD
        (opcode == 5'b01000) ? `S_TYPE :  // STORE
        (opcode == 5'b00100) ? `I_TYPE :  // OP-IMM
`ifdef RV64
        (opcode == 5'b00110) ? `I_TYPE :  // OP-IMM-32
`endif
        (opcode == 5'b01100) ? `R_TYPE :  // OP
`ifdef RV64
        (opcode == 5'b01110) ? `R_TYPE :  // OP-32
`endif
        (opcode == 5'b00010) ? `R_TYPE : `NONE_TYPE;  // CUSTOM-0 : NONE

    assign rd_o = ((instr_type_o == `S_TYPE) | (instr_type_o == `B_TYPE)) ? 0 : ir_i[11:7];
    assign rs1_o = ((instr_type_o == `U_TYPE) | (instr_type_o == `J_TYPE)) ? 0 : ir_i[19:15];
    assign rs2_o = ((instr_type_o==`I_TYPE) |
                    (instr_type_o==`U_TYPE) | (instr_type_o==`J_TYPE)) ? 0 : ir_i[24:20];
    assign rf_we_o = (rd_o != 0);
endmodule

/******************************************************************************************/
module regfile (  ///// register file with bypassing
    input  wire        clk_i,
    input  wire [ 4:0] rs1_i,
    input  wire [ 4:0] rs2_i,
    output wire [`XLEN-1:0] xrs1_o,
    output wire [`XLEN-1:0] xrs2_o,
    input  wire        we_i,
    input  wire [ 4:0] rd_i,
    input  wire [`XLEN-1:0] wdata_i
);

    reg [`XLEN-1:0] ram[0:31];

    assign xrs1_o = (rs1_i == 0) ? 0 : (we_i && rs1_i == rd_i) ? wdata_i : ram[rs1_i];
    assign xrs2_o = (rs2_i == 0) ? 0 : (we_i && rs2_i == rd_i) ? wdata_i : ram[rs2_i];
    always @(posedge clk_i) begin
        if (we_i) begin
            ram[rd_i] <= wdata_i;
        end
    end
endmodule

/******************************************************************************************/
module alu (
    input  wire [`ALU_CTRL_WIDTH-1:0] alu_ctrl_i,
    input  wire           [`XLEN-1:0] src1_i    ,
    input  wire           [`XLEN-1:0] src2_i    ,
    input  wire           [`XLEN-1:0] j_pc4_i   ,
    output wire           [`XLEN-1:0] rslt_o
);

    wire w_signed = alu_ctrl_i[`ALU_CTRL_IS_SIGNED];
    wire w_neg    = alu_ctrl_i[`ALU_CTRL_IS_NEG];
    wire w_less   = alu_ctrl_i[`ALU_CTRL_IS_LESS];
`ifdef RV64
    wire w_is_w   = alu_ctrl_i[`ALU_CTRL_IS_W];
`endif

    wire [`XLEN+1:0] adder_src1   = {w_signed && src1_i[`XLEN-1], src1_i, 1'b1};
    wire [`XLEN+1:0] adder_src2   = {w_signed && src2_i[`XLEN-1], src2_i, 1'b0} ^ {(`XLEN+2){w_neg}};
    wire [`XLEN+1:0] adder_rslt_t = adder_src1+adder_src2;
    wire        less_rslt    = w_less && adder_rslt_t[`XLEN+1];
    wire [`XLEN-1:0] adder_rslt   = (alu_ctrl_i[`ALU_CTRL_IS_ADD]) ? adder_rslt_t[`XLEN:1] : 0;

`ifdef RV64
    wire [31:0] src1_32 = src1_i[31:0];
    wire [ 4:0] shamt_32 = src2_i[4:0];
    wire [31:0] left_shift_32 = src1_32 << shamt_32;
    wire signed [32:0] right_shifter_src1_32 = {w_signed && src1_32[31], src1_32};
    wire [32:0] arith_shift_32_tmp = right_shifter_src1_32 >>> shamt_32;
    wire [31:0] right_shift_32 = arith_shift_32_tmp[31:0];
`endif

    wire signed  [`XLEN:0] right_shifter_src1 = {w_signed && src1_i[`XLEN-1], src1_i};
    wire  [$clog2(`XLEN)-1:0] shamt              = src2_i[$clog2(`XLEN)-1:0];
`ifdef RV64
    wire [`XLEN:0] arith_shift_64_tmp = right_shifter_src1 >>> shamt;
    wire [`XLEN-1:0] left_shifter_rslt  = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_LEFT] ) ?
                                     (w_is_w ? {32'b0, left_shift_32} : src1_i << shamt) : 0;
    wire [`XLEN-1:0] right_shifter_rslt = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_RIGHT]) ?
                                     (w_is_w ? {32'b0, right_shift_32} : arith_shift_64_tmp[`XLEN-1:0]) : 0;
`else
    wire [`XLEN-1:0] left_shifter_rslt  = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_LEFT] ) ?
                                     src1_i <<  shamt : 0;
    wire [`XLEN-1:0] right_shifter_rslt = (alu_ctrl_i[`ALU_CTRL_IS_SHIFT_RIGHT]) ?
                                     right_shifter_src1 >>> shamt : 0;
`endif

    wire [`XLEN-1:0] bitwise_rslt       = ((alu_ctrl_i[`ALU_CTRL_IS_XOR_OR]) ?
                                     (src1_i ^ src2_i) : 0) |
                                     ((alu_ctrl_i[`ALU_CTRL_IS_OR_AND])
                                      ? (src1_i & src2_i) : 0);
    wire [`XLEN-1:0] lui_auipc_rslt     = (alu_ctrl_i[`ALU_CTRL_IS_SRC2]) ? src2_i : 0;

    wire [`XLEN-1:0] rslt_t = less_rslt | adder_rslt | left_shifter_rslt | right_shifter_rslt |
                              bitwise_rslt | lui_auipc_rslt | j_pc4_i;

`ifdef RV64
    assign rslt_o = w_is_w ? {{32{rslt_t[31]}}, rslt_t[31:0]} : rslt_t;
`else
    assign rslt_o = rslt_t;
`endif
endmodule

/******************************************************************************************/
module bru (
    input  wire [`BRU_CTRL_WIDTH-1:0] bru_ctrl_i,
    input  wire [          `XLEN-1:0] src1_i,
    input  wire [          `XLEN-1:0] src2_i,
    input  wire [          `XLEN-1:0] pc_i,
    input  wire [          `XLEN-1:0] imm_i,
    input  wire [          `XLEN-1:0] npc_i,
    input  wire                       br_pred_tkn_i,
    output wire                       is_ctrl_tsfr_o,
    output wire                       br_tkn_o,
    output wire                       br_misp_rslt1_o,
    output wire                       br_misp_rslt2_o,
    output wire [          `XLEN-1:0] br_tkn_pc_o
);

    wire signed [`XLEN:0] sext_src1 = {bru_ctrl_i[`BRU_CTRL_IS_SIGNED] && src1_i[`XLEN-1], src1_i};
    wire signed [`XLEN:0] sext_src2 = {bru_ctrl_i[`BRU_CTRL_IS_SIGNED] && src2_i[`XLEN-1], src2_i};

    wire               w_eq = (src1_i == src2_i);  // equal
    wire               w_lt = (sext_src1 < sext_src2);  // less than

    assign br_tkn_o = bru_ctrl_i[`BRU_CTRL_IS_JAL_JALR] |
                     (bru_ctrl_i[`BRU_CTRL_IS_BEQ] &  w_eq) |
                     (bru_ctrl_i[`BRU_CTRL_IS_BNE] & !w_eq) |
                     (bru_ctrl_i[`BRU_CTRL_IS_BLT] &  w_lt) |
                     (bru_ctrl_i[`BRU_CTRL_IS_BGE] & !w_lt);

    wire [`XLEN-1:0] br_tkn_pc_t;
    assign br_tkn_pc_t     = ((bru_ctrl_i[`BRU_CTRL_IS_JALR]) ? src1_i : pc_i) + imm_i;
    assign br_tkn_pc_o     = {br_tkn_pc_t[`XLEN-1:1], 1'b0};

    assign is_ctrl_tsfr_o  = (bru_ctrl_i[`BRU_CTRL_IS_CTRL_TSFR] || br_pred_tkn_i);

    assign br_misp_rslt1_o = (npc_i != br_tkn_pc_o);
    assign br_misp_rslt2_o = (npc_i != (pc_i + 'h4));
endmodule

`define DIV_IDLE 0
`define DIV_CHECK 1
`define DIV_EXEC 2
`define DIV_RET 3
module divider (
    input  wire        clk_i      ,
    input  wire        rst_i      ,
    input  wire        stall_i    ,
    input  wire        valid_i    ,
    input  wire [`DIV_CTRL_WIDTH-1:0] div_ctrl_i ,
    input  wire [`XLEN-1:0] src1_i     ,
    input  wire [`XLEN-1:0] src2_i     ,
    output wire        stall_o    ,
    output wire [`XLEN-1:0] rslt_o
);

    reg [1:0] state = `DIV_IDLE;
    assign stall_o = (w_state!=`DIV_IDLE);

    reg        is_dividend_neg;
    reg        is_divisor_neg;
    reg [`XLEN-1:0] remainder;
    reg [`XLEN-1:0] divisor;
    reg [`XLEN-1:0] quotient;
    reg        is_div_rslt_neg;
    reg        is_rem_rslt_neg;
    reg        is_rem;
`ifdef RV64
    reg        is_w;
`endif
    reg  [$clog2(`XLEN)-1:0] cntr;

    wire [`XLEN-1:0] uintx_remainder = (is_dividend_neg) ? ~remainder+1 : remainder;
    wire [`XLEN-1:0] uintx_divisor   = (is_divisor_neg ) ? ~divisor+1   : divisor;
    wire [`XLEN:0] difference      = {remainder[`XLEN-2:0], quotient[`XLEN-1]} - divisor;
    wire        q               = !difference[`XLEN];

`ifdef RV64
    wire [`XLEN-1:0] raw_rslt = (is_rem) ? ((is_rem_rslt_neg) ? ~remainder+1 : remainder) :
                                      ((is_div_rslt_neg) ? ~quotient+1  : quotient ) ;
    assign rslt_o = (state!=`DIV_RET) ? 0 :
                    (is_w) ? {{32{raw_rslt[31]}}, raw_rslt[31:0]} : raw_rslt;
`else
    assign rslt_o = (state!=`DIV_RET) ? 0 :
                    (is_rem) ? ((is_rem_rslt_neg) ? ~remainder+1 : remainder) :
                    ((is_div_rslt_neg) ? ~quotient+1  : quotient ) ;
`endif

    wire w_div    = div_ctrl_i[`DIV_CTRL_IS_DIV];
    wire w_signed = div_ctrl_i[`DIV_CTRL_IS_SIGNED];
`ifdef RV64
    wire w_is_w   = div_ctrl_i[`DIV_CTRL_IS_W];
    wire [`XLEN-1:0] s1 = (w_is_w) ? (w_signed ? {{32{src1_i[31]}}, src1_i[31:0]} : {32'd0, src1_i[31:0]}) : src1_i;
    wire [`XLEN-1:0] s2 = (w_is_w) ? (w_signed ? {{32{src2_i[31]}}, src2_i[31:0]} : {32'd0, src2_i[31:0]}) : src2_i;
`else
    wire [`XLEN-1:0] s1 = src1_i;
    wire [`XLEN-1:0] s2 = src2_i;
`endif

    wire [1:0] w_state = (w_init) ? `DIV_CHECK :
                         (state==`DIV_CHECK && divisor==0) ? `DIV_RET : // Note
                         (state==`DIV_CHECK && divisor!=0) ? `DIV_EXEC :
                         (state==`DIV_EXEC  && cntr==0) ? `DIV_RET :
                         (state==`DIV_EXEC  && cntr!=0) ? `DIV_EXEC : `DIV_IDLE;

    wire w_init = (state==`DIV_IDLE && valid_i && w_div);
    always @(posedge clk_i) if (!stall_i) begin
        if (rst_i) begin
            state <= `DIV_IDLE;
        end else begin
            is_rem            <= (w_init) ? div_ctrl_i[`DIV_CTRL_IS_REM] : is_rem;
`ifdef RV64
            is_w              <= (w_init) ? w_is_w : is_w;
`endif
            is_dividend_neg   <= (w_init) ? w_signed && s1[`XLEN-1] : is_dividend_neg;
            is_divisor_neg    <= (w_init) ? w_signed && s2[`XLEN-1] : is_divisor_neg;
            is_div_rslt_neg   <= (w_init) ? w_signed && (s1[`XLEN-1] ^ s2[`XLEN-1]) :
                                 (state==`DIV_CHECK && divisor==0) ? 0 : is_div_rslt_neg;
            is_rem_rslt_neg   <= (w_init) ? w_signed &&  s1[`XLEN-1] :
                                 (state==`DIV_CHECK && divisor==0) ? 0 : is_rem_rslt_neg;

            divisor <= (w_init) ? s2 :
                       (state==`DIV_CHECK && divisor!=0) ? uintx_divisor : divisor;

            {remainder, quotient} <= (w_init) ? {s1, {`XLEN{1'b0}}} :
                       (state==`DIV_CHECK && divisor==0) ? {remainder, {`XLEN{1'b1}}} :
                       (state==`DIV_CHECK && divisor!=0) ? {{`XLEN{1'b0}}, uintx_remainder} :
                       (state==`DIV_EXEC) ? ((q) ? {difference[`XLEN-1:0], quotient[`XLEN-2:0], 1'b1} :
                                                   {remainder[`XLEN-2:0], quotient, 1'b0}) :
                       {remainder, quotient};

            cntr <= (state==`DIV_CHECK) ? `XLEN-1 : (state==`DIV_EXEC) ?  cntr-1 : cntr;
            state <= w_state;
        end
    end
endmodule

`ifdef RV64
`define MUL_IDLE   0
`define MUL_EXEC_0 1
`define MUL_EXEC_1 2
`define MUL_EXEC_2 3
`define MUL_EXEC_3 4
`define MUL_RET    5
`else
`define MUL_IDLE 0
`define MUL_EXEC 1
`define MUL_RET 2
`endif
/******************************************************************************************/
module multiplier (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        stall_i,
    input  wire        valid_i,
    input  wire [`MUL_CTRL_WIDTH-1:0] mul_ctrl_i,
    input  wire [`XLEN-1:0] src1_i,
    input  wire [`XLEN-1:0] src2_i,
    output wire        stall_o,
    output wire [`XLEN-1:0] rslt_o
);
`ifdef RV64
    parameter PIPE = 4; // Pipeline depth

    wire w_mul         = mul_ctrl_i[`MUL_CTRL_IS_MUL];
    wire w_src1_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC1_SIGNED];
    wire w_src2_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC2_SIGNED];
    wire w_is_high     = mul_ctrl_i[`MUL_CTRL_IS_HIGH];
    wire w_is_w        = mul_ctrl_i[`MUL_CTRL_IS_W];

    // Pre-process inputs (Sign/Zero extension for W instructions)
    wire [`XLEN-1:0] a_op = w_is_w ? { {32{w_src1_signed & src1_i[31]}}, src1_i[31:0] } : src1_i;
    wire [`XLEN-1:0] b_op = w_is_w ? { {32{w_src2_signed & src2_i[31]}}, src2_i[31:0] } : src2_i;

    // Expand to 65 bits for signed multiplication
    wire signed [`XLEN:0] mul_a = { w_src1_signed & a_op[(`XLEN-1)], a_op };
    wire signed [`XLEN:0] mul_b = { w_src2_signed & b_op[(`XLEN-1)], b_op };

    // Pipelined multiplier registers
    (* srl_style = "register" *) reg signed [129:0] prod_pipe [PIPE-1:0];
    reg [PIPE-1:0] is_w_pipe;
    reg [PIPE-1:0] is_high_pipe;
    
    reg [3:0] count = 0;
    integer i;

    always @(posedge clk_i) begin
        if (rst_i) begin
            count <= 0;
            is_w_pipe <= 0;
            is_high_pipe <= 0;
            for (i = 0; i < PIPE; i = i + 1) prod_pipe[i] <= 0;
        end else if (!stall_i) begin
            if (valid_i && w_mul && count == 0) begin
                count <= PIPE;
            end else if (count > 0) begin
                count <= count - 1;
            end

            prod_pipe[0] <= mul_a * mul_b;
            is_w_pipe    <= {is_w_pipe[PIPE-2:0], w_is_w};
            is_high_pipe <= {is_high_pipe[PIPE-2:0], w_is_high};

            for (i = 1; i < PIPE; i = i + 1) begin
                prod_pipe[i] <= prod_pipe[i-1];
            end
        end
    end

    // stall_o is HIGH when we need to stall the CPU.
    assign stall_o = (valid_i && w_mul && count == 0) || (count > 1);

    // Output formatting
    wire [129:0] product     = prod_pipe[PIPE-1];
    wire         out_is_w    = is_w_pipe[PIPE-1];
    wire         out_is_high = is_high_pipe[PIPE-1];
    wire [31:0]  rslt_32     = product[31:0];

    assign rslt_o = (count != 1) ? 0 : 
                    (out_is_w) ? {{32{rslt_32[31]}}, rslt_32} :
                    (out_is_high) ? product[2*`XLEN-1:`XLEN] : product[`XLEN-1:0];
`else
    reg        [ 1:0] state = `MUL_IDLE;
    reg signed [`XLEN:0] r_multiplicand;  // XLEN+1 bit
    reg signed [`XLEN:0] r_multiplier;  // XLEN+1 bit
    reg        [2*`XLEN-1:0] product;  // 2*XLEN bit
    reg               is_high;  //

    assign rslt_o = (state != `MUL_RET) ? 0 : (is_high) ? product[2*`XLEN-1:`XLEN] : product[`XLEN-1:0];

    wire w_mul = mul_ctrl_i[`MUL_CTRL_IS_MUL];
    wire w_src1_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC1_SIGNED];
    wire w_src2_signed = mul_ctrl_i[`MUL_CTRL_IS_SRC2_SIGNED];
    wire w_is_high = mul_ctrl_i[`MUL_CTRL_IS_HIGH];
    wire [1:0] w_state = (state==`MUL_IDLE && valid_i && w_mul) ? `MUL_EXEC :
                         (state==`MUL_EXEC) ? `MUL_RET : `MUL_IDLE;

    always @(posedge clk_i) if (!stall_i) begin
        if (rst_i) begin
            state <= `MUL_IDLE;
        end else if (!stall_i) begin
            if (state == `MUL_IDLE) r_multiplicand <= {w_src1_signed && src1_i[`XLEN-1], src1_i};
            if (state == `MUL_IDLE) r_multiplier <= {w_src2_signed && src2_i[`XLEN-1], src2_i};
            if (state == `MUL_IDLE) is_high <= w_is_high;
            if (state == `MUL_EXEC) product <= r_multiplicand * r_multiplier;
            state <= w_state;
        end
    end
    assign stall_o = (w_state != `MUL_IDLE);
`endif
endmodule

/******************************************************************************************/
module store_unit (
    input  wire        valid_i,
    input  wire [`LSU_CTRL_WIDTH-1:0] lsu_ctrl_i,
    input  wire [`XLEN-1:0] src1_i,
    input  wire [`XLEN-1:0] src2_i,
    input  wire [`XLEN-1:0] imm_i,
    output wire [`XLEN-1:0] dbus_addr_o,
`ifdef RV64
    output wire [ 2:0] dbus_offset_o,
`else
    output wire [ 1:0] dbus_offset_o,
`endif
    output wire        dbus_wvalid_o,
    output wire [`XLEN-1:0] dbus_wdata_o,
`ifdef RV64
    output wire [ 7:0] dbus_wstrb_o
`else
    output wire [ 3:0] dbus_wstrb_o
`endif
);

    assign dbus_addr_o   = (valid_i && (lsu_ctrl_i[`LSU_CTRL_IS_STORE] ||
                                        lsu_ctrl_i[`LSU_CTRL_IS_LOAD])) ? src1_i + imm_i : 0;
`ifdef RV64
    assign dbus_offset_o = dbus_addr_o[2:0];
`else
    assign dbus_offset_o = dbus_addr_o[1:0];
`endif
    assign dbus_wvalid_o = valid_i && lsu_ctrl_i[`LSU_CTRL_IS_STORE];

    wire w_sb = lsu_ctrl_i[`LSU_CTRL_IS_BYTE];
    wire w_sh = lsu_ctrl_i[`LSU_CTRL_IS_HALFWORD];
    wire w_sw = lsu_ctrl_i[`LSU_CTRL_IS_WORD];

`ifdef RV64
    assign dbus_wdata_o = (w_sb) ? {8{src2_i[7:0]}} :
                          (w_sh) ? {4{src2_i[15:0]}} :
                          (w_sw) ? {2{src2_i[31:0]}} : src2_i[`XLEN-1:0];
    wire [`XBYTES-1:0] mask = (w_sb) ? 1 : (w_sh) ? 3 : (w_sw) ? 15 : {`XBYTES{1'b1}};
    assign dbus_wstrb_o = mask << dbus_offset_o;
`else
    assign dbus_wdata_o[7:0]   = src2_i[7:0];
    assign dbus_wdata_o[15:8]  = (w_sb) ? src2_i[7:0] : src2_i[15:8];
    assign dbus_wdata_o[23:16] = (w_sw) ? src2_i[23:16] : src2_i[7:0];
    assign dbus_wdata_o[31:24] = (w_sb) ? src2_i[7:0] : (w_sh) ? src2_i[15:8] : src2_i[31:24];

    assign dbus_wstrb_o[0] = (w_sb && dbus_offset_o==0) || (w_sh && dbus_offset_o[1]==0) || w_sw;
    assign dbus_wstrb_o[1] = (w_sb && dbus_offset_o==1) || (w_sh && dbus_offset_o[1]==0) || w_sw;
    assign dbus_wstrb_o[2] = (w_sb && dbus_offset_o==2) || (w_sh && dbus_offset_o[1]==1) || w_sw;
    assign dbus_wstrb_o[3] = (w_sb && dbus_offset_o==3) || (w_sh && dbus_offset_o[1]==1) || w_sw;
`endif
endmodule

/******************************************************************************************/
module load_unit (
    input  wire [`LSU_CTRL_WIDTH-1:0] lsu_ctrl_i,
`ifdef RV64
    input  wire [ 2:0] dbus_offset_i,
`else
    input  wire [ 1:0] dbus_offset_i,
`endif
    input  wire [`XLEN-1:0] dbus_rdata_i,
    output wire [`XLEN-1:0] rslt_o
);

    wire w_lb = lsu_ctrl_i[`LSU_CTRL_IS_BYTE];
    wire w_lh = lsu_ctrl_i[`LSU_CTRL_IS_HALFWORD];
    wire w_lw = lsu_ctrl_i[`LSU_CTRL_IS_WORD];
    wire w_signed = lsu_ctrl_i[`LSU_CTRL_IS_SIGNED];
    wire w_load = lsu_ctrl_i[`LSU_CTRL_IS_LOAD];

`ifdef RV64
    wire [`XLEN-1:0] d_shifted = dbus_rdata_i >> {dbus_offset_i, 3'b0};
    wire [7:0] b = d_shifted[7:0];
    wire [15:0] h = d_shifted[15:0];
    wire [31:0] w = d_shifted[31:0];

    assign rslt_o = (!w_load) ? 0 :
                    (w_lb) ? {{(`XLEN-8){w_signed & b[7]}}, b} :
                    (w_lh) ? {{(`XLEN-16){w_signed & h[15]}}, h} :
                    (w_lw) ? {{(`XLEN-32){w_signed & w[31]}}, w} :
                    d_shifted;
`else
    wire [1:0] ost = dbus_offset_i;  // offset
    wire [`XLEN-1:0] d = dbus_rdata_i;  // data

    wire w_lb_sign = w_lb & ((ost==0) ? d[7] : (ost==1) ? d[15] :(ost==2) ? d[23] : d[31]) & w_signed;
    wire w_lh_sign = w_lh & ((ost[1] == 0) ? d[15] : d[31]) & w_signed;

    wire [7:0] w1, w2, w3, w4;
    assign w1   = (w_load==0) ? 0 : (w_lw || (w_lh & ost[1]==0) || (w_lb & ost==0)) ? d[7:0] :
                           (w_lb && ost==1) ? d[15:8] : ((w_lb && ost==2) ||
                           (w_lh && ost[1]==1)) ? d[23:16] : d[31:24];
    assign w2  = (w_load==0) ? 0 : (w_lw || (w_lh && ost[1]==0)) ? d[15:8] :
                           (w_lh && ost[1]==1) ? d[31:24] : (w_lb_sign) ? 8'hff : 0;
    assign w3 = (w_load == 0) ? 0 : (w_lw) ? d[23:16] : ((w_lb_sign) || (w_lh_sign)) ? 8'hff : 0;
    assign w4 = (w_load == 0) ? 0 : (w_lw) ? d[31:24] : ((w_lb_sign) || (w_lh_sign)) ? 8'hff : 0;
    assign rslt_o = {w4, w3, w2, w1};
`endif
endmodule

/******************************************************************************************/
module imm_gen (
    input  wire [        31:0] ir_i,
    input  wire [`ITYPE_W-1:0] instr_type_i,
    output wire [   `XLEN-1:0] imm_o
);

    wire [31:0] ir = ir_i;
    wire        i_ = (instr_type_i == `I_TYPE);
    wire        s_ = (instr_type_i == `S_TYPE);
    wire        j_ = (instr_type_i == `J_TYPE);
    wire        b_ = (instr_type_i == `B_TYPE);
    wire        u_ = (instr_type_i == `U_TYPE);

    wire        imm0 = (i_) ? ir[20] : (s_) ? ir[7] : 0;
    wire [ 3:0] imm4_1 = (i_ | j_) ? ir[24:21] : (s_ | b_) ? ir[11:8] : 0;
    wire [ 5:0] imm10_5 = (i_ | s_ | b_ | j_) ? ir[30:25] : 0;
    wire        imm11 = (i_ | s_) ? ir[31] : (b_) ? ir[7] : (j_) ? ir[20] : 0;
    wire [ 7:0] imm19_12 = (i_ | s_ | b_) ? {8{ir[31]}} : (u_ | j_) ? ir[19:12] : 0;
    wire [10:0] imm30_20 = (i_ | s_ | b_ | j_) ? {11{ir[31]}} : (u_) ? ir[30:20] : 0;
    wire [31:0] imm32 = {ir[31], imm30_20, imm19_12, imm11, imm10_5, imm4_1, imm0};
`ifdef RV64
    assign imm_o = {{32{imm32[31]}}, imm32};
`else
    assign imm_o = imm32;
`endif
endmodule

/******************************************************************************************/
module decoder (
    input  wire [                31:0] ir_i,
    output wire [`SRC2_CTRL_WIDTH-1:0] src2_ctrl_o,
    output wire [ `ALU_CTRL_WIDTH-1:0] alu_ctrl_o,
    output wire [ `BRU_CTRL_WIDTH-1:0] bru_ctrl_o,
    output wire [ `LSU_CTRL_WIDTH-1:0] lsu_ctrl_o,
    output wire [ `MUL_CTRL_WIDTH-1:0] mul_ctrl_o,
    output wire [ `DIV_CTRL_WIDTH-1:0] div_ctrl_o,
    output wire [ `CFU_CTRL_WIDTH-1:0] cfu_ctrl_o
);

    wire [31:0] ir = ir_i;
    wire [ 6:0] opcode = ir[6:0];
    wire [ 4:0] op = ir[6:2];
    wire [ 2:0] f3 = ir[14:12];
    wire [ 6:0] f7 = ir[31:25];
    assign cfu_ctrl_o = (op == 5'b00010) ? {f7, f3, 1'b1} : 0;

    wire src2_c0 = (op == 5'b00101);  // AUIPC
    wire src2_c1 = (op == 5'b01101) | (op == 5'b00100);  // LUI, OP-IMM
    assign src2_ctrl_o = {src2_c1, src2_c0};

    wire bru_c0 = (op == 5'b11011) || (op == 5'b11001) || (op == 5'b11000);  // IS_CTRL_TSFR
    wire bru_c1 = (op == 5'b11000) && (f3 == 4 || f3 == 5);  // IS_SIGNED
    wire bru_c2 = (op == 5'b11000) && (f3 == 0);  // IS_BEQ
    wire bru_c3 = (op == 5'b11000) && (f3 == 1);  // IS_BNE
    wire bru_c4 = (op == 5'b11000) && (f3 == 4 || f3 == 6);  // IS_BLT
    wire bru_c5 = (op == 5'b11000) && (f3 == 5 || f3 == 7);  // IS_BGE
    wire bru_c6 = (op == 5'b11001);  // IS_JALR
    wire bru_c7 = (op == 5'b11011) || (op == 5'b11001);  // IS_JAL_JALR
    assign bru_ctrl_o = {bru_c7, bru_c6, bru_c5, bru_c4, bru_c3, bru_c2, bru_c1, bru_c0};

    wire lsu_c0 = (op == 0);  // IS_LOAD
    wire lsu_c1 = (op == 8);  // IS_STORE
    wire lsu_c2 = (op == 0 && (f3 == 0 || f3 == 1 || f3 == 2));  // IS_SIGNED
    wire lsu_c3 = (op == 0 && (f3 == 0 || f3 == 4)) || (op == 8 && (f3 == 0));  // BYTE
    wire lsu_c4 = (op == 0 && (f3 == 1 || f3 == 5)) || (op == 8 && (f3 == 1));  // HALFWORD
`ifdef RV64
    wire lsu_c5 = (op == 0 && (f3 == 2 || f3 == 6)) || (op == 8 && (f3 == 2));  // WORD
    wire lsu_c6 = (op == 0 && (f3 == 3)) || (op == 8 && (f3 == 3));  // DOUBLEWORD
    assign lsu_ctrl_o = {lsu_c6, lsu_c5, lsu_c4, lsu_c3, lsu_c2, lsu_c1, lsu_c0};
`else
    wire lsu_c5 = (op == 0 && (f3 == 2)) || (op == 8 && (f3 == 2));  // WORD
    assign lsu_ctrl_o = {lsu_c5, lsu_c4, lsu_c3, lsu_c2, lsu_c1, lsu_c0};
`endif

`ifdef RV64
    wire mul_c0 = ((op == 12) && (f7 == 1) && (f3 == 0 || f3 == 1 || f3 == 2 || f3 == 3)) ||
                  ((op == 14) && (f7 == 1) && (f3 == 0));  // IS_MUL
`else
    wire mul_c0 = (op == 12) && (f7 == 1) && (f3 == 0 || f3 == 1 || f3 == 2 || f3 == 3);  // IS_MUL
`endif
    wire mul_c1 = (op == 12) && (f7 == 1) && (f3 == 1 || f3 == 2);  // IS_SRC1_SIGNED
    wire mul_c2 = (op == 12) && (f7 == 1) && (f3 == 1);  // IS_SRC2_SIGNED
    wire mul_c3 = (op == 12) && (f7 == 1) && (f3 == 1 || f3 == 2 || f3 == 3);  // IS_HIGH
`ifdef RV64
    wire mul_c4 = (op == 14) && (f7 == 1) && (f3 == 0); // IS_W
    assign mul_ctrl_o = {mul_c4, mul_c3, mul_c2, mul_c1, mul_c0};
`else
    assign mul_ctrl_o = {mul_c3, mul_c2, mul_c1, mul_c0};
`endif

`ifdef RV64
    wire div_c0 = ((op == 12) || (op == 14)) && (f7 == 1) && (f3 == 4 || f3 == 5 || f3 == 6 || f3 == 7);  // IS_DIV
    wire div_c1 = ((op == 12) || (op == 14)) && (f7 == 1) && (f3 == 4 || f3 == 6);  // IS_SIGNED
    wire div_c2 = ((op == 12) || (op == 14)) && (f7 == 1) && (f3 == 6 || f3 == 7);  // IS_REM
    wire div_c3 = (op == 14) && (f7 == 1) && (f3 == 4 || f3 == 5 || f3 == 6 || f3 == 7); // IS_W
    assign div_ctrl_o = {div_c3, div_c2, div_c1, div_c0};
`else
    wire div_c0 = (op == 12) && (f7 == 1) && (f3 == 4 || f3 == 5 || f3 == 6 || f3 == 7);  // IS_DIV
    wire div_c1 = (op == 12) && (f7 == 1) && (f3 == 4 || f3 == 6);  // IS_SIGNED
    wire div_c2 = (op == 12) && (f7 == 1) && (f3 == 6 || f3 == 7);  // IS_REM
    assign div_ctrl_o = {div_c2, div_c1, div_c0};
`endif

    wire [9:0] f10 = {f7, f3};
`ifdef RV64
    wire is_op_imm = (op == 5'b00100) || (op == 5'b00110); // OP-IMM, OP-IMM-32
    wire is_op     = (op == 5'b01100) || (op == 5'b01110); // OP, OP-32
`else
    wire is_op_imm = (op == 5'b00100);
    wire is_op     = (op == 5'b01100);
`endif
    wire alu_c0 = (is_op_imm && f3==2) || (is_op_imm && f3==5 && f7==7'b0100000) ||
                  (is_op && (f10==10'b10 || f10==10'b0100000101)); // IS_SIGNED
    wire alu_c1 = (is_op_imm && (f3==2 || f3==3)) || (is_op &&
                  (f10==10'b100000000 || f10==10'b10 || f10==10'b11)); // IS_NEG
    wire alu_c2 = (is_op_imm && (f3==2 || f3==3)) ||
                  (is_op && (f10==10'b10 || f10==10'b11)); // IS_LESS
    wire alu_c3 = (is_op_imm && f3==0) ||
                  (is_op && (f10==10'b0 || f10==10'b100000000)); // IS_ADD
    wire alu_c4 = (is_op_imm && f3 == 1 && f7[6:1] == 6'b0) || (is_op && f10 == 1);  // IS_SHIFT_LEFT
    wire alu_c5 = (is_op_imm && f3==5 && (f7[6:1]==6'b0 || f7[6:1]==6'b010000)) || (is_op &&
                  (f10==10'b101 || f10==10'b0100000101)); // IS_SHIFT_RIGHT
    wire alu_c6 = (is_op_imm && (f3==4 || f3==6)) || (is_op && (f10==4 || f10==6));//IS_XOR_OR
    wire alu_c7 = (is_op_imm && (f3==6 || f3==7)) || (is_op && (f10==6 || f10==7));//IS_OR_AND
    wire alu_c8 = (op == 5'b01101 || op == 5'b00101);  // IS_SRC2
`ifdef RV64
    wire alu_c9 = (op == 5'b00110 || op == 5'b01110);  // IS_W
    assign alu_ctrl_o = {alu_c9, alu_c8, alu_c7, alu_c6, alu_c5, alu_c4, alu_c3, alu_c2, alu_c1, alu_c0};
`else
    assign alu_ctrl_o = {alu_c8, alu_c7, alu_c6, alu_c5, alu_c4, alu_c3, alu_c2, alu_c1, alu_c0};
`endif
endmodule
/******************************************************************************************/
