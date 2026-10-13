`timescale 1ns / 1ps
// ============================================================================
// tb_csi2_loopback.v - Verilog testbench for csi2_loopback_top
//
//  Frame 1 : image from sim_data/input.mem (Python, grayscale RAW8)
//            TX packer -> RX bridge -> AXI4-Stream with random TREADY
//            back-pressure; output written to sim_data/output.mem
//  Frame 2 : 16x4 test frame with link errors injected
//            line 0 header : 1-bit error  -> ECC corrects, line delivered
//            line 1 header : 2-bit error  -> ECC error, line dropped
//            line 2 payload: 1-bit error  -> CRC error, line tagged tuser[1]
//            line 3        : clean
//  Frame 3 : 32x8 clean frame (recovery after errors)
//
//  Every output pixel is checked for data, tuser[0] (SOF), tlast (EOL)
//  and tuser[1] (line error).
// ============================================================================

module tb_csi2_loopback;

    parameter DATA_DIR   = "C:/Users/91778/Desktop/resume_projects/CSI2_RX_AXIS_Bridge/sim_data/";
    parameter MAX_PIXELS = 1920 * 1080;

    // ------------------------------------------------------------------------
    // Clocks: byte clock 100 MHz, AXI clock ~150 MHz (unrelated)
    // ------------------------------------------------------------------------
    reg clk_byte = 1'b0;
    reg clk_axi  = 1'b0;
    reg rst_n    = 1'b0;

    always #5    clk_byte = ~clk_byte;
    always #3.33 clk_axi  = ~clk_axi;

    // ------------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------------
    reg  [13:0] cfg_width  = 14'd0;
    reg  [15:0] cfg_height = 16'd0;

    reg  [7:0]  s_tdata  = 8'd0;
    reg         s_tvalid = 1'b0;
    wire        s_tready;
    reg         s_tlast  = 1'b0;
    reg         s_tuser  = 1'b0;

    reg  [7:0]  phy_err_mask;

    wire [7:0]  m_tdata;
    wire        m_tvalid;
    reg         m_tready = 1'b1;
    wire        m_tlast;
    wire [1:0]  m_tuser;

    wire        tx_frame_done, tx_underrun, tx_tlast_err;
    wire [15:0] frame_cnt, line_cnt, ecc_corr_cnt, ecc_err_cnt, crc_err_cnt;
    wire        sts_ecc_err, sts_crc_err, sts_overflow;

    csi2_loopback_top #(
        .IPG        (8),
        .FIFO_DEPTH (64)
    ) dut (
        .clk_byte      (clk_byte),
        .clk_axi       (clk_axi),
        .rst_n         (rst_n),
        .cfg_width     (cfg_width),
        .cfg_height    (cfg_height),
        .s_axis_tdata  (s_tdata),
        .s_axis_tvalid (s_tvalid),
        .s_axis_tready (s_tready),
        .s_axis_tlast  (s_tlast),
        .s_axis_tuser  (s_tuser),
        .phy_err_mask  (phy_err_mask),
        .m_axis_tdata  (m_tdata),
        .m_axis_tvalid (m_tvalid),
        .m_axis_tready (m_tready),
        .m_axis_tlast  (m_tlast),
        .m_axis_tuser  (m_tuser),
        .tx_frame_done (tx_frame_done),
        .tx_underrun   (tx_underrun),
        .tx_tlast_err  (tx_tlast_err),
        .frame_cnt     (frame_cnt),
        .line_cnt      (line_cnt),
        .ecc_corr_cnt  (ecc_corr_cnt),
        .ecc_err_cnt   (ecc_err_cnt),
        .crc_err_cnt   (crc_err_cnt),
        .sts_ecc_err   (sts_ecc_err),
        .sts_crc_err   (sts_crc_err),
        .sts_overflow  (sts_overflow)
    );

    // ------------------------------------------------------------------------
    // Pixel source (AXI4-Stream master @ clk_byte)
    // ------------------------------------------------------------------------
    reg [7:0] src_mem [0:MAX_PIXELS-1];
    integer   src_idx    = 0;
    integer   src_total  = 0;
    integer   src_w      = 1;
    reg       src_active = 1'b0;

    always @(posedge clk_byte) begin
        if (s_tvalid && s_tready)
            src_idx = src_idx + 1;
        if (src_active && src_idx < src_total) begin
            s_tvalid <= 1'b1;
            s_tdata  <= src_mem[src_idx];
            s_tuser  <= (src_idx == 0);
            s_tlast  <= ((src_idx % src_w) == src_w - 1);
        end else begin
            s_tvalid <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Link error injection (by byte index inside the frame)
    // ------------------------------------------------------------------------
    reg     inj_en   = 1'b0;
    integer link_idx = 0;

    always @(posedge clk_byte)
        if (inj_en && dut.tx_valid)
            link_idx <= link_idx + 1;

    always @(*) begin
        phy_err_mask = 8'h00;
        if (inj_en && dut.tx_valid) begin
            case (link_idx)
                5:  phy_err_mask = 8'h04;   // line 0 header, WC LSB : 1-bit
                26: phy_err_mask = 8'h03;   // line 1 header, DI     : 2-bit
                57: phy_err_mask = 8'h80;   // line 2 payload byte 5 : 1-bit
                default: phy_err_mask = 8'h00;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Pixel sink (AXI4-Stream slave @ clk_axi) + checker
    // ------------------------------------------------------------------------
    reg [7:0] exp_mem [0:MAX_PIXELS-1];
    integer   exp_total  = 0;
    integer   exp_w      = 1;
    integer   exp_err_at = -1;      // output pixel expected to carry tuser[1]
    integer   out_idx    = 0;
    integer   pix_errors = 0;
    integer   errors     = 0;
    integer   out_fd     = 0;
    reg       bp_en      = 1'b0;
    reg       exp_sof, exp_last, exp_err;

    always @(posedge clk_axi) begin
        m_tready <= bp_en ? (($random & 7) != 0) : 1'b1;   // ~87% ready

        if (m_tvalid && m_tready) begin
            if (out_fd != 0)
                $fwrite(out_fd, "%02X\n", m_tdata);

            exp_sof  = (out_idx == 0);
            exp_last = ((out_idx % exp_w) == exp_w - 1);
            exp_err  = (out_idx == exp_err_at);

            if (out_idx >= exp_total) begin
                pix_errors = pix_errors + 1;
                if (pix_errors <= 10)
                    $display("  [ERROR] unexpected extra pixel %0d = %02X", out_idx, m_tdata);
            end else if (m_tdata !== exp_mem[out_idx] || m_tuser[0] !== exp_sof ||
                         m_tlast !== exp_last || m_tuser[1] !== exp_err) begin
                pix_errors = pix_errors + 1;
                if (pix_errors <= 10)
                    $display("  [ERROR] pixel %0d: got %02X sof=%b last=%b err=%b, expected %02X sof=%b last=%b err=%b",
                             out_idx, m_tdata, m_tuser[0], m_tlast, m_tuser[1],
                             exp_mem[out_idx], exp_sof, exp_last, exp_err);
            end
            out_idx = out_idx + 1;
        end
    end

    // ------------------------------------------------------------------------
    // AXI4-Stream protocol check: payload stable while TVALID && !TREADY
    // ------------------------------------------------------------------------
    reg        p_valid = 1'b0, p_ready = 1'b0;
    reg [10:0] p_payload;
    integer    proto_errs = 0;

    always @(posedge clk_axi) begin
        if (p_valid && !p_ready && (!m_tvalid || {m_tuser, m_tlast, m_tdata} !== p_payload)) begin
            proto_errs = proto_errs + 1;
            if (proto_errs <= 5)
                $display("  [PROTOCOL] TVALID dropped or payload changed before TREADY @ %0t", $time);
        end
        p_valid   = m_tvalid;
        p_ready   = m_tready;
        p_payload = {m_tuser, m_tlast, m_tdata};
    end

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------
    task check;
        input            cond;
        input [8*56-1:0] msg;
        begin
            if (cond) $display("    PASS: %0s", msg);
            else begin
                $display("    FAIL: %0s", msg);
                errors = errors + 1;
            end
        end
    endtask

    // send the frame in src_mem and wait until exp_total pixels are received
    task run_frame;
        input integer w;
        input integer h;
        integer timeout;
        begin
            cfg_width  = w;
            cfg_height = h;
            src_w      = w;
            src_total  = w * h;
            src_idx    = 0;
            out_idx    = 0;
            pix_errors = 0;
            exp_w      = w;

            @(posedge clk_byte);
            src_active = 1'b1;
            @(posedge tx_frame_done);
            src_active = 1'b0;

            timeout = 0;
            while (out_idx < exp_total && timeout < 10000) begin
                @(posedge clk_axi);
                timeout = timeout + 1;
            end
            repeat (50) @(posedge clk_axi);    // catch any extra pixels
        end
    endtask

    // ------------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------------
    reg [31:0] dims [0:1];
    integer    img_w, img_h, i, x, y, k;
    integer    corr0, eccerr0, crc0, frames0, lines0;

    initial begin
        $readmemh({DATA_DIR, "dims.mem"}, dims);
        img_w = dims[0];
        img_h = dims[1];
        if (img_w <= 0 || img_h <= 0 || img_w * img_h > MAX_PIXELS) begin
            $display("ERROR: bad image size %0d x %0d - run scripts/img_to_mem.py first", img_w, img_h);
            $finish;
        end

        repeat (5) @(posedge clk_byte);
        rst_n = 1'b1;
        repeat (10) @(posedge clk_byte);

        $display("=================================================================");
        $display(" CSI-2 RX to AXI4-Stream bridge - loopback testbench");
        $display("=================================================================");

        // ---------------- Frame 1: image ----------------
        $display("--- Frame 1: %0d x %0d grayscale image, AXI4-Stream back-pressure", img_w, img_h);
        $readmemh({DATA_DIR, "input.mem"}, src_mem, 0, img_w * img_h - 1);
        for (i = 0; i < img_w * img_h; i = i + 1)
            exp_mem[i] = src_mem[i];
        exp_total  = img_w * img_h;
        exp_err_at = -1;
        out_fd     = $fopen({DATA_DIR, "output.mem"}, "w");
        bp_en      = 1'b1;
        run_frame(img_w, img_h);
        $fclose(out_fd);
        out_fd = 0;
        bp_en  = 1'b0;

        $display("    pixels received %0d / %0d, pixel errors %0d", out_idx, exp_total, pix_errors);
        check(out_idx == exp_total && pix_errors == 0, "all pixels, SOF, EOL correct");
        check(line_cnt == img_h && frame_cnt == 1,     "line and frame counters");
        check(crc_err_cnt == 0 && ecc_err_cnt == 0 && ecc_corr_cnt == 0, "no ECC / CRC errors");
        check(!sts_overflow && !tx_underrun && !tx_tlast_err, "no FIFO overflow, no TX underrun");

        // ---------------- Frame 2: error injection ----------------
        $display("--- Frame 2: 16 x 4 frame with injected link errors");
        corr0 = ecc_corr_cnt; eccerr0 = ecc_err_cnt; crc0 = crc_err_cnt;
        frames0 = frame_cnt;  lines0  = line_cnt;
        for (i = 0; i < 64; i = i + 1)
            src_mem[i] = (i * 13 + 7) & 8'hFF;
        // expected output: lines 0, 2, 3 (line 1 dropped), line 2 byte 5 flipped
        k = 0;
        for (y = 0; y < 4; y = y + 1)
            if (y != 1)
                for (x = 0; x < 16; x = x + 1) begin
                    exp_mem[k] = src_mem[y * 16 + x] ^ ((y == 2 && x == 5) ? 8'h80 : 8'h00);
                    k = k + 1;
                end
        exp_total  = 48;
        exp_err_at = 31;                // last pixel of the 2nd delivered line
        link_idx   = 0;
        inj_en     = 1'b1;
        run_frame(16, 4);
        inj_en     = 1'b0;

        $display("    pixels received %0d / %0d, pixel errors %0d", out_idx, exp_total, pix_errors);
        check(out_idx == 48 && pix_errors == 0,      "bad-header line dropped, others delivered");
        check(ecc_corr_cnt == corr0 + 1,             "1-bit header error corrected by ECC");
        check(ecc_err_cnt  == eccerr0 + 1,           "2-bit header error detected by ECC");
        check(crc_err_cnt  == crc0 + 1,              "payload error detected by CRC");
        check(line_cnt == lines0 + 3 && frame_cnt == frames0 + 1, "line and frame counters");
        repeat (5) @(posedge clk_axi);
        check(sts_ecc_err && sts_crc_err && !sts_overflow, "sticky flags synced to AXI clock");

        // ---------------- Frame 3: recovery ----------------
        $display("--- Frame 3: 32 x 8 clean frame after errors");
        crc0 = crc_err_cnt; eccerr0 = ecc_err_cnt;
        for (i = 0; i < 256; i = i + 1) begin
            src_mem[i] = 255 - i;
            exp_mem[i] = 255 - i;
        end
        exp_total  = 256;
        exp_err_at = -1;
        bp_en      = 1'b1;
        run_frame(32, 8);
        bp_en      = 1'b0;
        check(out_idx == 256 && pix_errors == 0 &&
              crc_err_cnt == crc0 && ecc_err_cnt == eccerr0, "clean frame received correctly");

        check(proto_errs == 0, "AXI4-Stream TVALID/TDATA stable under back-pressure");

        $display("=================================================================");
        if (errors == 0) $display(" ALL TESTS PASSED");
        else             $display(" TESTS FAILED: %0d", errors);
        $display(" Now run: python scripts/mem_to_img.py");
        $display("=================================================================");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT - TESTS FAILED");
        $finish;
    end

endmodule
