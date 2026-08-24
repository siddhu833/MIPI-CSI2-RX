`timescale 1ns / 1ps

module tb_pixel_unpack();

    // Inputs
    reg clk;
    reg rst_n;
    reg [5:0] data_type;
    reg [7:0] s_axis_tdata;
    reg s_axis_tvalid;
    reg s_axis_tlast;

    // Outputs
    wire s_axis_tready;
    wire [23:0] px_out;
    wire px_valid;
    wire px_last;

    // Instantiate the Unit Under Test (UUT)
    pixel_unpack #(
        .AXIS_WIDTH(8),
        .pixal_widht(24)
    ) uut (
        .clk(clk), 
        .rst_n(rst_n), 
        .data_type(data_type), 
        .s_axis_tdata(s_axis_tdata), 
        .s_axis_tvalid(s_axis_tvalid), 
        .s_axis_tready(s_axis_tready), 
        .s_axis_tlast(s_axis_tlast), 
        .px_out(px_out), 
        .px_valid(px_valid), 
        .px_last(px_last)
    );

    // Clock generation (100 MHz)
    always #5 clk = ~clk;

    // Task to safely send an AXI-Stream byte
    task send_axis_byte(input [7:0] data, input is_last);
        begin
            s_axis_tdata = data;
            s_axis_tvalid = 1;
            s_axis_tlast = is_last;
            
            // Wait until the unpacker is READY
            wait (s_axis_tready == 1'b1);
            @(posedge clk);
            #1; // Delay dropping the signals to avoid race conditions
            s_axis_tvalid = 0;
            s_axis_tlast = 0;
            
            // Add a small delay if it stalls (e.g., when unpacking)
            if (s_axis_tready == 1'b0) begin
                wait (s_axis_tready == 1'b1);
            end
        end
    endtask

    initial begin
        // Initialize Inputs
        clk = 0;
        rst_n = 0;
        data_type = 6'h00;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;

        $display("=================================================");
        $display("   Dynamic Pixel Unpacker Testbench Started");
        $display("=================================================");

        // Wait for global reset
        #20;
        rst_n = 1;
        #20;
        
        // ---------------------------------------------------------
        // TEST 1: RAW8 Unpacking (1 Byte -> 1 Pixel)
        // ---------------------------------------------------------
        $display("\n--- TEST 1: RAW8 Format ---");
        data_type = 6'h2A; // MIPI RAW8
        
        // Send 2 pixels
        send_axis_byte(8'hAA, 0); // Pixel 1
        send_axis_byte(8'hBB, 1); // Pixel 2 (Last)
        
        #20;

        // ---------------------------------------------------------
        // TEST 2: RAW24 (RGB888) Unpacking (3 Bytes -> 1 Pixel)
        // ---------------------------------------------------------
        $display("\n--- TEST 2: RAW24 Format ---");
        data_type = 6'h24; // MIPI RGB888
        
        // Send 1 pixel (R=AA, G=BB, B=CC)
        send_axis_byte(8'hAA, 0);
        send_axis_byte(8'hBB, 0);
        send_axis_byte(8'hCC, 1); // Last byte of packet
        
        #20;

        // ---------------------------------------------------------
        // TEST 3: RAW10 Unpacking (5 Bytes -> 4 Pixels)
        // ---------------------------------------------------------
        $display("\n--- TEST 3: RAW10 Format ---");
        data_type = 6'h2B; // MIPI RAW10
        
        // MIPI Spec: 4 bytes of MSBs, 1 byte of LSBs
        send_axis_byte(8'h11, 0); // Px0 MSBs
        send_axis_byte(8'h22, 0); // Px1 MSBs
        send_axis_byte(8'h33, 0); // Px2 MSBs
        send_axis_byte(8'h44, 0); // Px3 MSBs
        send_axis_byte(8'hE4, 1); // LSBs for all 4 pixels (11 10 01 00 = 0xE4)
        
        // Wait for state machine to unpack and push out the 4 pixels
        #60;

        // ---------------------------------------------------------
        // TEST 4: RAW12 Unpacking (3 Bytes -> 2 Pixels)
        // ---------------------------------------------------------
        $display("\n--- TEST 4: RAW12 Format ---");
        data_type = 6'h2C; // MIPI RAW12
        
        // MIPI Spec: 2 bytes of MSBs, 1 byte of LSBs
        send_axis_byte(8'hDD, 0); // Px0 MSBs
        send_axis_byte(8'hEE, 0); // Px1 MSBs
        send_axis_byte(8'hA5, 1); // Px1 LSB(A), Px0 LSB(5)
        
        // Wait for state machine to unpack and push out the 2 pixels
        #40;

        $display("\n=================================================");
        $display("   All Unpacker tests completed.");
        $display("=================================================\n");
        $finish;
    end

    // Monitor to cleanly print pixels as they are outputted
    always @(posedge clk) begin
        if (px_valid) begin
            $display("Time: %0t | DATA_TYPE: %h | Output Pixel: %h | Last Pixel: %b", 
                     $time, data_type, px_out, px_last);
        end
    end

endmodule
