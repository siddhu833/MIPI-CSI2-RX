`timescale 1ns / 1ps

// Synchronizer flop: asynchronous active-low reset, so there is no reset
// logic in front of D (a synchronizer must be flop-to-flop with no logic).
module D_flipflop(
    input clk,
    input rst_n,
    input d,
    output reg q
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        q <= 1'b0;
    else
        q <= d;
end

endmodule
