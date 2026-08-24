`timescale 1ns / 1ps

module tb_crc16_1021();

    // Inputs
    reg clk;
    reg rst;
    reg init;
    reg data_valid;
    reg [7:0] data_in;

    // Outputs
    wire [15:0] crc_out;

    // Instantiate the Unit Under Test (UUT)
    crc16_1021 uut (
        .clk(clk), 
        .rst(rst), 
        .init(init), 
        .data_valid(data_valid), 
        .data_in(data_in), 
        .crc_out(crc_out)
    );

    // Clock generation (100 MHz)
    always #5 clk = ~clk;

    // Task to send a byte to the CRC module
    task send_byte(input [7:0] d);
        begin
            @(posedge clk);
            data_valid = 1'b1;
            data_in = d;
            @(posedge clk);
            data_valid = 1'b0;
        end
    endtask

    initial begin
        // Initialize Inputs
        clk = 0;
        rst = 1;
        init = 0;
        data_valid = 0;
        data_in = 0;

        $display("=================================================");
        $display("   CSI-2 CRC-16 Polynomial Testbench Started");
        $display("=================================================");
        
        $monitor("Time: %0t | init: %b | valid: %b | data_in: %h | CRC_OUT: %h", 
                 $time, init, data_valid, data_in, crc_out);

        // -----------------------------------------------------------------
        // TEST 1: Reset Check
        // -----------------------------------------------------------------
        #20;
        rst = 0;
        #10;
        
        if (crc_out !== 16'hFFFF) 
            $display("[FAIL] Hard Reset state should be FFFF. Got: %h", crc_out);
        else 
            $display("[PASS] Hard Reset initialized CRC to FFFF.");

        // -----------------------------------------------------------------
        // TEST 2: Process a Data Packet
        // -----------------------------------------------------------------
        $display("\n--- Processing Packet 1 (Data: AB CD EF 12) ---");
        
        // Pulse init to start new packet
        @(posedge clk);
        init = 1;
        @(posedge clk);
        init = 0;
        
        // Stream bytes
        send_byte(8'hAB);
        send_byte(8'hCD);
        send_byte(8'hEF);
        send_byte(8'h12);
        
        // Wait for processing to complete
        #20;
        $display("\n[RESULT] Final CRC Checksum for Packet 1: %h", crc_out);

        // -----------------------------------------------------------------
        // TEST 3: Soft Reset via 'init' pulse
        // -----------------------------------------------------------------
        $display("\n--- Processing Packet 2 (Testing 'init' reset logic) ---");
        
        // Pulse init
        @(posedge clk);
        init = 1;
        @(posedge clk);
        init = 0;
        
        // Ensure CRC wiped back to FFFF
        if (crc_out !== 16'hFFFF) 
            $display("[FAIL] 'init' pulse failed to reset CRC. Got: %h", crc_out);
        else 
            $display("[PASS] 'init' pulse successfully cleared CRC back to FFFF.");

        // Stream different bytes
        send_byte(8'h00);
        send_byte(8'hFF);
        
        #20;
        $display("[RESULT] Final CRC Checksum for Packet 2: %h", crc_out);

        $display("\n=================================================");
        $display("   All tests completed successfully.");
        $display("=================================================\n");
        $finish;
    end

endmodule
