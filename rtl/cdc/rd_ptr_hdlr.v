`timescale 1ns / 1ps

// Read pointer: binary pointer for addressing, Gray pointer REGISTERED in
// the read domain so only flop outputs (one bit changing at a time) cross
// into the write domain.
module rd_ptr_hdlr #(parameter width = 5)(
    input clk_r,
    input rst_r_n,
    input r_en,
    input [width-1:0] g_wptr_sync,
    output empty,
    output reg [width-1:0] b_rptr,
    output reg [width-1:0] g_rptr
);

    wire [width:0]   b_rptr_sum  = {1'b0, b_rptr} + {{width{1'b0}}, (r_en && !empty)};
    wire [width-1:0] b_rptr_next = b_rptr_sum[width-1:0];        // pointer wraps by design
    wire [width-1:0] g_rptr_next = b_rptr_next ^ (b_rptr_next >> 1);

    assign empty = (g_rptr == g_wptr_sync);

    always @(posedge clk_r or negedge rst_r_n) begin
        if (!rst_r_n) begin
            b_rptr <= {width{1'b0}};
            g_rptr <= {width{1'b0}};
        end else begin
            b_rptr <= b_rptr_next;
            g_rptr <= g_rptr_next;
        end
    end

endmodule
