`timescale 1ns/1ps
// ============================================================================
// pixel_pack.v — CSI-2 Pixel Packer
//
// Converts raw pixel data into packed byte streams per the MIPI CSI-2 spec.
// Supports RAW8, RAW10, RAW12, RAW24.
//
// How it works:
//   - Input: N pixels (width depends on format) presented as a flat bus
//   - Output: M packed bytes output one per clock cycle with out_valid
//   - The packing_done pulse fires when the last byte of a pixel group is sent
//
// Packing rules (CSI-2 spec):
//   RAW8  : 1 pixel  → 1 byte   (no packing)
//   RAW10 : 4 pixels → 5 bytes  (each pixel[9:2] + 4×[1:0] in last byte)
//   RAW12 : 2 pixels → 3 bytes  (each pixel[11:4] + 2×[3:0] in last byte)
//   RAW24 : 1 pixel  → 3 bytes  (pixel[23:16], [15:8], [7:0])
//
// Usage:
//   Set format, load pixels into px0..px3, pulse start.
//   Read packed bytes from out_byte while out_valid is high.
// ============================================================================

module pixel_pack (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,       // Pulse to begin packing one pixel group

    // Format select
    input  wire [1:0]  format,      // 00=RAW8, 01=RAW10, 10=RAW12, 11=RAW24

    // Pixel inputs (max 24-bit for RAW24; lower bits used for smaller formats)
    input  wire [23:0] px0,         // Always used
    input  wire [23:0] px1,         // Used for RAW10, RAW12, RAW24 (as px1 unused)
    input  wire [23:0] px2,         // Used for RAW10 only
    input  wire [23:0] px3,         // Used for RAW10 only

    // Packed byte output
    output reg  [7:0]  out_byte,    // One packed byte per cycle
    output reg         out_valid,   // High when out_byte is valid
    output reg         packing_done,// 1-cycle pulse when last byte of group sent

    // CSI-2 Data Type — combinational, driven by format select
    // TX header FSM reads this to fill the DI byte in the packet header
    output wire [7:0]  data_type    // 0x2A=RAW8, 0x2B=RAW10, 0x2C=RAW12, 0x24=RAW24
);

// Data Type lookup (MIPI CSI-2 spec Table 10)
assign data_type = (format == 2'd0) ? 8'h2A :  // RAW8
                   (format == 2'd1) ? 8'h2B :  // RAW10
                   (format == 2'd2) ? 8'h2C :  // RAW12
                                      8'h24;   // RAW24

// Format encoding
localparam FMT_RAW8  = 2'd0;
localparam FMT_RAW10 = 2'd1;
localparam FMT_RAW12 = 2'd2;
localparam FMT_RAW24 = 2'd3;

// FSM
localparam IDLE = 3'd0;
localparam BYTE0 = 3'd1;
localparam BYTE1 = 3'd2;
localparam BYTE2 = 3'd3;
localparam BYTE3 = 3'd4;
localparam BYTE4 = 3'd5; // Only for RAW10
//localparam BYTE5 = 3'd6;
reg [2:0] state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= IDLE;
        out_byte     <= 0;
        out_valid    <= 0;
        packing_done <= 0;
    end else begin
        out_valid    <= 0;
        packing_done <= 0;

        case (state)
            // ── Wait for start pulse ─────────────────────────────────────────
            IDLE: begin
                if (start)
                    state <= BYTE0;
            end

            // ── Byte 0: always present ───────────────────────────────────────
            BYTE0: begin
                out_valid <= 1;
                case (format)
                    FMT_RAW8:  begin out_byte <= px0[7:0];   state <= IDLE; packing_done <= 1; end
                    FMT_RAW10: begin out_byte <= px0[9:2];   state <= BYTE1; end
                    FMT_RAW12: begin out_byte <= px0[11:4];  state <= BYTE1; end
                    FMT_RAW24: begin out_byte <= px0[23:16]; state <= BYTE1; end
                endcase
            end

            //  Byte 1 
            BYTE1: begin
                out_valid <= 1;
                case (format)
                    FMT_RAW10: begin out_byte <= px1[9:2];   state <= BYTE2; end
                    FMT_RAW12: begin out_byte <= px1[11:4];  state <= BYTE2; end
                    FMT_RAW24: begin out_byte <= px0[15:8];  state <= BYTE2; end
                    default:   state <= IDLE;
                endcase
            end

            //  Byte 2 
            BYTE2: begin
                out_valid <= 1;
                case (format)
                    FMT_RAW10: begin out_byte <= px2[9:2];   state <= BYTE3; end
                    FMT_RAW12: begin
                        // Last byte: {px1[3:0], px0[3:0]}
                        out_byte <= {px1[3:0], px0[3:0]};
                        packing_done <= 1;
                        state <= IDLE;
                    end
                    FMT_RAW24: begin
                        out_byte <= px0[7:0];
                        packing_done <= 1;
                        state <= IDLE;
                    end
                    default: state <= IDLE;
                endcase
            end

            // ── Byte 3 (RAW10 only) ──────────────────────────────────────────
            BYTE3: begin
                out_valid <= 1;
                out_byte  <= px3[9:2];
                state     <= BYTE4;
            end

            // ── Byte 4: RAW10 final byte carrying all 4 LSB pairs ────────────
            BYTE4: begin
                out_valid    <= 1;
                out_byte     <= {px3[1:0], px2[1:0], px1[1:0], px0[1:0]};
                packing_done <= 1;
                state        <= IDLE;
            end
        endcase
    end
end

endmodule
