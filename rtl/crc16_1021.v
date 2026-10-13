`timescale 1ns / 1ps
// ============================================================================
// crc16_1021.v - CSI-2 payload CRC (CRC-16-CCITT, polynomial x^16+x^12+x^5+1)
//
// Seed 0xFFFF, bytes processed LSB first, one byte per clock.
// ============================================================================

module crc16_1021 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init,        // reload seed (start of payload)
    input  wire        data_valid,
    input  wire [7:0]  data_in,
    output reg  [15:0] crc_out
);

    function [15:0] crc_next;
        input [15:0] crc;
        input [7:0]  data;
        integer k;
        reg [15:0] c;
        reg        fb;
        begin
            c = crc;
            for (k = 0; k < 8; k = k + 1) begin
                fb = data[k] ^ c[15];
                c  = {c[14:0], 1'b0};
                if (fb)
                    c = c ^ 16'h1021;
            end
            crc_next = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            crc_out <= 16'hFFFF;
        else if (init)
            crc_out <= 16'hFFFF;
        else if (data_valid)
            crc_out <= crc_next(crc_out, data_in);
    end

endmodule
