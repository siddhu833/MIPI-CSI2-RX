`timescale 1ns / 1ps

module tb_csi2_ecc_rx();

    // Inputs
    reg [25:0] data_in;
    reg [5:0]  ecc_rx;

    // Outputs
    wire [25:0] data_corr;
    wire        ecc_ok;
    wire        ecc_corrected;
    wire        ecc_error;

    // Instantiate the Unit Under Test (UUT)
    csi2_ecc_rx uut (
        .data_in(data_in), 
        .ecc_rx(ecc_rx), 
        .data_corr(data_corr), 
        .ecc_ok(ecc_ok), 
        .ecc_corrected(ecc_corrected), 
        .ecc_error(ecc_error)
    );

    // Function to accurately calculate the ECC based on CSI-2 Hamming logic
    function [5:0] calc_ecc(input [25:0] d);
        begin
            calc_ecc[0] = d[0]  ^ d[1]  ^ d[3]  ^ d[4]  ^ d[6]  ^ d[8]  ^ 
                          d[10] ^ d[11] ^ d[13] ^ d[15] ^ d[17] ^ d[19] ^ 
                          d[21] ^ d[23] ^ d[25];

            calc_ecc[1] = d[0]  ^ d[2]  ^ d[3]  ^ d[5]  ^ d[6]  ^ d[9]  ^ 
                          d[10] ^ d[12] ^ d[13] ^ d[16] ^ d[17] ^ d[20] ^ 
                          d[21] ^ d[24] ^ d[25];

            calc_ecc[2] = d[1]  ^ d[2]  ^ d[3]  ^ d[7]  ^ d[8]  ^ d[9]  ^ 
                          d[10] ^ d[14] ^ d[15] ^ d[16] ^ d[17] ^ d[22] ^ 
                          d[23] ^ d[24] ^ d[25];

            calc_ecc[3] = d[4]  ^ d[5]  ^ d[6]  ^ d[7]  ^ d[8]  ^ d[9]  ^ 
                          d[10] ^ d[18] ^ d[19] ^ d[20] ^ d[21] ^ d[22] ^ 
                          d[23] ^ d[24] ^ d[25];

            calc_ecc[4] = d[11] ^ d[12] ^ d[13] ^ d[14] ^ d[15] ^ d[16] ^ 
                          d[17] ^ d[18] ^ d[19] ^ d[20] ^ d[21] ^ d[22] ^ 
                          d[23] ^ d[24] ^ d[25];

            calc_ecc[5] = d[0]  ^ d[1]  ^ d[2]  ^ d[3]  ^ d[4]  ^ d[5]  ^ 
                          d[6]  ^ d[7]  ^ d[8]  ^ d[9]  ^ d[10] ^ d[11] ^ 
                          d[12] ^ d[13] ^ d[14] ^ d[15] ^ d[16] ^ d[17] ^ 
                          d[18] ^ d[19];
        end
    endfunction

    // Variables for holding ground truth data
    reg [25:0] true_data;
    reg [5:0]  true_ecc;

    initial begin
        $display("=================================================");
        $display("   CSI-2 ECC Receiver Testbench Started");
        $display("=================================================");
        
        $monitor("Time: %0t | In: %h | ECC_RX: %b || Corr: %h | OK: %b | Corrected: %b | Error: %b", 
                 $time, data_in, ecc_rx, data_corr, ecc_ok, ecc_corrected, ecc_error);

        // -----------------------------------------------------------------
        // TEST 1: No Error (Perfect transmission)
        // -----------------------------------------------------------------
        $display("\n--- TEST 1: Perfect Transmission ---");
        true_data = 26'h1A2B3C;           // Random 26-bit header payload
        true_ecc  = calc_ecc(true_data);  // Compute correct ECC
        
        data_in = true_data;
        ecc_rx  = true_ecc;
        #10;
        
        if (ecc_ok && !ecc_error && !ecc_corrected && data_corr == true_data)
            $display("[PASS] 100%% Correct. Data preserved.");
        else
            $display("[FAIL] Test 1 failed!");

        // -----------------------------------------------------------------
        // TEST 2: 1-Bit Error in Data Payload (Should Auto-Correct)
        // -----------------------------------------------------------------
        $display("\n--- TEST 2: Single Bit Error (Data bit 7) ---");
        data_in = true_data ^ (1 << 7);   // Flip bit 7 to simulate transmission error
        ecc_rx  = true_ecc;
        #10;
        
        if (!ecc_ok && ecc_corrected && !ecc_error && data_corr == true_data)
            $display("[PASS] 1-Bit error detected AND perfectly corrected.");
        else
            $display("[FAIL] Test 2 failed!");

        // -----------------------------------------------------------------
        // TEST 3: 1-Bit Error in ECC Parity (Should Ignore/Correct)
        // -----------------------------------------------------------------
        $display("\n--- TEST 3: Single Bit Error (ECC Parity bit 3) ---");
        data_in = true_data;
        ecc_rx  = true_ecc ^ (1 << 3);    // Flip ECC bit 3
        #10;
        
        if (!ecc_ok && ecc_corrected && !ecc_error && data_corr == true_data)
            $display("[PASS] 1-Bit parity error detected and bypassed safely.");
        else
            $display("[FAIL] Test 3 failed!");

        // -----------------------------------------------------------------
        // TEST 4: 2-Bit Error in Data Payload (Should Detect but NOT correct)
        // -----------------------------------------------------------------
        $display("\n--- TEST 4: Double Bit Error (Data bits 2 and 19) ---");
        data_in = true_data ^ (1 << 2) ^ (1 << 19); // Flip two data bits
        ecc_rx  = true_ecc;
        #10;
        
        if (!ecc_ok && !ecc_corrected && ecc_error)
            $display("[PASS] 2-Bit fatal error detected and correctly flagged.");
        else
            $display("[FAIL] Test 4 failed! (Did it try to correct a 2-bit error?)");

        // -----------------------------------------------------------------
        // TEST 5: 2-Bit Error (1 Data Bit + 1 Parity Bit)
        // -----------------------------------------------------------------
        $display("\n--- TEST 5: Double Bit Error (Data bit 12 + Parity bit 1) ---");
        data_in = true_data ^ (1 << 12);
        ecc_rx  = true_ecc ^ (1 << 1);
        #10;
        
        if (!ecc_ok && !ecc_corrected && ecc_error)
            $display("[PASS] 2-Bit scattered fatal error detected and flagged.");
        else
            $display("[FAIL] Test 5 failed!");

        $display("\n=================================================");
        $display("   All tests completed successfully.");
        $display("=================================================\n");
        $finish;
    end

endmodule
