`timescale 1ns / 1ps
// ============================================================================
// csi2_ecc_gen.v - CSI-2 packet header ECC generator (TX side)
//
// 6-bit Hamming parity over the 24-bit packet header {WC, DI}.
//   data_in[25:0] = {4'b0, WC[13:8], WC[7:0], DI[7:0]}
// Uses the same parity equations as csi2_ecc_rx, so a clean header gives
// syndrome 0 at the receiver.
// ============================================================================

module csi2_ecc_gen (
    input  wire [25:0] data_in,
    output wire [5:0]  ecc_out
);

    assign ecc_out[0] = data_in[0]  ^ data_in[1]  ^ data_in[3]  ^
                        data_in[4]  ^ data_in[6]  ^ data_in[8]  ^
                        data_in[10] ^ data_in[11] ^ data_in[13] ^
                        data_in[15] ^ data_in[17] ^ data_in[19] ^
                        data_in[21] ^ data_in[23] ^ data_in[25];

    assign ecc_out[1] = data_in[0]  ^ data_in[2]  ^ data_in[3]  ^
                        data_in[5]  ^ data_in[6]  ^ data_in[9]  ^
                        data_in[10] ^ data_in[12] ^ data_in[13] ^
                        data_in[16] ^ data_in[17] ^ data_in[20] ^
                        data_in[21] ^ data_in[24] ^ data_in[25];

    assign ecc_out[2] = data_in[1]  ^ data_in[2]  ^ data_in[3]  ^
                        data_in[7]  ^ data_in[8]  ^ data_in[9]  ^
                        data_in[10] ^ data_in[14] ^ data_in[15] ^
                        data_in[16] ^ data_in[17] ^ data_in[22] ^
                        data_in[23] ^ data_in[24] ^ data_in[25];

    assign ecc_out[3] = data_in[4]  ^ data_in[5]  ^ data_in[6]  ^
                        data_in[7]  ^ data_in[8]  ^ data_in[9]  ^
                        data_in[10] ^ data_in[18] ^ data_in[19] ^
                        data_in[20] ^ data_in[21] ^ data_in[22] ^
                        data_in[23] ^ data_in[24] ^ data_in[25];

    assign ecc_out[4] = data_in[11] ^ data_in[12] ^ data_in[13] ^
                        data_in[14] ^ data_in[15] ^ data_in[16] ^
                        data_in[17] ^ data_in[18] ^ data_in[19] ^
                        data_in[20] ^ data_in[21] ^ data_in[22] ^
                        data_in[23] ^ data_in[24] ^ data_in[25];

    assign ecc_out[5] = data_in[0]  ^ data_in[1]  ^ data_in[2]  ^
                        data_in[3]  ^ data_in[4]  ^ data_in[5]  ^
                        data_in[6]  ^ data_in[7]  ^ data_in[8]  ^
                        data_in[9]  ^ data_in[10] ^ data_in[11] ^
                        data_in[12] ^ data_in[13] ^ data_in[14] ^
                        data_in[15] ^ data_in[16] ^ data_in[17] ^
                        data_in[18] ^ data_in[19];

endmodule
