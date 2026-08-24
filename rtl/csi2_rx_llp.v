`timescale 1ns/1ps

// CSI-2 RX module WITH ECC - using the proven idle_wait fix
module csi2_rx_llp (
    input  wire        clk,
    input  wire        rst_n,

    // PHY byte stream
    input  wire [7:0]  phy_byte,
    input  wire        phy_valid,

    // AXI-Stream output
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast,

    // Status
    output reg         ecc_ok,
    output reg         ecc_corrected,
    output reg         ecc_error,
    output reg  [7:0]  data_id,
    output reg         packet_done
);

    // ---------------- STATES ----------------
    localparam IDLE        = 3'd0;
    localparam HEADER      = 3'd1;
    localparam WAIT_ECC    = 3'd2;
    localparam PAYLOAD     = 3'd3;

    reg [2:0] state;

    // ---------------- COUNTERS ----------------
    reg [2:0]  hdr_cnt;
    reg [15:0] byte_cnt;
    reg [15:0] word_count;

    // ---------------- HEADER BYTES ----------------
    reg [7:0] hdr_b0, hdr_b1, hdr_b2, hdr_b3;
    
    // ✅ Flag to wait one cycle in IDLE before capturing next packet
    reg idle_wait;

    // ---------------- ECC ----------------
    wire [25:0] ecc_data_in;
    wire [25:0] ecc_data_corr;
    wire [5:0]  ecc_rx;
    wire        ecc_ok_wire, ecc_corrected_wire, ecc_error_wire;

    assign ecc_data_in = {hdr_b2[5:0], hdr_b1, hdr_b0};
    assign ecc_rx      = hdr_b3[5:0];

    csi2_ecc_rx ecc_checker (
        .data_in       (ecc_data_in),
        .ecc_rx        (ecc_rx),
        .data_corr     (ecc_data_corr),
        .ecc_ok        (ecc_ok_wire),
        .ecc_corrected (ecc_corrected_wire),
        .ecc_error     (ecc_error_wire)
    );

    // ECC-corrected fields
    wire [7:0] corr_data_id = ecc_data_corr[7:0];
    wire [7:0] corr_wc_lsb  = ecc_data_corr[15:8];
    wire [5:0] corr_wc_msb  = ecc_data_corr[21:16];

    // ---------------- FSM ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            hdr_cnt        <= 0;
            byte_cnt       <= 0;
            word_count     <= 0;
            data_id        <= 0;
            packet_done    <= 0;
            m_axis_tdata   <= 0;
            m_axis_tvalid  <= 0;
            m_axis_tlast   <= 0;
            hdr_b0 <= 0; hdr_b1 <= 0; hdr_b2 <= 0; hdr_b3 <= 0;
            idle_wait <= 0;
            ecc_ok        <= 0;
            ecc_corrected <= 0;
            ecc_error     <= 0;
        end else begin
            // defaults
            m_axis_tvalid  <= 0;
            m_axis_tlast   <= 0;
            packet_done    <= 0;
            ecc_ok        <= 0;
            ecc_corrected <= 0;
            ecc_error     <= 0;

            case (state)

            // ---------------- IDLE ----------------
            IDLE: begin
                hdr_cnt    <= 0;
                byte_cnt   <= 0;
                word_count <= 0;

                // ✅ Wait one cycle before capturing next packet
                if (idle_wait) begin
                    idle_wait <= 0;  // Clear wait flag
                end else if (phy_valid) begin
                    hdr_b0  <= phy_byte;  // Data ID
                    hdr_cnt <= 1;
                    state   <= HEADER;
                end
            end

            // ---------------- HEADER ----------------
            HEADER: begin
                if (phy_valid) begin
                    case (hdr_cnt)
                        1: begin 
                            hdr_b1 <= phy_byte;  // Word Count LSB
                            hdr_cnt <= 2; 
                        end
                        2: begin 
                            hdr_b2 <= phy_byte;  // Word Count MSB
                            hdr_cnt <= 3; 
                        end
                        3: begin
                            hdr_b3 <= phy_byte;  // ECC byte
                            hdr_cnt <= 0;
                            state <= WAIT_ECC;
                        end
                    endcase
                end
            end

            // ---------------- WAIT_ECC ----------------
            WAIT_ECC: begin
                ecc_ok        <= ecc_ok_wire;
                ecc_corrected <= ecc_corrected_wire;
                ecc_error     <= ecc_error_wire;

                if (ecc_error_wire) begin
                    state <= IDLE;
                end else begin
                    data_id    <= corr_data_id;
                    word_count <= {corr_wc_msb, corr_wc_lsb};

                    if ({corr_wc_msb, corr_wc_lsb} == 0) begin
                        packet_done <= 1'b1;
                        state <= IDLE;
                    end else begin
                        // ✅ CRITICAL FIX: Output FIRST byte HERE before state transition!
                        // At this moment, phy_byte IS the first payload byte
                        if (phy_valid && m_axis_tready) begin
                            m_axis_tdata  <= phy_byte;
                            m_axis_tvalid <= 1'b1;
                            byte_cnt      <= 1;  // We've output 1 byte
                            
                            if ({corr_wc_msb, corr_wc_lsb} == 1) begin
                                // Only 1 byte in packet
                                m_axis_tlast <= 1'b1;
                                packet_done  <= 1'b1;
                                idle_wait    <= 1'b1;
                                state <= IDLE;
                            end else begin
                                state <= PAYLOAD;
                            end
                        end else begin
                            // No phy_valid or not ready, go to PAYLOAD anyway
                            byte_cnt <= 0;
                            state <= PAYLOAD;
                        end
                    end
                end
            end

            // ---------------- PAYLOAD ----------------
            PAYLOAD: begin
                // Output bytes directly from phy_byte
                if (phy_valid && m_axis_tready && byte_cnt < word_count) begin
                    m_axis_tdata  <= phy_byte;
                    m_axis_tvalid <= 1'b1;
                    byte_cnt      <= byte_cnt + 1;
                    
                    if (byte_cnt == word_count - 1) begin
                        m_axis_tlast <= 1'b1;
                        packet_done  <= 1'b1;
                        idle_wait    <= 1'b1;  // ✅ Set wait flag
                    end
                end

                // State transition independent of phy_valid
                if (byte_cnt >= word_count) begin
                    state <= IDLE;
                end
            end

            endcase
        end
    end

endmodule
