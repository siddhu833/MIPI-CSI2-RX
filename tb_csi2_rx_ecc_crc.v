    // Helper function to calculate CRC-16 (CCITT 0x1021)
    function [15:0] calculate_crc(input [31:0] payload);
        reg [15:0] crc;
        integer i, j;
        reg [7:0] b;
        reg feedback;
        begin
            crc = 16'hFFFF;
            for (i = 0; i < 4; i = i + 1) begin
                if (i == 0) b = payload[7:0];
                else if (i == 1) b = payload[15:8];
                else if (i == 2) b = payload[23:16];
                else b = payload[31:24];
                
                for (j = 0; j < 8; j = j + 1) begin
                    feedback = b[j] ^ crc[15];
                    crc = {crc[14:0], 1'b0};
                    if (feedback) begin
                        crc = crc ^ 16'h1021;
                    end
                end
            end
            calculate_crc = crc;
        end
    endfunction

    task send_phy_byte(input [7:0] b);
        begin
            phy_byte = b;
            phy_valid = 1;
            @(posedge clk);
            #1;
            phy_valid = 0;
        end
    endtask

    task send_packet(input [7:0] data_id, input [31:0] payload);
        begin
            // Header: DI, WC=4
            send_phy_byte(data_id);
            send_phy_byte(8'h04);
            send_phy_byte(8'h00);
            send_phy_byte({2'b00, calculate_ecc({8'h00, 8'h04, data_id})});

            // Payload
            send_phy_byte(payload[7:0]);
            send_phy_byte(payload[15:8]);
            send_phy_byte(payload[23:16]);
            send_phy_byte(payload[31:24]);

            // CRC
            send_phy_byte(calculate_crc(payload) & 8'hFF);
            send_phy_byte((calculate_crc(payload) >> 8) & 8'hFF);
        end
    endtask

    initial begin
        clk = 0;
        clk_axi = 0;
        rst_n = 0;
        phy_byte = 0;
        phy_valid = 0;

        #20;
        rst_n = 1;
        #20;

        $display("=========================================================");
        $display("Starting Dual-Clock Loopback Simulation");
        $display("PHY domain clk: 100 MHz | AXI domain clk_axi: 120 MHz");
        $display("=========================================================");

        $display("Sending PACKET 1 (VC=0, RAW10) -> Expected to pass...");
        send_packet(8'h2B, 32'hDDCCBBAA);

        // Gap of 4 clocks in the write domain
        repeat(4) @(posedge clk);
        #1;
        
        $display("Sending PACKET 2 (VC=1, RAW10) -> Expected to be ignored...");
        send_packet(8'h6B, 32'h88776655);

        // Gap of 4 clocks
        repeat(4) @(posedge clk);
        #1;

        $display("Sending PACKET 3 (VC=0, RAW10) -> Expected to pass...");
        send_packet(8'h2B, 32'h44332211);
