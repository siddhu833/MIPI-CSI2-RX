`timescale 1ns / 1ps
// ============================================================================
// rst_sync.v - reset synchronizer
//
// Asynchronous assertion, synchronous de-assertion. One instance per clock
// domain so that reset release never violates recovery/removal timing
// (prevents reset-domain-crossing / metastability on reset release).
// ============================================================================

module rst_sync (
    input  wire clk,
    input  wire arst_n,     // asynchronous active-low reset input
    output wire srst_n      // reset for this clock domain
);

    (* ASYNC_REG = "TRUE" *) reg rst_ff1;
    (* ASYNC_REG = "TRUE" *) reg rst_ff2;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            rst_ff1 <= 1'b0;
            rst_ff2 <= 1'b0;
        end else begin
            rst_ff1 <= 1'b1;
            rst_ff2 <= rst_ff1;
        end
    end

    assign srst_n = rst_ff2;

endmodule
