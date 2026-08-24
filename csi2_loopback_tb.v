`timescale 1ns/1ps
// ============================================================================
// csi2_loopback_tb.v — End-to-End Loopback Testbench
//
// Connects csi2_tx directly to csi2_rx_llp_sf:
//   [csi2_tx] ──phy_byte/phy_valid──> [csi2_rx_llp_sf] ──> AXI monitor
//
// No hand-crafted send_byte() calls. The TX hardware generates all packets
// automatically from its 8x8 pixel ROM. The RX hardware decodes them.
// ============================================================================

module csi2_loopback_tb;

    // ── Clock & Reset
    reg clk   = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;  // 100 MHz

    // ── TX → RX wires
    wire [7:0] phy_byte;
    wire       phy_valid;

    // ── RX → AXI wires
    wire [7:0] m_axis_tdata;
    wire       m_axis_tvalid;
    wire       m_axis_tlast;
    wire       ecc_ok;
    wire       ecc_error;
    wire       crc_error;
    wire [7:0] data_id;
    wire       packet_done;

    reg        start   = 0;
    reg [1:0]  format  = 2'd1; // 01=RAW10 test
    wire       tx_done;

    // ── Instantiate TX
    csi2_tx_top tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .format    (format),
        .phy_byte  (phy_byte),
        .phy_valid (phy_valid),
        .tx_done   (tx_done)
    );

    // ── Instantiate RX (Store-and-Forward)
    csi2_rx_llp_sf rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .phy_byte     (phy_byte),
        .phy_valid    (phy_valid),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(1'b1),        // AXI slave always ready
        .m_axis_tlast (m_axis_tlast),
        .ecc_ok       (ecc_ok),
        .ecc_corrected(),
        .ecc_error    (ecc_error),
        .crc_error    (crc_error),
        .data_id      (data_id),
        .packet_done  (packet_done)
    );

    // ── Stimulus
    initial begin
      //  $dumpfile("csi2_loopback.vcd");
      //  $dumpvars(0, csi2_loopback_tb);

        #25;
        rst_n = 1;
        #20;

        // Fire the TX
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        // Wait for TX to finish + extra time for RX to stream out
        wait(tx_done == 1);
        repeat(200) @(posedge clk);

        $display("\n=== Loopback Test Complete ===");
        $finish;
    end

    // ── Monitor: print every AXI byte received
    integer pixel_num = 0;
    always @(posedge clk) begin
        if (m_axis_tvalid) begin
            $display("T=%0t: PIXEL[%0d] = 0x%02h  tlast=%b",
                     $time, pixel_num, m_axis_tdata, m_axis_tlast);
            pixel_num = pixel_num + 1;
        end

        if (packet_done) begin
            $display("T=%0t: PACKET DONE  DI=0x%02h  ecc_ok=%b  crc_error=%b",
                     $time, data_id, ecc_ok, crc_error);
            if (crc_error) begin
                $display("  TX CRC computed = 0x%04h", tx.tx_crc);
                $display("  RX CRC calc     = 0x%04h", rx.crc_calc);
                $display("  *** CRC FAILED — TX or RX bug! ***");
            end
        end

        if (tx_done)
            $display("T=%0t: TX DONE — all %0d packets sent", $time, 10);
    end

endmodule
