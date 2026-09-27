/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

`resetall `default_nettype none

`include "config.vh"

/*
 * Minimal transmit-only UART used by the CFU-PG console MMIO peripheral.
 * The transmitter sends 8 data bits, LSB first, with one start and stop bit.
 */
module uart_tx #(
    parameter integer CLOCK_HZ = `CLK_FREQ_MHZ * 1000000,
    parameter integer BAUD_RATE = `BAUD_RATE
) (
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       we_i,
    input  wire [7:0] data_i,
    output wire       ready_o,
    output reg        txd_o
);
    localparam integer CLKS_PER_BIT = CLOCK_HZ / BAUD_RATE;
    localparam integer COUNTER_WIDTH =
        (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    reg [COUNTER_WIDTH-1:0] baud_count;
    reg [3:0] bit_index;
    reg [7:0] data_latch;
    reg busy;

    assign ready_o = !busy;

    always @(posedge clk_i) begin
        if (rst_i) begin
            baud_count <= {COUNTER_WIDTH{1'b0}};
            bit_index   <= 4'd0;
            data_latch  <= 8'd0;
            busy        <= 1'b0;
            txd_o       <= 1'b1;
        end else if (!busy) begin
            txd_o <= 1'b1;
            if (we_i) begin
                data_latch <= data_i;
                baud_count <= CLKS_PER_BIT - 1;
                bit_index  <= 4'd0;
                busy       <= 1'b1;
                txd_o      <= 1'b0;
            end
        end else if (baud_count != 0) begin
            baud_count <= baud_count - 1'b1;
        end else begin
            baud_count <= CLKS_PER_BIT - 1;
            if (bit_index < 8) begin
                txd_o      <= data_latch[bit_index];
                bit_index  <= bit_index + 1'b1;
            end else if (bit_index == 8) begin
                txd_o      <= 1'b1;
                bit_index  <= bit_index + 1'b1;
            end else begin
                busy  <= 1'b0;
                txd_o <= 1'b1;
            end
        end
    end
endmodule

`resetall
