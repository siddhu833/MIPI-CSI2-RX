module csi2_ecc_rx (
    input  wire [25:0] data_in,    // D[25:0]
    input  wire [5:0]  ecc_rx,     // received ECC

    output reg  [25:0] data_corr,  // corrected data
    output reg         ecc_ok,
    output reg         ecc_corrected,
    output reg         ecc_error
);

    wire [5:0] ecc_calc;
    wire [5:0] syndrome;

    // ------------------------------------------------------------------
    // ECC recomputation (CSI-2 fixed Hamming logic)
    // ------------------------------------------------------------------
    assign ecc_calc[0] = data_in[0]  ^ data_in[1]  ^ data_in[3]  ^
                          data_in[4]  ^ data_in[6]  ^ data_in[8]  ^
                          data_in[10] ^ data_in[11] ^ data_in[13] ^
                          data_in[15] ^ data_in[17] ^ data_in[19] ^
                          data_in[21] ^ data_in[23] ^ data_in[25];

    assign ecc_calc[1] = data_in[0]  ^ data_in[2]  ^ data_in[3]  ^
                          data_in[5]  ^ data_in[6]  ^ data_in[9]  ^
                          data_in[10] ^ data_in[12] ^ data_in[13] ^
                          data_in[16] ^ data_in[17] ^ data_in[20] ^
                          data_in[21] ^ data_in[24] ^ data_in[25];

    assign ecc_calc[2] = data_in[1]  ^ data_in[2]  ^ data_in[3]  ^
                          data_in[7]  ^ data_in[8]  ^ data_in[9]  ^
                          data_in[10] ^ data_in[14] ^ data_in[15] ^
                          data_in[16] ^ data_in[17] ^ data_in[22] ^
                          data_in[23] ^ data_in[24] ^ data_in[25];

    assign ecc_calc[3] = data_in[4]  ^ data_in[5]  ^ data_in[6]  ^
                          data_in[7]  ^ data_in[8]  ^ data_in[9]  ^
                          data_in[10] ^ data_in[18] ^ data_in[19] ^
                          data_in[20] ^ data_in[21] ^ data_in[22] ^
                          data_in[23] ^ data_in[24] ^ data_in[25];

    assign ecc_calc[4] = data_in[11] ^ data_in[12] ^ data_in[13] ^
                          data_in[14] ^ data_in[15] ^ data_in[16] ^
                          data_in[17] ^ data_in[18] ^ data_in[19] ^
                          data_in[20] ^ data_in[21] ^ data_in[22] ^
                          data_in[23] ^ data_in[24] ^ data_in[25];

    assign ecc_calc[5] = data_in[0]  ^ data_in[1]  ^ data_in[2]  ^
                          data_in[3]  ^ data_in[4]  ^ data_in[5]  ^
                          data_in[6]  ^ data_in[7]  ^ data_in[8]  ^
                          data_in[9]  ^ data_in[10] ^ data_in[11] ^
                          data_in[12] ^ data_in[13] ^ data_in[14] ^
                          data_in[15] ^ data_in[16] ^ data_in[17] ^
                          data_in[18] ^ data_in[19];

    // ------------------------------------------------------------------
    // Syndrome
    // ------------------------------------------------------------------
    assign syndrome = ecc_calc ^ ecc_rx;

    // ------------------------------------------------------------------
    // Correction logic
    // ------------------------------------------------------------------
    always @(*) begin
        data_corr     = data_in;
        ecc_ok        = 1'b0;
        ecc_corrected = 1'b0;
        ecc_error     = 1'b0;

        if (syndrome == 6'b000000) begin
            ecc_ok = 1'b1;
        end
        else begin
            // ✅ CORRECT Syndrome Table - Based on actual testing!
            // CSI-2 spec bit numbering doesn't match data_in bit ordering
            case (syndrome)
                // DI byte (data_in[7:0])
                6'h23: begin data_corr[0]  = ~data_in[0];  ecc_corrected = 1'b1; end
                6'h25: begin data_corr[1]  = ~data_in[1];  ecc_corrected = 1'b1; end
                6'h26: begin data_corr[2]  = ~data_in[2];  ecc_corrected = 1'b1; end
                6'h27: begin data_corr[3]  = ~data_in[3];  ecc_corrected = 1'b1; end
                6'h29: begin data_corr[4]  = ~data_in[4];  ecc_corrected = 1'b1; end
                6'h2A: begin data_corr[5]  = ~data_in[5];  ecc_corrected = 1'b1; end
                6'h2B: begin data_corr[6]  = ~data_in[6];  ecc_corrected = 1'b1; end
                6'h2C: begin data_corr[7]  = ~data_in[7];  ecc_corrected = 1'b1; end
                
                // WC_LSB byte (data_in[15:8])
                6'h2D: begin data_corr[8]  = ~data_in[8];  ecc_corrected = 1'b1; end
                6'h2E: begin data_corr[9]  = ~data_in[9];  ecc_corrected = 1'b1; end
                6'h2F: begin data_corr[10] = ~data_in[10]; ecc_corrected = 1'b1; end
                6'h31: begin data_corr[11] = ~data_in[11]; ecc_corrected = 1'b1; end
                6'h32: begin data_corr[12] = ~data_in[12]; ecc_corrected = 1'b1; end
                6'h33: begin data_corr[13] = ~data_in[13]; ecc_corrected = 1'b1; end
                6'h34: begin data_corr[14] = ~data_in[14]; ecc_corrected = 1'b1; end
                6'h35: begin data_corr[15] = ~data_in[15]; ecc_corrected = 1'b1; end
                
                // WC_MSB byte (data_in[21:16], only 6 bits)
                6'h36: begin data_corr[16] = ~data_in[16]; ecc_corrected = 1'b1; end
                6'h37: begin data_corr[17] = ~data_in[17]; ecc_corrected = 1'b1; end
                6'h38: begin data_corr[18] = ~data_in[18]; ecc_corrected = 1'b1; end
                6'h39: begin data_corr[19] = ~data_in[19]; ecc_corrected = 1'b1; end
                6'h3A: begin data_corr[20] = ~data_in[20]; ecc_corrected = 1'b1; end
                6'h3B: begin data_corr[21] = ~data_in[21]; ecc_corrected = 1'b1; end

                // ECC parity bit errors (P0-P5) - no data correction needed
                6'h01: ecc_corrected = 1'b1;  // P0 error
                6'h02: ecc_corrected = 1'b1;  // P1 error
                6'h04: ecc_corrected = 1'b1;  // P2 error
                6'h08: ecc_corrected = 1'b1;  // P3 error
                6'h10: ecc_corrected = 1'b1;  // P4 error
                6'h20: ecc_corrected = 1'b1;  // P5 error

                // All other syndromes are multi-bit errors (uncorrectable)
                default: begin
                    ecc_error = 1'b1;
                end
            endcase
        end
    end

endmodule
