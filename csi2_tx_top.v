`timescale 1ns/1ps
// ============================================================================
// csi2_tx_top.v — CSI-2 TX with pixel_pack wired in
//
// Supports: RAW8, RAW10, RAW12, RAW24 via `format` input
// Generates: Frame Start → 8 Line Long Packets → Frame End
//
// Internal pipeline:
//   pixel_rom → pixel_pack → CRC accumulate → phy_byte stream
//
// Format-dependent behaviour (8 pixels per line):
//   RAW8  : 8 groups × 1px → 1 byte each  → WC = 8
//   RAW10 : 2 groups × 4px → 5 bytes each → WC = 10
//   RAW12 : 4 groups × 2px → 3 bytes each → WC = 12
//   RAW24 : 8 groups × 1px → 3 bytes each → WC = 24
// ============================================================================

module csi2_tx_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,       // Pulse to begin transmitting one frame
    input  wire [1:0] format,      // 00=RAW8 01=RAW10 10=RAW12 11=RAW24

    output reg  [7:0] phy_byte,
    output reg        phy_valid,
    output reg        tx_done
);

// ─── Constants ───────────────────────────────────────────────────────────────
localparam IMG_ROWS = 1080;
localparam IMG_COLS = 1920;  // pixels per line
localparam DI_FS    = 8'h00;
localparam DI_FE    = 8'h01;

// ─── Format-derived combinational signals ────────────────────────────────────
// pixels_per_group: how many pixels pixel_pack consumes per start pulse
wire [2:0] pix_per_grp = (format == 2'd1) ? 3'd4 :   // RAW10: 4px/group
                          (format == 2'd2) ? 3'd2 :   // RAW12: 2px/group
                                             3'd1;    // RAW8/RAW24: 1px/group

// groups_per_line: how many times we pulse pixel_pack per line
wire [11:0] grps_per_line = (format == 2'd1) ? 12'd480 :  // RAW10: 1920/4 = 480
                            (format == 2'd2) ? 12'd960 :  // RAW12: 1920/2 = 960
                                               12'd1920;  // RAW8/RAW24: 1920

// word_count: payload bytes per line (for the packet header)
wire [15:0] wc = (format == 2'd1) ? 16'd2400 : // RAW10: 1920×10/8 = 2400
                  (format == 2'd2) ? 16'd2880 : // RAW12: 1920×12/8 = 2880
                  (format == 2'd3) ? 16'd5760 : // RAW24: 1920×3   = 5760
                                     16'd1920;  // RAW8:  1920×1   = 1920

// ─── Pixel ROM (24-bit per entry, format uses lower N bits) ──────────────────
// Row r, Col c: value = (r+1)*0x10 + c  (simple gradient, works for all formats)
reg [23:0] pixel_rom [0:2073599];
initial begin
    // Use absolute path so Vivado simulator can find it from the xsim folder
    $readmemh("C:/Users/91778/Desktop/6thproject/csi2_rx/mem_data/image_raw10.mem", pixel_rom);
end

// ─── pixel_pack instance ─────────────────────────────────────────────────────
reg         pack_start;
wire [7:0]  pack_out;
wire        pack_valid;
wire        pack_done;
wire [7:0]  data_type;   // DI byte — auto-driven from format

// Pixel group inputs — set combinationally based on group_cnt
reg [11:0]  group_cnt;   // which pixel group within the current line (0-based, max 1920)
reg [10:0]  line_cnt;    // up to 1080
wire [21:0] rom_base = {line_cnt, 11'd0};  // This won't work perfectly since 1920 isn't a power of 2.
// Let's explicitly calculate the multiplier for 1920 instead of relying on weird bit shifting!
wire [21:0] rom_offset = ({11'd0, line_cnt} * 22'd1920) + ({10'd0, group_cnt} * {19'd0, pix_per_grp});

wire [23:0] pxA = pixel_rom[rom_offset];
wire [23:0] pxB = pixel_rom[rom_offset + 1];
wire [23:0] pxC = pixel_rom[rom_offset + 2];
wire [23:0] pxD = pixel_rom[rom_offset + 3];

pixel_pack packer (
    .clk         (clk),
    .rst_n       (rst_n),
    .start       (pack_start),
    .format      (format),
    .px0         (pxA),
    .px1         (pxB),
    .px2         (pxC),
    .px3         (pxD),
    .out_byte    (pack_out),
    .out_valid   (pack_valid),
    .packing_done(pack_done),
    .data_type   (data_type)
);

// ECC data_in format: {2'b0, WC_MSB[5:0], WC_LSB[7:0], DI[7:0]} = 26 bits
wire [5:0] ecc_fs_out, ecc_fe_out, ecc_line_out;
// TX ECC layout MUST match RX: assign ecc_data_in = {hdr_b2[5:0], hdr_b1, hdr_b0}
// = {WC_MSB[5:0], WC_LSB[7:0], DI[7:0]} padded to 26 bits = {4'b0, WC_MSB[5:0], WC_LSB, DI}
csi2_ecc_gen ecc_fs (.data_in({4'b0, 6'h00, 8'h00, DI_FS}), .ecc_out(ecc_fs_out));
csi2_ecc_gen ecc_fe (.data_in({4'b0, 6'h00, 8'h00, DI_FE}), .ecc_out(ecc_fe_out));
csi2_ecc_gen ecc_ln (.data_in({4'b0, wc[13:8], wc[7:0], data_type}), .ecc_out(ecc_line_out));

// ─── Self-contained CRC-16/CCITT ──────────────────────────────────────────────
reg  [15:0] tx_crc;
reg         crc_init;
// crc_en is high whenever pixel_pack is emitting a valid byte (payload phase)
wire        crc_en = pack_valid;

function [15:0] crc_update;
    input [15:0] crc_in;
    input [7:0]  data;
    integer k; reg fb; reg [15:0] c;
    begin
        c = crc_in;
        for (k = 0; k < 8; k = k + 1) begin
            fb = data[k] ^ c[15];
            c  = {c[14:0], 1'b0};
            if (fb) begin c[12]=c[12]^1; c[5]=c[5]^1; c[0]=c[0]^1; end
        end
        crc_update = c;
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)    tx_crc <= 16'hFFFF;
    else if (crc_init) tx_crc <= 16'hFFFF;
    else if (crc_en)   tx_crc <= crc_update(tx_crc, pack_out);
end

// ─── FSM States ──────────────────────────────────────────────────────────────
localparam IDLE        = 4'd0;
localparam FRAME_START = 4'd1;
localparam LINE_HEADER = 4'd2;
localparam PACK_START  = 4'd3;  // Pulse pixel_pack.start, present pixel group
localparam PACK_COLL   = 4'd4;  // Collect bytes from pixel_pack
localparam CRC_WAIT    = 4'd5;  // 1-cycle gap for CRC to latch last byte
localparam LINE_CRC    = 4'd6;
localparam IPG_WAIT    = 4'd7;  // Inter-packet gap
localparam FRAME_END   = 4'd8;
localparam DONE        = 4'd9;

reg [3:0]  state;
reg [2:0]  byte_cnt;
reg [15:0]  ipg_cnt;     // counter for inter-packet gap

// ─── FSM ─────────────────────────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= IDLE;
        phy_byte   <= 0;
        phy_valid  <= 0;
        tx_done    <= 0;
        byte_cnt   <= 0;
        line_cnt   <= 0;
        group_cnt  <= 0;
        ipg_cnt    <= 0;
        pack_start <= 0;
        crc_init   <= 0;
    end else begin
        tx_done    <= 0;
        pack_start <= 0;
        crc_init   <= 0;

        case (state)

            // ── Wait ────────────────────────────────────────────────────────
            IDLE: begin
                phy_valid <= 0;
                line_cnt  <= 0;
                if (start) begin byte_cnt <= 0; state <= FRAME_START; end
            end

            // ── Frame Start short packet (4 bytes) ──────────────────────────
            FRAME_START: begin
                phy_valid <= 1;
                case (byte_cnt)
                    0: phy_byte <= DI_FS;
                    1: phy_byte <= 8'h00;
                    2: phy_byte <= 8'h00;
                    3: phy_byte <= {2'b00, ecc_fs_out};
                endcase
                if (byte_cnt == 3) begin
                    byte_cnt <= 0;
                    ipg_cnt  <= 6000; // 6000-cycle gap before first line (allows RX to init)
                    state    <= IPG_WAIT;
                end else byte_cnt <= byte_cnt + 1;
            end

            // ── Long Packet header (4 bytes): DI WC_L WC_M ECC ─────────────
            LINE_HEADER: begin
                phy_valid <= 1;
                case (byte_cnt)
                    0: phy_byte <= data_type;           // From pixel_pack (combinational)
                    1: phy_byte <= wc[7:0];             // WC LSB
                    2: phy_byte <= wc[15:8];            // WC MSB
                    3: phy_byte <= {2'b00, ecc_line_out}; // ECC
                endcase
                if (byte_cnt == 3) begin
                    byte_cnt  <= 0;
                    group_cnt <= 0;
                    state     <= PACK_START;
                end else byte_cnt <= byte_cnt + 1;
            end

            // ── Start one pixel group ────────────────────────────────────────
            // pixel_pack.px0..px3 already set combinationally from group_cnt + ROM
            PACK_START: begin
                phy_valid  <= 0;     // Bus quiet while packer prepares
                pack_start <= 1;     // Pulse start into pixel_pack
                state      <= PACK_COLL;
            end

            // ── Collect bytes from pixel_pack ────────────────────────────────
            PACK_COLL: begin
                if (pack_valid) begin
                    phy_valid <= 1;
                    phy_byte  <= pack_out;  // Direct wire from packer output
                end else begin
                    phy_valid <= 0;
                end

                if (pack_done) begin
                    // This group is done
                    if (group_cnt == grps_per_line - 1) begin
                        // All groups done — go to CRC
                        state <= CRC_WAIT;
                    end else begin
                        group_cnt <= group_cnt + 1;
                        state     <= PACK_START;
                    end
                end
            end

            // ── 1 idle cycle so tx_crc latches last packed byte ─────────────
            CRC_WAIT: begin
                phy_valid <= 0;
                state     <= LINE_CRC;
            end

            // ── Send 2-byte CRC footer (LSB first) ──────────────────────────
            LINE_CRC: begin
                phy_valid <= 1;
                case (byte_cnt)
                    0: begin phy_byte <= tx_crc[7:0];  byte_cnt <= 1; end
                    1: begin
                        phy_byte <= tx_crc[15:8];
                        byte_cnt  <= 0;
                        ipg_cnt   <= 6000; // 6000-cycle gap after each line to allow Store-and-Forward to drain
                        line_cnt  <= line_cnt + 1;
                        group_cnt <= 0;
                        state     <= IPG_WAIT;
                    end
                endcase
            end

            // ── Inter-Packet Gap ────────────────────────────────────────────
            IPG_WAIT: begin
                phy_valid <= 0;
                phy_byte  <= 0;
                if (ipg_cnt == 0) begin
                    if (line_cnt == IMG_ROWS) begin
                        state <= FRAME_END;
                    end else begin
                        crc_init <= 1; // Reset CRC for this line
                        state    <= LINE_HEADER;
                    end
                end else begin
                    ipg_cnt <= ipg_cnt - 1;
                end
            end

            // ── Frame End short packet (4 bytes) ────────────────────────────
            FRAME_END: begin
                phy_valid <= 1;
                case (byte_cnt)
                    0: phy_byte <= DI_FE;
                    1: phy_byte <= 8'h00;
                    2: phy_byte <= 8'h00;
                    3: phy_byte <= {2'b00, ecc_fe_out};
                endcase
                if (byte_cnt == 3) begin byte_cnt <= 0; state <= DONE; end
                else byte_cnt <= byte_cnt + 1;
            end

            // ── Done ─────────────────────────────────────────────────────────
            DONE: begin
                phy_valid <= 0;
                phy_byte  <= 0;
                tx_done   <= 1;
                state     <= IDLE;
            end

        endcase
    end
end

endmodule
