`timescale 1ns / 1ps
// ============================================================================
// csi2_ecc_rx.v - CSI-2 packet header ECC checker / corrector (RX side)
//
//  syndrome = recomputed ECC xor received ECC
//    0                -> header OK
//    single-bit match -> bit corrected (ecc_corrected)
//    anything else    -> uncorrectable multi-bit error (ecc_error)
// Purely combinational.
// ============================================================================

module csi2_ecc_rx (
    input  wire [25:0] data_in,    // {4'b0, WC[13:8], WC[7:0], DI}
    input  wire [5:0]  ecc_rx,     // received ECC byte [5:0]

    output reg  [25:0] data_corr,  // corrected header
    output reg         ecc_ok,
    output reg         ecc_corrected,
    output reg         ecc_error
);

    wire [5:0] ecc_calc;
    wire [5:0] syndrome;

    csi2_ecc_gen u_ecc_calc (
        .data_in (data_in),
        .ecc_out (ecc_calc)
    );

    assign syndrome = ecc_calc ^ ecc_rx;

    always @(*) begin
        data_corr     = data_in;
        ecc_ok        = 1'b0;
        ecc_corrected = 1'b0;
        ecc_error     = 1'b0;

        if (syndrome == 6'h00) begin
            ecc_ok = 1'b1;
        end else begin
            case (syndrome)
                // DI byte
                6'h23: begin data_corr[0]  = ~data_in[0];  ecc_corrected = 1'b1; end
                6'h25: begin data_corr[1]  = ~data_in[1];  ecc_corrected = 1'b1; end
                6'h26: begin data_corr[2]  = ~data_in[2];  ecc_corrected = 1'b1; end
                6'h27: begin data_corr[3]  = ~data_in[3];  ecc_corrected = 1'b1; end
                6'h29: begin data_corr[4]  = ~data_in[4];  ecc_corrected = 1'b1; end
                6'h2A: begin data_corr[5]  = ~data_in[5];  ecc_corrected = 1'b1; end
                6'h2B: begin data_corr[6]  = ~data_in[6];  ecc_corrected = 1'b1; end
                6'h2C: begin data_corr[7]  = ~data_in[7];  ecc_corrected = 1'b1; end
                // WC LSB
                6'h2D: begin data_corr[8]  = ~data_in[8];  ecc_corrected = 1'b1; end
                6'h2E: begin data_corr[9]  = ~data_in[9];  ecc_corrected = 1'b1; end
                6'h2F: begin data_corr[10] = ~data_in[10]; ecc_corrected = 1'b1; end
                6'h31: begin data_corr[11] = ~data_in[11]; ecc_corrected = 1'b1; end
                6'h32: begin data_corr[12] = ~data_in[12]; ecc_corrected = 1'b1; end
                6'h33: begin data_corr[13] = ~data_in[13]; ecc_corrected = 1'b1; end
                6'h34: begin data_corr[14] = ~data_in[14]; ecc_corrected = 1'b1; end
                6'h35: begin data_corr[15] = ~data_in[15]; ecc_corrected = 1'b1; end
                // WC MSB (6 bits)
                6'h36: begin data_corr[16] = ~data_in[16]; ecc_corrected = 1'b1; end
                6'h37: begin data_corr[17] = ~data_in[17]; ecc_corrected = 1'b1; end
                6'h38: begin data_corr[18] = ~data_in[18]; ecc_corrected = 1'b1; end
                6'h39: begin data_corr[19] = ~data_in[19]; ecc_corrected = 1'b1; end
                6'h3A: begin data_corr[20] = ~data_in[20]; ecc_corrected = 1'b1; end
                6'h3B: begin data_corr[21] = ~data_in[21]; ecc_corrected = 1'b1; end
                // error in one of the parity bits themselves
                6'h01, 6'h02, 6'h04,
                6'h08, 6'h10, 6'h20: ecc_corrected = 1'b1;
                // multi-bit error
                default: ecc_error = 1'b1;
            endcase
        end
    end

endmodule
