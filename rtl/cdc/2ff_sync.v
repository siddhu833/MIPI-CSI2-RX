`timescale 1ns / 1ps


module sync_2ff #(parameter width = 1)(

input clk,rst_n,
input [width-1:0]in,
output [width -1 :0]q
    );


  wire [width-1:0]qs;
    genvar i;

    generate
     for (i = 0 ; i<= width - 1 ; i=i+1) begin : sync_ff
    D_flipflop sync_2ff_1(.clk(clk),.rst_n(rst_n),.d(in[i]),.q(qs[i]));
    D_flipflop sync_2ff_2(.clk(clk),.rst_n(rst_n),.d(qs[i]),.q(q[i])) ;
                                         end
    endgenerate
endmodule
