`timescale 1ns/1ps
// ============================================================================
// csi2_tx.v — CSI-2 TX Packet Generator (8x8 RAW8 image loopback source)
//
// Generates a complete CSI-2 frame:
//   Frame Start Short Packet
//   8x Line Long Packets (DI=0x2A RAW8, 8 bytes payload each)
//   Frame End Short Packet
//
// Outputs: phy_byte / phy_valid — directly wired to csi2_rx_llp_sf inputs
//
// FSM States:
//   IDLE → FRAME_START → LINE_HEADER → LINE_PAYLOAD → LINE_CRC → FRAME_END → DONE
// ============================================================================

module csi2_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,        // Pulse high to begin transmission

    output reg  [7:0] phy_byte,     // Byte to the RX
    output reg        phy_valid,    // Valid strobe

    output reg        tx_done       // Pulses 1 cycle after last byte sent
);

// ─── Parameters ──────────────────────────────────────────────────────────────
localparam IMG_ROWS   = 8;
localparam IMG_COLS   = 8;
localparam DATA_ID    = 8'h2A;  // CSI-2 RAW8 Long Packet data type
localparam VC         = 2'b00;  // Virtual Channel 0
localparam DI_BYTE    = {VC, DATA_ID[5:0]};  // DI = {VC[1:0], DT[5:0]}
localparam DI_FS      = 8'h00;  // Frame Start short packet type
localparam DI_FE      = 8'h01;  // Frame End short packet type
localparam WC_LSB     = 8'd8;   // Word Count = 8 bytes (8 pixels RAW8)
localparam WC_MSB     = 8'd0;

// ─── 8×8 Pixel ROM (simple gradient image) ──────────────────────────────────
// Row 0: 0x10..0x17, Row 1: 0x20..0x27, ... Row 7: 0x80..0x87
// You can replace these 64 values with any real pixel data
reg [7:0] pixel_rom [0:63];
integer init_i;
initial begin
    for (init_i = 0; init_i < 64; init_i = init_i + 1)
        pixel_rom[init_i] = ((init_i / 8) + 1) * 8'h10 + (init_i % 8);
end

// ─── FSM States ──────────────────────────────────────────────────────────────
localparam IDLE        = 4'd0;
localparam FRAME_START = 4'd1;
localparam LINE_HEADER = 4'd2;
localparam LINE_PAYLOAD= 4'd3;
localparam LINE_CRC    = 4'd4;
localparam FRAME_END   = 4'd5;
localparam DONE        = 4'd6;
localparam CRC_WAIT    = 4'd7; // 1-cycle gap so CRC register latches last payload byte

reg [3:0]  state;
reg [2:0]  byte_cnt;     // byte counter within current section
reg [2:0]  line_cnt;     // current line number (0..7)
reg [2:0]  pix_cnt;      // current pixel within line (0..7)

// Combinational next-byte to feed CRC core before it is registered into phy_byte
reg [7:0]  next_byte;

// ─── ECC Generator ──────────────────────────────────────────────────────────
// ECC input is always for a Long Packet header with DI=0x2A, WC=8
wire [25:0] ecc_data_in = {4'b0000, WC_MSB[5:0], WC_LSB, DI_BYTE};
wire  [5:0] ecc_out;
csi2_ecc_gen ecc_gen (
    .data_in(ecc_data_in),
    .ecc_out(ecc_out)
);

// ECC for Frame Start/End (DI, WC=0x0000)
wire [25:0] ecc_fs_in = {10'b0, 8'h00, 8'h00, DI_FS};
wire  [5:0] ecc_fs_out;
csi2_ecc_gen ecc_fs_gen (
    .data_in(ecc_fs_in),
    .ecc_out(ecc_fs_out)
);

wire [25:0] ecc_fe_in = {10'b0, 8'h00, 8'h00, DI_FE};
wire  [5:0] ecc_fe_out;
csi2_ecc_gen ecc_fe_gen (
    .data_in(ecc_fe_in),
    .ecc_out(ecc_fe_out)
);

// ─── CRC Accumulator (self-contained, no external module) ──────────────────────
// CRC-16/CCITT: polynomial 0x1021, init 0xFFFF
// Matches crc16_1021.v: bit[0] first, tap bits 12,5,0
reg  [15:0] tx_crc;
reg         crc_init;
wire        crc_en = (state == LINE_PAYLOAD); // Combinational: zero lag, captures pixel 0

// CRC update task
function [15:0] crc_update;
    input [15:0] crc_in;
    input [7:0]  data;
    integer k;
    reg feedback;
    reg [15:0] c;
    begin
        c = crc_in;
        for (k = 0; k < 8; k = k + 1) begin
            feedback = data[k] ^ c[15];
            c = {c[14:0], 1'b0};
            if (feedback) begin
                c[12] = c[12] ^ 1'b1;
                c[5]  = c[5]  ^ 1'b1;
                c[0]  = c[0]  ^ 1'b1;
            end
        end
        crc_update = c;
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_crc <= 16'hFFFF;
    end else begin
        if (crc_init)
            tx_crc <= 16'hFFFF;
        else if (crc_en)
            tx_crc <= crc_update(tx_crc, next_byte);
    end
end

// ─── Combinational next_byte mux ─────────────────────────────────────────────
// This drives the CRC core and is registered into phy_byte one cycle later
always @(*) begin
    next_byte = 8'h00;
    case (state)
        FRAME_START: case (byte_cnt)
            0: next_byte = DI_FS;
            1: next_byte = 8'h00;
            2: next_byte = 8'h00;
            3: next_byte = {2'b00, ecc_fs_out};
        endcase
        LINE_HEADER: case (byte_cnt)
            0: next_byte = DI_BYTE;
            1: next_byte = WC_LSB;
            2: next_byte = WC_MSB;
            3: next_byte = {2'b00, ecc_out};
        endcase
        LINE_PAYLOAD: next_byte = pixel_rom[{line_cnt, pix_cnt}];
        LINE_CRC: case (byte_cnt)
            0: next_byte = tx_crc[7:0];
            1: next_byte = tx_crc[15:8];
        endcase
        FRAME_END: case (byte_cnt)
            0: next_byte = DI_FE;
            1: next_byte = 8'h00;
            2: next_byte = 8'h00;
            3: next_byte = {2'b00, ecc_fe_out};
        endcase
    endcase
end

// ─── FSM ─────────────────────────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= IDLE;
        phy_byte  <= 8'h00;
        phy_valid <= 0;
        tx_done   <= 0;
        byte_cnt  <= 0;
        line_cnt  <= 0;
        pix_cnt   <= 0;
        crc_init  <= 0;
    end else begin
        tx_done  <= 0;
        crc_init <= 0;

        case (state)
            // ── Wait for start pulse
            IDLE: begin
                phy_valid <= 0;
                line_cnt  <= 0;
                if (start) begin
                    byte_cnt <= 0;
                    state    <= FRAME_START;
                end
            end

            // ── Send 4-byte Frame Start Short Packet
            FRAME_START: begin
                phy_valid <= 1;
                phy_byte  <= next_byte;  // Driven by combinational mux
                if (byte_cnt == 3) begin
                    byte_cnt <= 0;
                    crc_init <= 1;
                    state    <= LINE_HEADER;
                end else
                    byte_cnt <= byte_cnt + 1;
            end

            // ── Send 4-byte Long Packet Header
            LINE_HEADER: begin
                phy_valid <= 1;
                phy_byte  <= next_byte;
                if (byte_cnt == 3) begin
                    byte_cnt <= 0;
                    pix_cnt  <= 0;
                    state    <= LINE_PAYLOAD;
                end else
                    byte_cnt <= byte_cnt + 1;
            end

            // ── Send 8 payload bytes for the current line
            LINE_PAYLOAD: begin
                phy_valid <= 1;
                phy_byte  <= next_byte;
                // crc_en is a wire driven by state — no need to assert here

                if (pix_cnt == IMG_COLS - 1) begin
                    pix_cnt  <= 0;
                    state    <= CRC_WAIT; // Wait 1 cycle for last byte to enter CRC register
                end else
                    pix_cnt  <= pix_cnt + 1;
            end

            // ── 1-cycle gap for CRC to latch the last payload byte
            CRC_WAIT: begin
                phy_valid <= 0;         // Go idle for 1 cycle
                phy_byte  <= 8'h00;
                state     <= LINE_CRC; // Now crc_out is stable
            end

            // ── Send 2-byte CRC footer (LSB first)
            LINE_CRC: begin
                phy_valid <= 1;
                phy_byte  <= next_byte;
                if (byte_cnt == 1) begin
                    byte_cnt <= 0;
                    if (line_cnt == IMG_ROWS - 1) begin
                        state <= FRAME_END;
                    end else begin
                        line_cnt <= line_cnt + 1;
                        crc_init <= 1;
                        state    <= LINE_HEADER;
                    end
                end else
                    byte_cnt <= 1;
            end

            // ── Send 4-byte Frame End Short Packet
            FRAME_END: begin
                phy_valid <= 1;
                phy_byte  <= next_byte;
                if (byte_cnt == 3) begin
                    byte_cnt <= 0;
                    state    <= DONE;
                end else
                    byte_cnt <= byte_cnt + 1;
            end

            // ── Transmission complete
            DONE: begin
                phy_valid <= 0;
                phy_byte  <= 8'h00;
                tx_done   <= 1;
                state     <= IDLE;
            end

        endcase
    end
end

endmodule
