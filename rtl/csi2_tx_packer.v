`timescale 1ns / 1ps
// ============================================================================
// csi2_tx_packer.v - CSI-2 TX packet packer (RAW8 grayscale)
//
// Pixel input : AXI4-Stream, 8-bit grayscale pixels
//               tuser = start of frame (first pixel), tlast = end of line
// Link output : CSI-2 low-level-protocol byte stream (phy_byte/phy_valid)
//
// Per frame:
//   Frame Start short packet  : DI=0x00, WC=frame number, ECC
//   cfg_height x long packets : DI=0x2A (RAW8), WC=cfg_width,
//                               ECC, payload (cfg_width bytes), CRC-16 (LSB first)
//   Frame End short packet    : DI=0x01, WC=frame number, ECC
// phy_valid is low for IPG cycles between packets (end of HS burst).
//
// The pixel source must deliver a whole line without gaps once the payload
// starts; a gap is reported on tx_underrun.
// ============================================================================

module csi2_tx_packer #(
    parameter IPG = 8                       // idle cycles between packets
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [13:0] cfg_width,           // pixels (= bytes) per line
    input  wire [15:0] cfg_height,          // lines per frame

    // AXI4-Stream pixel input
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

    // CSI-2 byte stream
    output reg  [7:0]  phy_byte,
    output reg         phy_valid,

    // status
    output reg         frame_done,          // 1-cycle pulse after Frame End
    output reg         tx_underrun,         // sticky: pixel gap inside payload
    output reg         tx_tlast_err         // sticky: tlast not at line end
);

    localparam [7:0] DI_FS   = 8'h00;
    localparam [7:0] DI_FE   = 8'h01;
    localparam [7:0] DI_RAW8 = 8'h2A;

    localparam [2:0] S_IDLE    = 3'd0;
    localparam [2:0] S_HDR     = 3'd1;   // 4-byte packet header
    localparam [2:0] S_PAYLOAD = 3'd2;
    localparam [2:0] S_CRC     = 3'd3;
    localparam [2:0] S_GAP     = 3'd4;

    localparam [1:0] PKT_FS   = 2'd0;
    localparam [1:0] PKT_LINE = 2'd1;
    localparam [1:0] PKT_FE   = 2'd2;

    reg [2:0]  state;
    reg [1:0]  pkt;            // packet type being sent
    reg [1:0]  byte_idx;
    reg [13:0] pay_cnt;
    reg [15:0] line_cnt;
    reg [15:0] frame_num;
    reg [7:0]  gap_cnt;

    // ------------------------------------------------------------------------
    // Header fields + ECC
    // ------------------------------------------------------------------------
    wire [7:0]  hdr_di = (pkt == PKT_FS) ? DI_FS : (pkt == PKT_FE) ? DI_FE : DI_RAW8;
    wire [13:0] hdr_wc = (pkt == PKT_LINE) ? cfg_width : frame_num[13:0];
    wire [5:0]  hdr_ecc;

    csi2_ecc_gen u_ecc_gen (
        .data_in ({4'b0, hdr_wc[13:8], hdr_wc[7:0], hdr_di}),
        .ecc_out (hdr_ecc)
    );

    // ------------------------------------------------------------------------
    // Payload handshake + CRC
    // ------------------------------------------------------------------------
    assign s_axis_tready = (state == S_PAYLOAD);
    wire   pix_hs        = s_axis_tvalid && s_axis_tready;
    wire   last_pixel    = (pay_cnt == cfg_width - 14'd1);

    wire [15:0] crc_val;
    wire        crc_init = (state == S_HDR) && (byte_idx == 2'd0);

    crc16_1021 u_crc (
        .clk        (clk),
        .rst_n      (rst_n),
        .init       (crc_init),
        .data_valid (pix_hs),
        .data_in    (s_axis_tdata),
        .crc_out    (crc_val)
    );

    // ------------------------------------------------------------------------
    // Packet FSM
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            pkt          <= PKT_FS;
            byte_idx     <= 2'd0;
            pay_cnt      <= 14'd0;
            line_cnt     <= 16'd0;
            frame_num    <= 16'd0;
            gap_cnt      <= 8'd0;
            phy_byte     <= 8'd0;
            phy_valid    <= 1'b0;
            frame_done   <= 1'b0;
            tx_underrun  <= 1'b0;
            tx_tlast_err <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            case (state)
                // wait for the first pixel of a frame
                S_IDLE: begin
                    phy_valid <= 1'b0;
                    if (s_axis_tvalid && s_axis_tuser) begin
                        frame_num <= frame_num + 16'd1;
                        line_cnt  <= 16'd0;
                        pkt       <= PKT_FS;
                        byte_idx  <= 2'd0;
                        state     <= S_HDR;
                    end
                end

                // DI, WC LSB, WC MSB, ECC
                S_HDR: begin
                    phy_valid <= 1'b1;
                    case (byte_idx)
                        2'd0: phy_byte <= hdr_di;
                        2'd1: phy_byte <= hdr_wc[7:0];
                        2'd2: phy_byte <= {2'b00, hdr_wc[13:8]};
                        2'd3: phy_byte <= {2'b00, hdr_ecc};
                    endcase
                    byte_idx <= byte_idx + 2'd1;
                    if (byte_idx == 2'd3) begin
                        pay_cnt <= 14'd0;
                        if (pkt == PKT_LINE) begin
                            state <= S_PAYLOAD;
                        end else begin
                            gap_cnt <= IPG;
                            state   <= S_GAP;
                        end
                    end
                end

                S_PAYLOAD: begin
                    if (pix_hs) begin
                        phy_byte  <= s_axis_tdata;
                        phy_valid <= 1'b1;
                        pay_cnt   <= pay_cnt + 14'd1;
                        if (s_axis_tlast != last_pixel)
                            tx_tlast_err <= 1'b1;
                        if (last_pixel) begin
                            byte_idx <= 2'd0;
                            state    <= S_CRC;
                        end
                    end else begin
                        phy_valid   <= 1'b0;
                        tx_underrun <= 1'b1;
                    end
                end

                // CRC LSB then MSB
                S_CRC: begin
                    phy_valid <= 1'b1;
                    if (byte_idx == 2'd0) begin
                        phy_byte <= crc_val[7:0];
                        byte_idx <= 2'd1;
                    end else begin
                        phy_byte <= crc_val[15:8];
                        line_cnt <= line_cnt + 16'd1;
                        gap_cnt  <= IPG;
                        state    <= S_GAP;
                    end
                end

                // inter-packet gap, then choose the next packet
                S_GAP: begin
                    phy_valid <= 1'b0;
                    if (gap_cnt != 8'd0) begin
                        gap_cnt <= gap_cnt - 8'd1;
                    end else if (pkt == PKT_FE) begin
                        frame_done <= 1'b1;
                        state      <= S_IDLE;
                    end else begin
                        byte_idx <= 2'd0;
                        pkt      <= (line_cnt == cfg_height) ? PKT_FE : PKT_LINE;
                        state    <= S_HDR;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
