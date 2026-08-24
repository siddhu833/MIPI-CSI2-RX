`timescale 1ns / 1ps

module rd_ptr_hdlr  #(parameter width= 5)(

input clk_r,rst_r,r_en,
input [width - 1:0]g_wptr_sync,
output empty,
output reg [width - 1:0] b_rptr,
output [width - 1:0]g_rptr

    );
    assign g_rptr = b_rptr ^ (b_rptr >>1);
    assign empty = (g_rptr == g_wptr_sync);
    
    always@(posedge clk_r  )begin
    
        if (rst_r)begin
        
           b_rptr <= 0; 
                  end
        else if(r_en && !empty)begin
                b_rptr <= b_rptr+1;       
                                end
                            end
    
endmodule
