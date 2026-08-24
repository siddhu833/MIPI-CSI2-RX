`timescale 1ns/1ps

module tb_csi2_rx_llp;

    reg clk;
    reg rst_n;

    reg  [7:0] phy_byte;
    reg        phy_valid;

    wire [7:0] m_axis_tdata;
    wire       m_axis_tvalid;
    reg        m_axis_tready;
    wire       m_axis_tlast;

    wire       ecc_ok;
    wire       ecc_corrected;
    wire       ecc_error;
    wire       crc_error; // IMPORTANT: I added this so you can monitor it!
    wire [7:0] data_id;
    wire       packet_done;

    // Instantiate the DUT (Store-and-Forward Version)
    csi2_rx_llp_sf dut (
        .clk(clk),
        .rst_n(rst_n),
        .phy_byte(phy_byte),
        .phy_valid(phy_valid),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .ecc_ok(ecc_ok),
        .ecc_corrected(ecc_corrected),
        .ecc_error(ecc_error),
        .crc_error(crc_error),
        .data_id(data_id),
        .packet_done(packet_done)
    );

    // 100MHz Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task to pulse phy_valid and send 1 byte
    task send_byte(input [7:0] b);
        begin
            @(posedge clk);
            phy_valid <= 1;
            phy_byte  <= b;
        end
    endtask

    // Task to clear phy_valid to simulate gaps
    task end_packet();
        begin
            @(posedge clk);
            phy_valid <= 0;
            phy_byte  <= 8'h00;
            
            // For Store-and-Forward: Wait until the packet is completely done being processed!
            // Either wait for packet_done signal, or a large timeout to prevent hanging.
            wait(packet_done == 1'b1);
            
            // Add a padding of idles before the next packet can arrive
            repeat(10) @(posedge clk);
        end
    endtask

    initial begin
       // $dumpfile("csi2_rx_llp.vcd");
       // $dumpvars(0, tb_csi2_rx_llp);

        rst_n = 0;
        phy_valid = 0;
        phy_byte = 0;
        m_axis_tready = 1; // AXI slave is ready

        #20;
        @(posedge clk);
        rst_n = 1;

        #20;

        // ---------------- PACKET 1 ----------------
        $display("\n=== LONG PACKET 1 (WC=4, DI=0x4A) ===");
        send_byte(8'h4A); // DI
        send_byte(8'h04); // WC LSB
        send_byte(8'h00); // WC MSB
        send_byte(8'h06); // ECC
        // Payload (4 bytes)
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h03);
        send_byte(8'h04);
        // CRC (2 bytes) REQUIRED FOR LONG PACKET
        send_byte(8'h63); // CRC LSB
        send_byte(8'h76); // CRC MSB
        end_packet();

        // ---------------- PACKET 2 ----------------
        $display("\n=== LONG PACKET 2 (WC=4, DI=0x11) ===");
        send_byte(8'h11); // DI
        send_byte(8'h04); // WC LSB
        send_byte(8'h00); // WC MSB
        send_byte(8'h25); // ECC
        // Payload (4 bytes)
        send_byte(8'h05);
        send_byte(8'h06);
        send_byte(8'h07);
        send_byte(8'h08);
        // CRC (2 bytes)
        send_byte(8'h5E); // CRC LSB
        send_byte(8'hF7); // CRC MSB
        end_packet();
        
        // ---------------- PACKET 3 ----------------
        $display("\n=== LONG PACKET 3 (WC=6, DI=0x2A) ===");
        send_byte(8'h2A); // DI
        send_byte(8'h06); // WC LSB
        send_byte(8'h00); // WC MSB
        send_byte(8'h29); // ECC
        // Payload (6 bytes)
        send_byte(8'h0A);
        send_byte(8'h0B);
        send_byte(8'h0C);
        send_byte(8'h0D);
        send_byte(8'h0E);
        send_byte(8'h0F);
        // CRC (2 bytes)
        send_byte(8'h36); // CRC LSB
        send_byte(8'h7C); // CRC MSB
        end_packet();

        // ---------------- PACKET 4 ----------------
        $display("\n=== LONG PACKET 4 (WC=1, DI=0x30) ===");
        send_byte(8'h30); // DI
        send_byte(8'h01); // WC LSB
        send_byte(8'h00); // WC MSB
        send_byte(8'h2E); // ECC
        // Payload (1 byte)
        send_byte(8'h07);
        // CRC (2 bytes)
        send_byte(8'hDE); // CRC LSB
        send_byte(8'h1C); // CRC MSB
        end_packet();

        // ---------------- PACKET 5 ----------------
        $display("\n=== LONG PACKET 5 (WC=8, DI=0x3E) ===");
        send_byte(8'h3E); // DI
        send_byte(8'h08); // WC LSB
        send_byte(8'h00); // WC MSB
        send_byte(8'h16); // ECC
        // Payload (8 bytes)
        send_byte(8'h00);
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h03);
        send_byte(8'h04);
        send_byte(8'h05);
        send_byte(8'h06);
        send_byte(8'h07);
        // CRC (2 bytes)
        send_byte(8'hB9); // CRC LSB
        send_byte(8'hBF); // CRC MSB
        end_packet();
        
        // Wait long enough for the final packet to stream out of the FIFO
        repeat(50) @(posedge clk);

        $display("\n=== Test Complete ===");
        $finish;
    end

    // Monitor outputs
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready)
            $display("T=%0t: AXI OUT: tdata=0x%02h, tlast=%b",
                     $time, m_axis_tdata, m_axis_tlast);

        if (packet_done) begin
            $display("T=%0t: PACKET DONE: DI=0x%02h, ecc_ok=%b, ecc_error=%b",
                     $time, data_id, ecc_ok, ecc_error);
            if (crc_error)
                $display("       -> [ERROR] CRC FAILED! (Calculated by DUT: 0x%04h, Expected in TB: 0xAABB) Update Dummy CRCs in testbench!", dut.crc_calc);
            else
                $display("       -> [SUCCESS] CRC PASSED!");
        end
    end

endmodule
