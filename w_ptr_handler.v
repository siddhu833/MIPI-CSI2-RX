`timescale 1ns / 1ps

module w_ptr_handler #(parameter width= 5)(

input clk_w,rst_w,w_en,
input [width -1 :0] g_rptr_sync,
output reg [width -1 :0]b_wptr,
output [width -1 :0]g_w_ptr,
output full

    );
    
    assign g_w_ptr = b_wptr ^ (b_wptr >>1);
    assign full = (g_w_ptr == {~g_rptr_sync[width-1:width-2], g_rptr_sync[width-3:0]});
    
    always@(posedge clk_w)begin
       if(rst_w) begin
       b_wptr <= 0;
               end
       else begin 
       if(w_en && !full) begin
            
            b_wptr <= b_wptr + 1'd1;            
                         end
       
            end        
                           end
                           
                           
endmodule
