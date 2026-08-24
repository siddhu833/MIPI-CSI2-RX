`timescale 1ns/1ps

module csi2_rx_llp_sf #(
    parameter [1:0] TARGET_VC = 2'b00
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  phy_byte,
    input  wire        phy_valid,

    output wire [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,

    output reg         ecc_ok,
    output reg         ecc_corrected,
    output reg         ecc_error,
    output reg         crc_error,

    output reg  [7:0]  data_id,
    output reg         packet_done
);

// FSM states
localparam IDLE        = 3'd0;
localparam HEADER      = 3'd1;
localparam PAYLOAD     = 3'd2;
localparam CRC_LSB     = 3'd3;
localparam CRC_MSB     = 3'd4;
localparam AXI_STREAM  = 3'd5;
localparam FLUSH_FIFO  = 3'd6;

reg [2:0]  state;
reg [2:0]  hdr_cnt;
reg [15:0] payload_cnt;
reg [15:0] word_count;
reg        vc_match;

reg [7:0]  hdr_b0, hdr_b1, hdr_b2;
wire [7:0] hdr_b3 = phy_byte; 

wire [25:0] ecc_data_in;
wire [25:0] ecc_data_corr;
wire [5:0]  ecc_rx;

wire ecc_ok_wire;
wire ecc_corrected_wire;
wire ecc_error_wire;

// Feed ECC combinationally
assign ecc_data_in = {hdr_b2[5:0], hdr_b1, hdr_b0};
assign ecc_rx      = hdr_b3[5:0];

csi2_ecc_rx ecc_checker(
    .data_in(ecc_data_in),
    .ecc_rx(ecc_rx),
    .data_corr(ecc_data_corr),
    .ecc_ok(ecc_ok_wire),
    .ecc_corrected(ecc_corrected_wire),
    .ecc_error(ecc_error_wire)
);

wire [7:0] corr_data_id = ecc_data_corr[7:0];
wire [7:0] corr_wc_lsb  = ecc_data_corr[15:8];
wire [5:0] corr_wc_msb  = ecc_data_corr[21:16];

// CRC
wire [15:0] crc_calc;
wire        crc_init = (state == HEADER) && (hdr_cnt == 3) && phy_valid && !ecc_error_wire && (corr_data_id >= 8'h10);
wire        crc_en = (state == PAYLOAD) && phy_valid;
reg  [7:0]  crc_lsb;

crc16_1021 crc_core(
    .clk(clk),
    .rst(~rst_n),
    .init(crc_init),
    .data_valid(crc_en),
    .data_in(phy_byte),
    .crc_out(crc_calc)
);

// Internal FIFO signals
wire fifo_full;
wire fifo_empty;
wire fifo_wr = (state == PAYLOAD) && phy_valid && vc_match;
wire fifo_rd;
reg  fifo_flush;
wire [7:0] fifo_dout;

assign fifo_rd = axi_active && m_axis_tvalid && m_axis_tready;

// Instantiate internal Synchronous FIFO for Store-and-Forward buffering
sync_fifo #(
    .DEPTH(4096),
    .ADDR_WIDTH(12)
) fifo (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(fifo_wr),
    .wr_data(phy_byte),
    .full(fifo_full),
    .rd_en(fifo_rd),
    .rd_data(fifo_dout),
    .empty(fifo_empty),
    .flush(fifo_flush)
);

// AXI Output Count
reg [15:0] axi_out_cnt;

// FSM for Store-and-Forward
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= IDLE;
        hdr_cnt       <= 0;
        payload_cnt   <= 0;
        word_count    <= 0;
        vc_match      <= 0;
        hdr_b0        <= 0;
        hdr_b1        <= 0;
        hdr_b2        <= 0;
        ecc_ok        <= 0;
        ecc_corrected <= 0;
        ecc_error     <= 0;
        crc_error     <= 0;
        data_id       <= 0;
        packet_done   <= 0;
        fifo_flush    <= 0;
    end else begin
        packet_done <= 0;
        fifo_flush  <= 0; // Default

        case(state)
            IDLE: begin
                hdr_cnt <= 0;
                payload_cnt <= 0;
                crc_error <= 0; // Clear immediately for Vivado waveform clarity
                // Only block if FIFO still has previous packet data
                // Do NOT wait for AXI stream to finish - they are independent domains
                if (phy_valid) begin
                    hdr_b0 <= phy_byte;
                    hdr_cnt <= 1;
                    state <= HEADER;
                end
            end

            HEADER: begin
                if (phy_valid) begin
                    case (hdr_cnt)
                        1: begin hdr_b1 <= phy_byte; hdr_cnt <= 2; end
                        2: begin hdr_b2 <= phy_byte; hdr_cnt <= 3; end
                        3: begin
                            // We have all 4 bytes of the header. Perform ECC.
                            ecc_ok        <= ecc_ok_wire;
                            ecc_corrected <= ecc_corrected_wire;
                            ecc_error     <= ecc_error_wire;
                            
                            data_id    <= corr_data_id;
                            word_count <= {corr_wc_msb, corr_wc_lsb};
                            vc_match   <= (corr_data_id[7:6] == TARGET_VC);

                            if (ecc_error_wire) begin
                                state <= IDLE;
                            end else if (corr_data_id < 8'h10) begin
                                if (corr_data_id[7:6] == TARGET_VC) begin
                                    packet_done <= 1; // Short Packet matching target VC is done
                                end
                                state       <= IDLE;
                            end else begin
                                state    <= PAYLOAD; // Long Packet (swallow bytes even if VC doesn't match)
                            end
                        end
                    endcase
                end
            end

            PAYLOAD: begin
                // Data is pushing to FIFO combinationally
                if (phy_valid) begin
                    payload_cnt <= payload_cnt + 1;

                    if (payload_cnt == word_count - 1) begin
                        state <= CRC_LSB;
                    end
                end
            end

            CRC_LSB: begin
                if (phy_valid) begin
                    crc_lsb <= phy_byte;
                    state <= CRC_MSB;
                end
            end

            CRC_MSB: begin
                if (phy_valid) begin
                    if (!vc_match) begin
                        state <= IDLE; // Discarded VC packet is done, return to IDLE
                    end else if ({phy_byte, crc_lsb} != crc_calc) begin
                        crc_error <= 1;
                        state <= FLUSH_FIFO; // CRC Failed! Dump the payload.
                    end else begin
                        crc_error <= 0;
                        state <= AXI_STREAM; // CRC Passed! Stream it out.
                    end
                end
            end
            
            FLUSH_FIFO: begin
                // Drop all stored payload data
                fifo_flush <= 1;
                packet_done <= 1;
                state <= IDLE;
            end
            
            AXI_STREAM: begin
                // Signal to the separate output FSM to begin streaming 'word_count' bytes
                packet_done <= 1;
                state <= IDLE; // Immediately return to IDLE to catch the next header
            end
            
        endcase
    end
end

// ------------------------------------------------------------------
// AXI Output Stream Logic (Independent Domain)
// ------------------------------------------------------------------
reg        axi_active;
reg [15:0] axi_out_word_count;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        m_axis_tvalid <= 0;
        m_axis_tlast  <= 0;
        axi_out_cnt   <= 0;
        axi_active    <= 0;
        axi_out_word_count <= 0;
    end else begin
        if (axi_active) begin
            if (m_axis_tvalid && !m_axis_tready) begin
                // Stall: hold everything
            end else begin
                // Previous byte accepted
                if (axi_out_cnt + 1 == axi_out_word_count) begin
                    // We are done
                    m_axis_tvalid <= 0;
                    m_axis_tlast  <= 0;
                    axi_active    <= 0;
                end else begin
                    // Continue streaming
                    m_axis_tvalid <= 1;
                    axi_out_cnt   <= axi_out_cnt + 1;
                    
                    if (axi_out_cnt + 2 == axi_out_word_count) begin
                        m_axis_tlast <= 1;
                    end else begin
                        m_axis_tlast <= 0;
                    end
                end
            end
        end
        else if (state == AXI_STREAM) begin
            if (!fifo_empty && word_count > 0) begin
                axi_active         <= 1;
                axi_out_cnt        <= 0;
                axi_out_word_count <= word_count;
                m_axis_tvalid      <= 1;
                
                if (word_count == 1) begin
                    m_axis_tlast   <= 1;
                end else begin
                    m_axis_tlast   <= 0;
                end
            end
        end
    end
end

assign m_axis_tdata = fifo_dout;

endmodule
