`timescale 1ns / 1ps
// ============================================================================
// csi2_rx_llp.v - CSI-2 RX low-level protocol (cut-through)
//
//  * Captures the 4-byte packet header, checks/corrects it with ECC
//      - single-bit error : corrected, packet accepted (ecc_corrected)
//      - multi-bit error  : packet discarded until end of burst (ecc_error)
//  * Short packets: Frame Start / Frame End
//  * Long packets : payload forwarded byte by byte (cut-through) while the
//    CRC-16 is computed on the fly; the received CRC is compared at the end
//  * The last payload byte is held back by one stage so it can be tagged
//    with the CRC result: out_last=1 and out_err=1 on a bad line
//  * phy_valid low = end of HS burst: an unfinished packet is closed and
//    reported on pkt_truncated
// ============================================================================

module csi2_rx_llp (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  phy_byte,
    input  wire        phy_valid,

    // payload byte stream
    output reg  [7:0]  out_data,
    output reg         out_valid,
    output reg         out_last,     // last byte of a line
    output reg         out_sof,      // first byte of a frame
    output reg         out_err,      // line failed CRC / was truncated (with out_last)

    // header / status (1-cycle pulses unless noted)
    output reg  [7:0]  data_id,      // last accepted DI (level)
    output reg  [15:0] word_count,   // last accepted WC (level)
    output reg         frame_start,
    output reg         frame_end,
    output reg         line_done,
    output reg         ecc_corrected,
    output reg         ecc_error,
    output reg         crc_error,
    output reg         pkt_truncated
);

    localparam [7:0] DI_FS = 8'h00;
    localparam [7:0] DI_FE = 8'h01;

    localparam [2:0] S_IDLE    = 3'd0;
    localparam [2:0] S_HDR     = 3'd1;
    localparam [2:0] S_PAYLOAD = 3'd2;
    localparam [2:0] S_CRC_LSB = 3'd3;
    localparam [2:0] S_CRC_MSB = 3'd4;
    localparam [2:0] S_DISCARD = 3'd5;

    reg [2:0]  state;
    reg [1:0]  hdr_cnt;
    reg [7:0]  hdr_b0, hdr_b1, hdr_b2;
    reg [15:0] pay_cnt;
    reg [15:0] wc_q;
    reg [7:0]  crc_lsb;
    reg        sof_pending;

    // one-byte hold stage
    reg [7:0]  pend_data;
    reg        pend_valid;
    reg        pend_sof;

    // ------------------------------------------------------------------------
    // Header ECC (4th header byte is the live phy_byte)
    // ------------------------------------------------------------------------
    wire [25:0] hdr_corr;
    wire        ecc_ok_w, ecc_corr_w, ecc_err_w;

    csi2_ecc_rx u_ecc (
        .data_in       ({4'b0, hdr_b2[5:0], hdr_b1, hdr_b0}),
        .ecc_rx        (phy_byte[5:0]),
        .data_corr     (hdr_corr),
        .ecc_ok        (ecc_ok_w),
        .ecc_corrected (ecc_corr_w),
        .ecc_error     (ecc_err_w)
    );

    wire [7:0]  hdr_di   = hdr_corr[7:0];
    wire [15:0] hdr_wc   = {2'b00, hdr_corr[21:8]};
    wire        hdr_last = (state == S_HDR) && (hdr_cnt == 2'd3) && phy_valid;
    wire        is_long  = (hdr_di >= 8'h10);

    // ------------------------------------------------------------------------
    // Payload CRC
    // ------------------------------------------------------------------------
    wire [15:0] crc_calc;

    crc16_1021 u_crc (
        .clk        (clk),
        .rst_n      (rst_n),
        .init       (hdr_last),
        .data_valid ((state == S_PAYLOAD) && phy_valid),
        .data_in    (phy_byte),
        .crc_out    (crc_calc)
    );

    wire crc_bad = ({phy_byte, crc_lsb} != crc_calc);

    // ------------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            hdr_cnt       <= 2'd0;
            hdr_b0        <= 8'd0;
            hdr_b1        <= 8'd0;
            hdr_b2        <= 8'd0;
            pay_cnt       <= 16'd0;
            wc_q          <= 16'd0;
            crc_lsb       <= 8'd0;
            sof_pending   <= 1'b0;
            pend_data     <= 8'd0;
            pend_valid    <= 1'b0;
            pend_sof      <= 1'b0;
            out_data      <= 8'd0;
            out_valid     <= 1'b0;
            out_last      <= 1'b0;
            out_sof       <= 1'b0;
            out_err       <= 1'b0;
            data_id       <= 8'd0;
            word_count    <= 16'd0;
            frame_start   <= 1'b0;
            frame_end     <= 1'b0;
            line_done     <= 1'b0;
            ecc_corrected <= 1'b0;
            ecc_error     <= 1'b0;
            crc_error     <= 1'b0;
            pkt_truncated <= 1'b0;
        end else begin
            out_valid     <= 1'b0;
            out_last      <= 1'b0;
            out_sof       <= 1'b0;
            out_err       <= 1'b0;
            frame_start   <= 1'b0;
            frame_end     <= 1'b0;
            line_done     <= 1'b0;
            ecc_corrected <= 1'b0;
            ecc_error     <= 1'b0;
            crc_error     <= 1'b0;
            pkt_truncated <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (phy_valid) begin
                        hdr_b0  <= phy_byte;
                        hdr_cnt <= 2'd1;
                        state   <= S_HDR;
                    end
                end

                S_HDR: begin
                    if (!phy_valid) begin
                        pkt_truncated <= 1'b1;
                        state         <= S_IDLE;
                    end else begin
                        case (hdr_cnt)
                            2'd1: begin
                                hdr_b1  <= phy_byte;
                                hdr_cnt <= 2'd2;
                            end
                            2'd2: begin
                                hdr_b2  <= phy_byte;
                                hdr_cnt <= 2'd3;
                            end
                            default: begin
                                // 4th byte = ECC: check header
                                ecc_corrected <= ecc_corr_w;
                                if (ecc_err_w) begin
                                    ecc_error <= 1'b1;
                                    state     <= S_DISCARD;
                                end else begin
                                    data_id    <= hdr_di;
                                    word_count <= hdr_wc;
                                    if (!is_long) begin
                                        if (hdr_di == DI_FS) begin
                                            frame_start <= 1'b1;
                                            sof_pending <= 1'b1;
                                        end
                                        if (hdr_di == DI_FE)
                                            frame_end <= 1'b1;
                                        state <= S_IDLE;
                                    end else begin
                                        wc_q       <= hdr_wc;
                                        pay_cnt    <= 16'd0;
                                        pend_valid <= 1'b0;
                                        state      <= (hdr_wc == 16'd0) ? S_CRC_LSB : S_PAYLOAD;
                                    end
                                end
                            end
                        endcase
                    end
                end

                S_PAYLOAD: begin
                    if (!phy_valid) begin
                        // burst ended early: close the line as bad
                        out_data      <= pend_data;
                        out_valid     <= pend_valid;
                        out_sof       <= pend_sof;
                        out_last      <= pend_valid;
                        out_err       <= pend_valid;
                        pend_valid    <= 1'b0;
                        pkt_truncated <= 1'b1;
                        state         <= S_IDLE;
                    end else begin
                        // forward the previous byte, hold the new one
                        out_data   <= pend_data;
                        out_valid  <= pend_valid;
                        out_sof    <= pend_sof;
                        pend_data  <= phy_byte;
                        pend_valid <= 1'b1;
                        pend_sof   <= sof_pending;
                        sof_pending <= 1'b0;
                        pay_cnt    <= pay_cnt + 16'd1;
                        if (pay_cnt == wc_q - 16'd1)
                            state <= S_CRC_LSB;
                    end
                end

                S_CRC_LSB: begin
                    if (!phy_valid) begin
                        out_data      <= pend_data;
                        out_valid     <= pend_valid;
                        out_sof       <= pend_sof;
                        out_last      <= pend_valid;
                        out_err       <= pend_valid;
                        pend_valid    <= 1'b0;
                        pkt_truncated <= 1'b1;
                        state         <= S_IDLE;
                    end else begin
                        crc_lsb <= phy_byte;
                        state   <= S_CRC_MSB;
                    end
                end

                S_CRC_MSB: begin
                    // release the held last byte tagged with the CRC result
                    out_data   <= pend_data;
                    out_valid  <= pend_valid;
                    out_sof    <= pend_sof;
                    out_last   <= pend_valid;
                    pend_valid <= 1'b0;
                    state      <= S_IDLE;
                    if (!phy_valid) begin
                        out_err       <= pend_valid;
                        pkt_truncated <= 1'b1;
                    end else begin
                        out_err   <= pend_valid && crc_bad;
                        crc_error <= crc_bad;
                        line_done <= 1'b1;
                    end
                end

                // uncorrectable header: drop bytes until the burst ends
                S_DISCARD: begin
                    if (!phy_valid)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
