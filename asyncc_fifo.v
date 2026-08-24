`timescale 1ns / 1ps

module asyncc_fifo #(parameter depth = 16 ,
parameter width = 8 )(

input clk_w,clk_r,rst_w,rst_r,w_en,r_en,
input [width - 1:0]data_in,
output full,empty,
output reg [width - 1:0]data_out

    );
    
    reg [width - 1:0] mem[depth - 1:0];
    
    localparam PTR_WIDTH = $clog2(depth) + 1;
    
    wire [PTR_WIDTH - 1:0] b_wptr, b_rptr;
    wire [PTR_WIDTH - 1:0] g_rptr;
    wire [PTR_WIDTH - 1:0] g_w_ptr;
    wire [PTR_WIDTH - 1:0] g_rptr_sync;
    wire [PTR_WIDTH - 1:0] g_wptr_sync;
    
    
    sync_2ff  #(.width(PTR_WIDTH)) ff_r (
        .clk(clk_r),
        .rst(rst_r),
        .in(g_w_ptr),
        .q(g_wptr_sync)
    );

    sync_2ff  #(.width(PTR_WIDTH)) ff_w (
        .clk(clk_w),
        .rst(rst_w),
        .in(g_rptr),
        .q(g_rptr_sync)
    );
  
    w_ptr_handler  #(.width(PTR_WIDTH)) w_hndlr (
        .clk_w(clk_w),
        .rst_w(rst_w),
        .w_en(w_en),
        .g_rptr_sync(g_rptr_sync),
        .b_wptr(b_wptr),
        .g_w_ptr(g_w_ptr),
        .full(full)
    );
    
    rd_ptr_hdlr  #(.width(PTR_WIDTH)) r_hndlr (
        .clk_r(clk_r),
        .rst_r(rst_r),
        .r_en(r_en),
        .g_wptr_sync(g_wptr_sync),
        .b_rptr(b_rptr),
        .g_rptr(g_rptr),
        .empty(empty)
    );
    
    always @(posedge clk_w) begin
        if (w_en && !full) begin
            mem[b_wptr[PTR_WIDTH - 2:0]] <= data_in;
        end
    end
                             
    always @(posedge clk_r) begin
        if (rst_r) begin
            data_out <= 0;
        end else if (r_en && !empty) begin
            data_out <= mem[b_rptr[PTR_WIDTH - 2:0]];
        end
    end                  
    
endmodule
