`timescale 1ns / 1ps

// Write pointer: binary pointer for addressing, Gray pointer REGISTERED in
// the write domain so only flop outputs (one bit changing at a time) cross
// into the read domain.
module w_ptr_handler #(parameter width = 5)(
    input clk_w,
    input rst_w_n,
    input w_en,
    input [width-1:0] g_rptr_sync,
    output reg [width-1:0] b_wptr,
    output reg [width-1:0] g_w_ptr,
    output full
);

    wire [width:0]   b_wptr_sum  = {1'b0, b_wptr} + {{width{1'b0}}, (w_en && !full)};
    wire [width-1:0] b_wptr_next = b_wptr_sum[width-1:0];        // pointer wraps by design
    wire [width-1:0] g_wptr_next = b_wptr_next ^ (b_wptr_next >> 1);

    assign full = (g_w_ptr == {~g_rptr_sync[width-1:width-2], g_rptr_sync[width-3:0]});

    always @(posedge clk_w or negedge rst_w_n) begin
        if (!rst_w_n) begin
            b_wptr  <= {width{1'b0}};
            g_w_ptr <= {width{1'b0}};
        end else begin
            b_wptr  <= b_wptr_next;
            g_w_ptr <= g_wptr_next;
        end
    end

endmodule
