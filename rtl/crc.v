module crc16_1021 (
    input  wire        clk,
    input  wire        rst,          // active high reset
    input  wire        init,         // pulse to start new packet
    input  wire        data_valid,
    input  wire [7:0]  data_in,
    output reg  [15:0] crc_out
);

    integer i;
    reg [15:0] crc_next;
    reg feedback;

    always @(posedge clk) begin
        if (rst)
            crc_out <= 16'hFFFF;
        else if (init)
            crc_out <= 16'hFFFF;
        else if (data_valid) begin
            crc_next = crc_out;

            // Process 8 bits
            for (i = 0; i < 8; i = i + 1) begin
                feedback = data_in[i] ^ crc_next[15];
                crc_next = {crc_next[14:0], 1'b0};

                if (feedback) begin
                    crc_next[12] = crc_next[12] ^ 1'b1;
                    crc_next[5]  = crc_next[5]  ^ 1'b1;
                    crc_next[0]  = crc_next[0]  ^ 1'b1;
                end
            end

            crc_out <= crc_next;
        end
    end

endmodule