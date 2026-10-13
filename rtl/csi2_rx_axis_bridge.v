`timescale 1ns / 1ps
// ============================================================================
// csi2_rx_axis_bridge.v - MIPI CSI-2 RX to AXI4-Stream bridge (RAW8)
//
//   phy_byte @ clk_byte --> csi2_rx_llp (ECC check, CRC check, cut-through)
//                       --> axis_async_fifo (clk_byte -> clk_axi, CDC)
//                       --> AXI4-Stream video master @ clk_axi
//
//   m_axis_tdata  : 8-bit grayscale pixel
//   m_axis_tuser  : [0] start of frame (first pixel), [1] line CRC/length error
//   m_axis_tlast  : end of line
//
// Clock / reset domains
//   clk_byte : CSI-2 byte clock (receiver, FIFO write side, error counters)
//   clk_axi  : SoC AXI clock    (FIFO read side, AXI4-Stream, sticky flags)
//   rst_n    : asynchronous, synchronized separately into each domain
// ============================================================================

module csi2_rx_axis_bridge #(
    parameter FIFO_DEPTH = 64
)(
    input  wire        clk_byte,
    input  wire        clk_axi,
    input  wire        rst_n,

    // CSI-2 byte stream from the PHY
    input  wire [7:0]  phy_byte,
    input  wire        phy_valid,

    // AXI4-Stream master @ clk_axi
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,
    output wire [1:0]  m_axis_tuser,

    // status @ clk_byte (counters)
    output reg  [15:0] frame_cnt,
    output reg  [15:0] line_cnt,
    output reg  [15:0] ecc_corr_cnt,
    output reg  [15:0] ecc_err_cnt,
    output reg  [15:0] crc_err_cnt,

    // status @ clk_axi (sticky flags, synchronized)
    output wire        sts_ecc_err,
    output wire        sts_crc_err,
    output wire        sts_overflow
);

    // ------------------------------------------------------------------------
    // Reset synchronizers (one per clock domain)
    // ------------------------------------------------------------------------
    wire rst_byte_n;
    wire rst_axi_n;

    rst_sync u_rst_byte (.clk(clk_byte), .arst_n(rst_n), .srst_n(rst_byte_n));
    rst_sync u_rst_axi  (.clk(clk_axi),  .arst_n(rst_n), .srst_n(rst_axi_n));

    // ------------------------------------------------------------------------
    // CSI-2 low-level protocol receiver @ clk_byte
    // ------------------------------------------------------------------------
    wire [7:0]  rx_data;
    wire        rx_valid, rx_last, rx_sof, rx_err;
    wire [7:0]  rx_data_id;
    wire [15:0] rx_word_count;
    wire        rx_frame_start, rx_frame_end, rx_line_done;
    wire        rx_ecc_corrected, rx_ecc_error, rx_crc_error, rx_truncated;

    csi2_rx_llp u_rx_llp (
        .clk           (clk_byte),
        .rst_n         (rst_byte_n),
        .phy_byte      (phy_byte),
        .phy_valid     (phy_valid),
        .out_data      (rx_data),
        .out_valid     (rx_valid),
        .out_last      (rx_last),
        .out_sof       (rx_sof),
        .out_err       (rx_err),
        .data_id       (rx_data_id),
        .word_count    (rx_word_count),
        .frame_start   (rx_frame_start),
        .frame_end     (rx_frame_end),
        .line_done     (rx_line_done),
        .ecc_corrected (rx_ecc_corrected),
        .ecc_error     (rx_ecc_error),
        .crc_error     (rx_crc_error),
        .pkt_truncated (rx_truncated)
    );

    // ------------------------------------------------------------------------
    // Clock-domain crossing FIFO: {err, sof, last, data}
    // ------------------------------------------------------------------------
    wire [10:0] fifo_out;
    wire        fifo_full;
    wire        fifo_overflow;

    axis_async_fifo #(
        .WIDTH (11),
        .DEPTH (FIFO_DEPTH)
    ) u_cdc_fifo (
        .s_clk         (clk_byte),
        .s_rst_n       (rst_byte_n),
        .s_data        ({rx_err, rx_sof, rx_last, rx_data}),
        .s_valid       (rx_valid),
        .s_full        (fifo_full),
        .s_overflow    (fifo_overflow),

        .m_clk         (clk_axi),
        .m_rst_n       (rst_axi_n),
        .m_axis_tdata  (fifo_out),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready)
    );

    assign m_axis_tdata = fifo_out[7:0];
    assign m_axis_tlast = fifo_out[8];
    assign m_axis_tuser = {fifo_out[10], fifo_out[9]};

    // ------------------------------------------------------------------------
    // Counters + sticky error flags @ clk_byte
    // ------------------------------------------------------------------------
    reg ecc_err_flag, crc_err_flag, ovf_flag;

    always @(posedge clk_byte or negedge rst_byte_n) begin
        if (!rst_byte_n) begin
            frame_cnt    <= 16'd0;
            line_cnt     <= 16'd0;
            ecc_corr_cnt <= 16'd0;
            ecc_err_cnt  <= 16'd0;
            crc_err_cnt  <= 16'd0;
            ecc_err_flag <= 1'b0;
            crc_err_flag <= 1'b0;
            ovf_flag     <= 1'b0;
        end else begin
            if (rx_frame_end)     frame_cnt    <= frame_cnt + 16'd1;
            if (rx_line_done)     line_cnt     <= line_cnt + 16'd1;
            if (rx_ecc_corrected) ecc_corr_cnt <= ecc_corr_cnt + 16'd1;
            if (rx_ecc_error)     ecc_err_cnt  <= ecc_err_cnt + 16'd1;
            if (rx_crc_error)     crc_err_cnt  <= crc_err_cnt + 16'd1;
            if (rx_ecc_error)     ecc_err_flag <= 1'b1;
            if (rx_crc_error)     crc_err_flag <= 1'b1;
            if (fifo_overflow)    ovf_flag     <= 1'b1;
        end
    end

    // single-bit level flags -> clk_axi through 2-flop synchronizers
    sync_2ff #(.width(3)) u_sts_sync (
        .clk (clk_axi),
        .rst_n (rst_axi_n),
        .in  ({ovf_flag, crc_err_flag, ecc_err_flag}),
        .q   ({sts_overflow, sts_crc_err, sts_ecc_err})
    );

endmodule
