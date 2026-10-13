`timescale 1ns / 1ps
// ============================================================================
// csi2_loopback_top.v - CSI-2 TX packer looped back into the RX bridge
//
//   pixels (AXI4-Stream, clk_byte) --> csi2_tx_packer (ECC gen + CRC)
//        --> CSI-2 link bytes (^ phy_err_mask for fault injection)
//        --> csi2_rx_axis_bridge --> pixels (AXI4-Stream, clk_axi)
//
// phy_err_mask : XORed onto the link byte to inject bit errors in test;
//                tie to 8'h00 in hardware.
// ============================================================================

module csi2_loopback_top #(
    parameter IPG        = 8,
    parameter FIFO_DEPTH = 64
)(
    input  wire        clk_byte,
    input  wire        clk_axi,
    input  wire        rst_n,

    input  wire [13:0] cfg_width,
    input  wire [15:0] cfg_height,

    // pixel source @ clk_byte
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

    // link fault injection
    input  wire [7:0]  phy_err_mask,

    // pixel sink @ clk_axi
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,
    output wire [1:0]  m_axis_tuser,

    // TX status @ clk_byte
    output wire        tx_frame_done,
    output wire        tx_underrun,
    output wire        tx_tlast_err,

    // RX status
    output wire [15:0] frame_cnt,
    output wire [15:0] line_cnt,
    output wire [15:0] ecc_corr_cnt,
    output wire [15:0] ecc_err_cnt,
    output wire [15:0] crc_err_cnt,
    output wire        sts_ecc_err,
    output wire        sts_crc_err,
    output wire        sts_overflow
);

    wire rst_tx_n;
    rst_sync u_rst_tx (.clk(clk_byte), .arst_n(rst_n), .srst_n(rst_tx_n));

    wire [7:0] tx_byte;
    wire       tx_valid;

    csi2_tx_packer #(
        .IPG (IPG)
    ) u_tx (
        .clk           (clk_byte),
        .rst_n         (rst_tx_n),
        .cfg_width     (cfg_width),
        .cfg_height    (cfg_height),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tuser  (s_axis_tuser),
        .phy_byte      (tx_byte),
        .phy_valid     (tx_valid),
        .frame_done    (tx_frame_done),
        .tx_underrun   (tx_underrun),
        .tx_tlast_err  (tx_tlast_err)
    );

    csi2_rx_axis_bridge #(
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_rx (
        .clk_byte      (clk_byte),
        .clk_axi       (clk_axi),
        .rst_n         (rst_n),
        .phy_byte      (tx_byte ^ phy_err_mask),
        .phy_valid     (tx_valid),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast),
        .m_axis_tuser  (m_axis_tuser),
        .frame_cnt     (frame_cnt),
        .line_cnt      (line_cnt),
        .ecc_corr_cnt  (ecc_corr_cnt),
        .ecc_err_cnt   (ecc_err_cnt),
        .crc_err_cnt   (crc_err_cnt),
        .sts_ecc_err   (sts_ecc_err),
        .sts_crc_err   (sts_crc_err),
        .sts_overflow  (sts_overflow)
    );

endmodule
