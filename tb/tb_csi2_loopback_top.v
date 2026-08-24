`timescale 1ns/1ps
// ============================================================================
// tb_csi2_loopback_top.v — Testbench for the Hardware Synthesizable Top Level
//
// Tests the top wrapper by pulsing start and watching the AXI outputs.
// ============================================================================

module tb_csi2_loopback_top;

    // ── Clocks and Resets
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;  // 100 MHz clock

    // ── DUT Inputs
    reg        start = 0;
    reg [1:0]  format = 2'd1;  // 11 = RAW24 (Color Image Test)

    // ── DUT Outputs
    wire [23:0] px_out;
    wire        px_valid;
    wire        px_last;
    wire        tx_done;
    wire        packet_done;
    wire [7:0] data_id;
    wire       ecc_ok;
    wire       ecc_error;
    wire       crc_error;

    // ── Instantiate the Top Level DUT
    csi2_loopback_top dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .format       (format),
        .px_out       (px_out),
        .px_valid     (px_valid),
        .px_last      (px_last),
        .tx_done      (tx_done),
        .packet_done  (packet_done),
        .data_id      (data_id),
        .ecc_ok       (ecc_ok),
        .ecc_error    (ecc_error),
        .crc_error    (crc_error)
    );

    // ── Image Rebuilder Logger
    integer img_log_fd;
    initial begin
        img_log_fd = $fopen("C:/Users/91778/Desktop/6thproject/csi2_rx/rebuilt_pixels.txt", "w");
    end

    always @(posedge clk) begin
        if (px_valid) begin
            $fdisplay(img_log_fd, "%06X", px_out);
        end
    end

    // ── Stimulus
    initial begin
        $dumpfile("tb_csi2_loopback_top.vcd");
        $dumpvars(0, tb_csi2_loopback_top);

        // Reset sequence
        #25;
        rst_n = 1;
        #20;

        // Trigger TX Generation
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        // Wait for generation to run to completion
        wait(tx_done == 1'b1);
        
        // Let pipeline drain (FIFO + Unpacker latency)
        repeat(150) @(posedge clk);
        
        $fclose(img_log_fd);
        $display("\n=== csi2_loopback_top Test Complete ===");
        $finish;
    end

    // ── Pixel Output Monitor
    integer rx_pixel_count = 0;
    integer px_log_fd;
    
    initial begin
px_log_fd = $fopen("C:/Users/91778/Desktop/6thproject/csi2_rx/rebuilt_data/rebuilt_pixels.txt", "w");
    end

    always @(posedge clk) begin
        if (px_valid) begin
            // $display("T=%0t: [Pixel Unpacked] Data=0x%06h  px_last=%b  (Total Pixels=%0d)",
            //          $time, px_out, px_last, rx_pixel_count);
            // Write hex to the text file for Python processing
            $fdisplay(px_log_fd, "%06x", px_out);
            rx_pixel_count = rx_pixel_count + 1;
        end
        
        if (packet_done) begin
            $display("T=%0t: Packet Finished! DI=0x%02h ECC_OK=%b CRC_ERR=%b", 
                      $time, data_id, ecc_ok, crc_error);
        end

        if (tx_done) begin
            $fclose(px_log_fd);
        end
    end

    // ── PHY Traffic Logger & Packet Tracker
    integer phy_log_fd;
    integer phy_packet_count = 0;
    reg phy_valid_d = 0;

    initial begin
        phy_log_fd = $fopen("C:/Users/91778/Desktop/6thproject/csi2_rx/phy_traffic_log.txt", "w");
    end

    always @(posedge clk) begin
        // Track previous state to detect edges
        phy_valid_d <= dut.phy_valid;

        // Rising Edge: Packet Start
        if (dut.phy_valid && !phy_valid_d) begin
            phy_packet_count = phy_packet_count + 1;
            $fdisplay(phy_log_fd, "\n=== T=%0t: [TX -> PHY] Packet %0d Started ===", $time, phy_packet_count);
        end

        // Log the actual PHY bytes
        if (dut.phy_valid) begin
            $fdisplay(phy_log_fd, "T=%0t: PHY_BYTE = 0x%02h", $time, dut.phy_byte);
        end

        // Falling Edge: Packet Done
        if (!dut.phy_valid && phy_valid_d) begin
            $fdisplay(phy_log_fd, "=== T=%0t: [TX -> PHY] Packet %0d Done ===\n", $time, phy_packet_count);
        end

        if (tx_done) begin
            $fclose(phy_log_fd);
        end
    end

endmodule
