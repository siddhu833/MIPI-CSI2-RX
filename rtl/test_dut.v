`timescale 1ns/1ps

module csi2_rx_ecc_crc (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  phy_byte,
    input  wire        phy_valid,

    output reg  [7:0]  m_axis_tdata,
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

reg [2:0]  state;
reg [2:0]  hdr_cnt;
reg [15:0] payload_cnt;
reg [15:0] word_count;

reg [7:0]  hdr_b0, hdr_b1, hdr_b2;
wire [7:0] hdr_b3 = phy_byte; // Header byte 3 is processed combinationally

wire [25:0] ecc_data_in;
wire [25:0] ecc_data_corr;
wire [5:0]  ecc_rx;

wire ecc_ok_wire;
wire ecc_corrected_wire;
wire ecc_error_wire;

// Feed ECC combinationally so we don't waste a clock cycle
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

// CRC check logic (assumes CRC matches standard CSI-2 config)
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

// FIFO inst
wire fifo_full;
wire fifo_empty;
wire fifo_wr = (state == PAYLOAD) && phy_valid;
reg  fifo_rd;
wire [7:0] fifo_dout;

sync_fifo fifo(
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(fifo_wr),
    .wr_data(phy_byte),
    .full(fifo_full),
    .rd_en(fifo_rd),
    .rd_data(fifo_dout),
    .empty(fifo_empty),
    .flush(1'b0) // No flushing, we stream the data out as it comes
);

// AXI Stream Output Logic (Independent from incoming PHY FSM)
reg [15:0] axi_out_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        m_axis_tdata  <= 0;
        m_axis_tvalid <= 0;
        m_axis_tlast  <= 0;
        fifo_rd       <= 0;
        axi_out_cnt   <= 0;
    end else begin
        fifo_rd <= 0; // Default

        // AXI Protocol: tvalid MUST stay high if tready is low
        if (m_axis_tvalid && !m_axis_tready) begin
            // Hold the data, wait for slave to be ready
            fifo_rd <= 0; 
        end 
        else if (!fifo_empty) begin
            // Send new data from FIFO
            fifo_rd <= 1;
            m_axis_tdata <= fifo_dout;
            m_axis_tvalid <= 1;
            
            axi_out_cnt <= axi_out_cnt + 1;
            // Generate tlast on the last byte of the payload
            if (axi_out_cnt == word_count - 1) begin
                m_axis_tlast <= 1;
                axi_out_cnt <= 0;
            end else begin
                m_axis_tlast <= 0;
            end
        end 
        else begin
            // No data to send
            m_axis_tvalid <= 0;
            m_axis_tlast  <= 0;
        end
    end
end

// PHY Input FSM
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= IDLE;
        hdr_cnt       <= 0;
        payload_cnt   <= 0;
        word_count    <= 0;
        data_id       <= 0;
        packet_done   <= 0;
        crc_error     <= 0;
        ecc_ok        <= 0;
        ecc_corrected <= 0;
        ecc_error     <= 0;
    end else begin
        packet_done <= 0;

        case(state)
            IDLE: begin
                hdr_cnt <= 0;
                payload_cnt <= 0;
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
                            // Calculate ECC dynamically in this exact clock cycle!
                            ecc_ok        <= ecc_ok_wire;
                            ecc_corrected <= ecc_corrected_wire;
                            ecc_error     <= ecc_error_wire;
                            
                            data_id    <= corr_data_id;
                            word_count <= {corr_wc_msb, corr_wc_lsb};

                            if (ecc_error_wire) begin
                                state <= IDLE; // Unrecoverable error
                            end else if (corr_data_id < 8'h10) begin
                                // IT IS A SHORT PACKET! (Data_ID < 0x10)
                                // Do not wait for payload.
                                packet_done <= 1;
                                state       <= IDLE;
                            end else begin
                                // Long Packet!
                                state    <= PAYLOAD;
                            end
                        end
                    endcase
                end
            end

            PAYLOAD: begin
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
                    if ({phy_byte, crc_lsb} != crc_calc) begin
                        crc_error <= 1;
                    end else begin
                        crc_error <= 0;
                    end
                    packet_done <= 1;
                    state <= IDLE;
                end
            end
        endcase
    end
end

endmodule
