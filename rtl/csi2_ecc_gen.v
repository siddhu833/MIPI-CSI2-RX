// ============================================================================
// csi2_ecc_gen.v
// Combinational CSI-2 Header ECC Generator (TX side)
//
// Generates the 6-bit ECC parity for a 26-bit header data word.
// Uses IDENTICAL parity equations as csi2_ecc_rx.v so the RX checker
// will always see syndrome = 6'b000000 (ecc_ok = 1) on correct packets.
//
// Port:
//   data_in [25:0] = {reserved[25:22], WC_MSB[21:16], WC_LSB[15:8], DI[7:0]}
//   ecc_out  [5:0] = generated ECC parity bits (put into header byte 4)
// ============================================================================

module csi2_ecc_gen (
    input  wire [25:0] data_in,   // {2'b00, WC_MSB[5:0], WC_LSB[7:0], DI[7:0]}
    output wire  [5:0] ecc_out    // Generated ECC — identical equations to RX checker
);

    // Same parity equations as csi2_ecc_rx so syndrome = 0 on valid packets
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
