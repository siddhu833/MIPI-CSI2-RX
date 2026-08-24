`timescale 1ns/1ps
// ============================================================================
// csi2_loopback_top.v — Hardware Synthesizable Top Level
//
// Wraps the entire TX and RX into a single module block so you can deploy it
// on an FPGA. You can tie `start` to a button, and monitor the outputs.
//
// The internal "phy" wires never leave the FPGA, proving the logic works 
// locally before adding an external MIPI D-PHY.
// ============================================================================

module csi2_loopback_top (
    input  wire        clk,
    input  wire        rst_n,      // Active-low reset (connect to a button)
    
    // TX Control
    input  wire        start,      // Pulse to start generating a frame
    input  wire [1:0]  format,     // 00=RAW8, 01=RAW10, 10=RAW12, 11=RAW24

    // RX Pixel Output (Unpacked native pixels)
    output wire [23:0] px_out,
    output wire        px_valid,
    output wire        px_last,
    
    // Status / Diagnostics
    output wire        tx_done,
    output wire        packet_done,
    output wire [7:0]  data_id,
    output wire        ecc_ok,
    output wire        ecc_error,
    output wire        crc_error
);

    // ── Internal MIPI byte-level connection (The "Virtual PHY") ──────────────
    wire [7:0] phy_byte;
    wire       phy_valid;

    // ── Transmission (Hardware Image Generator) ──────────────────────────────
    csi2_tx_top tx_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .format    (format),
        .phy_byte  (phy_byte),
        .phy_valid (phy_valid),
        .tx_done   (tx_done)
    );

    // ── Receiver (Store and Forward with ECC/CRC) ────────────────────────────
    wire [7:0] m_axis_tdata;
    wire       m_axis_tvalid;
    wire       m_axis_tready;
    wire       m_axis_tlast;

    csi2_rx_llp_sf rx_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .phy_byte     (phy_byte),
        .phy_valid    (phy_valid),
        
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),
        
        .ecc_ok       (ecc_ok),
        .ecc_corrected(),       // Ignored for now
        .ecc_error    (ecc_error),
        .crc_error    (crc_error),
        .data_id      (data_id),
        .packet_done  (packet_done)
    );

    // ── Unpacker (Convert bytes back to pixels) ──────────────────────────────
    pixel_unpack unpack_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .format       (format),
        
        .s_axis_tdata (m_axis_tdata),
        .s_axis_tvalid(m_axis_tvalid),
        .s_axis_tready(m_axis_tready),
        .s_axis_tlast (m_axis_tlast),
        
        .px_out       (px_out),
        .px_valid     (px_valid),
        .px_last      (px_last)
    );

endmodule
