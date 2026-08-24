`timescale 1ns/1ps
module pixel_pack_tb;
    reg clk = 0, rst_n = 0, start = 0;
    reg [1:0]  format;
    reg [23:0] px0, px1, px2, px3;
    wire [7:0] out_byte;
    wire       out_valid, packing_done;
    wire [7:0] data_type;  // NEW: combinational DI output
    always #5 clk = ~clk;

    pixel_pack dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .format(format), .px0(px0), .px1(px1), .px2(px2), .px3(px3),
        .out_byte(out_byte), .out_valid(out_valid), .packing_done(packing_done),
        .data_type(data_type)
    );

    always @(posedge clk)
        if (out_valid)
            $display("byte=0x%02h  done=%b", out_byte, packing_done);

    initial begin
        #12; rst_n = 1;

        // ── RAW8 test: px0 = 0xAB ──────────────────────────────────────────
        $display("\n--- RAW8: px0=0xAB, expect: AB, DI=0x2A ---");
        format = 2'd0; px0 = 24'hAB; px1 = 0; px2 = 0; px3 = 0;
        #1; $display("data_type = 0x%02h (expect 0x2A)", data_type);
        @(posedge clk); start <= 1;
        @(posedge clk); start <= 0;
        repeat(5) @(posedge clk);

        // ── RAW10 test: stress test values ─────────────────────────────────
        // P0=0x2AB P1=0x335 P2=0x0EF P3=0x112
        // Expected: AA CD 3B 44 B7
        $display("\n--- RAW10: P0=0x2AB P1=0x335 P2=0x0EF P3=0x112 ---");
        $display("Expected bytes: AA CD 3B 44 B7");
        format = 2'd1;
        px0 = 24'h2AB; px1 = 24'h335; px2 = 24'h0EF; px3 = 24'h112;
        #1; $display("data_type = 0x%02h (expect 0x2B)", data_type);
        @(posedge clk); start <= 1;
        @(posedge clk); start <= 0;
        repeat(10) @(posedge clk);

        // ── RAW12 test: px0=0xABC px1=0xDEF ───────────────────────────────
        // B0=px0[11:4]=0xAB, B1=px1[11:4]=0xDE, B2={0xF,0xC}=0xFC
        $display("\n--- RAW12: P0=0xABC P1=0xDEF ---");
        $display("Expected bytes: AB DE FC");
        format = 2'd2;
        px0 = 24'hABC; px1 = 24'hDEF; px2 = 0; px3 = 0;
        #1; $display("data_type = 0x%02h (expect 0x2C)", data_type);
        @(posedge clk); start <= 1;
        @(posedge clk); start <= 0;
        repeat(8) @(posedge clk);

        // ── RAW24 test: px0=0xCAFE12 ──────────────────────────────────────
        $display("\n--- RAW24: P0=0xCAFE12 ---");
        $display("Expected bytes: CA FE 12");
        format = 2'd3;
        px0 = 24'hCAFE12; px1 = 0; px2 = 0; px3 = 0;
        #1; $display("data_type = 0x%02h (expect 0x24)", data_type);
        @(posedge clk); start <= 1;
        @(posedge clk); start <= 0;
        repeat(8) @(posedge clk);

        $display("\n=== pixel_pack test done ===");
        $finish;
    end
endmodule
