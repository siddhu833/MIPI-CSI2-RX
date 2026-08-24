`timescale 1ns/1ps

module pixel_unpack #(
    parameter AXIS_WIDTH = 8,
    parameter pixal_widht = 24
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire  [5:0] data_type, // MIPI CSI-2 Data Type (e.g. 6'h2A=RAW8, 6'h2B=RAW10, 6'h2C=RAW12, 6'h24=RGB888)
    
    // AXI input from Async FIFO
    input  wire [AXIS_WIDTH - 1:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    
    // Unpacked output (up to 24 bits wide)
    output reg  [pixal_widht-1:0] px_out,       
    output reg         px_valid,
    output reg         px_last       // End of line flag
);

    // Input buffer to hold raw bytes
    reg [7:0] in_buf [0:3];
    reg [2:0] in_count;

    // Output queue buffer for unpacked pixels
    reg [pixal_widht-1:0] out_buf [0:3];
    reg [2:0] out_count;
    reg [1:0] out_ptr;
    reg       out_last_flag;

    // Always ready after reset since output processing is faster than or equal to input
    assign s_axis_tready = rst_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            px_out        <= 0;
            px_valid      <= 0;
            px_last       <= 0;
            in_count      <= 0;
            out_count     <= 0;
            out_ptr       <= 0;
            out_last_flag <= 0;
            in_buf[0]     <= 0;
            in_buf[1]     <= 0;
            in_buf[2]     <= 0;
            in_buf[3]     <= 0;
            out_buf[0]    <= 0;
            out_buf[1]    <= 0;
            out_buf[2]    <= 0;
            out_buf[3]    <= 0;
        end else begin
            // Default assignments
            px_valid <= 0;
            px_last  <= 0;

            // 1. INPUT STREAM PROCESSING & UNPACKING
            if (s_axis_tvalid && s_axis_tready) begin
                if (data_type == 6'h2A) begin
                    // RAW8 mode (Bypass): 1 Byte -> 1 Pixel immediately
                    px_out   <= {16'd0, s_axis_tdata};
                    px_valid <= 1'b1;
                    px_last  <= s_axis_tlast;
                end else if (data_type == 6'h2B) begin
                    // RAW10 mode: 5 Bytes -> 4 Pixels
                    if (in_count == 4) begin
                        out_buf[0]    <= {14'd0, in_buf[0], s_axis_tdata[1:0]};
                        out_buf[1]    <= {14'd0, in_buf[1], s_axis_tdata[3:2]};
                        out_buf[2]    <= {14'd0, in_buf[2], s_axis_tdata[5:4]};
                        out_buf[3]    <= {14'd0, in_buf[3], s_axis_tdata[7:6]};
                        out_count     <= 4;
                        out_ptr       <= 0;
                        in_count      <= 0;
                        out_last_flag <= s_axis_tlast;
                    end else begin
                        in_buf[in_count] <= s_axis_tdata;
                        in_count         <= in_count + 1;
                    end
                end else if (data_type == 6'h2C) begin
                    // RAW12 mode: 3 Bytes -> 2 Pixels
                    if (in_count == 2) begin
                        out_buf[0]    <= {12'd0, in_buf[0], s_axis_tdata[3:0]};
                        out_buf[1]    <= {12'd0, in_buf[1], s_axis_tdata[7:4]};
                        out_count     <= 2;
                        out_ptr       <= 0;
                        in_count      <= 0;
                        out_last_flag <= s_axis_tlast;
                    end else begin
                        in_buf[in_count] <= s_axis_tdata;
                        in_count         <= in_count + 1;
                    end
                end else if (data_type == 6'h24) begin
                    // RGB888 (RAW24) mode: 3 Bytes -> 1 Pixel
                    if (in_count == 2) begin
                        out_buf[0]    <= {s_axis_tdata, in_buf[1], in_buf[0]};
                        out_count     <= 1;
                        out_ptr       <= 0;
                        in_count      <= 0;
                        out_last_flag <= s_axis_tlast;
                    end else begin
                        in_buf[in_count] <= s_axis_tdata;
                        in_count         <= in_count + 1;
                    end
                end

                // Failsafe: Reset input counter on premature tlast
                if (s_axis_tlast && (
                    (data_type == 6'h2B && in_count != 4) ||
                    (data_type == 6'h2C && in_count != 2) ||
                    (data_type == 6'h24 && in_count != 2)
                )) begin
                    in_count <= 0;
                end
            end

            // 2. OUTPUT PIPELINE GENERATION
            // Runs independently to flush the remaining pixels when input is idle or finished
            if (data_type != 6'h2A) begin
                if (out_count > 0) begin
                    px_out    <= out_buf[out_ptr];
                    px_valid  <= 1'b1;
                    out_ptr   <= out_ptr + 1;
                    out_count <= out_count - 1;

                    // Assert px_last on the final pixel of the decoded group
                    if (
                        (data_type == 6'h2B && out_ptr == 3) ||
                        (data_type == 6'h2C && out_ptr == 1) ||
                        (data_type == 6'h24 && out_ptr == 0)
                    ) begin
                        px_last <= out_last_flag;
                    end
                end
            end
        end
    end

endmodule
