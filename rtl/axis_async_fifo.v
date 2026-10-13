`timescale 1ns / 1ps
// ============================================================================
// axis_async_fifo.v - AXI4-Stream wrapper around asyncc_fifo (clock crossing)
//
//  Write side : raw write-enable interface (cut-through receiver cannot be
//               stalled) - a write while full is dropped and flagged on
//               s_overflow
//  Read side  : AXI4-Stream master with head + skid registers, so
//               TVALID/TDATA stay stable while TREADY is low; reads are
//               issued on slot occupancy (as in axis_asyncc_fifo) so the
//               output sustains one word per clock under back-pressure
//  CDC        : done inside asyncc_fifo (Gray pointers + sync_2ff)
// ============================================================================

module axis_async_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 64
)(
    // write domain
    input  wire             s_clk,
    input  wire             s_rst_n,
    input  wire [WIDTH-1:0] s_data,
    input  wire             s_valid,
    output wire             s_full,
    output wire             s_overflow,      // 1-cycle pulse: write dropped

    // read domain (AXI4-Stream master)
    input  wire             m_clk,
    input  wire             m_rst_n,
    output wire [WIDTH-1:0] m_axis_tdata,
    output wire             m_axis_tvalid,
    input  wire             m_axis_tready
);

    // ------------------------------------------------------------------------
    // Core async FIFO
    // ------------------------------------------------------------------------
    wire             fifo_r_en;
    wire             fifo_empty;
    wire [WIDTH-1:0] fifo_r_dout;

    asyncc_fifo #(
        .depth (DEPTH),
        .width (WIDTH)
    ) u_fifo (
        .clk_w    (s_clk),
        .clk_r    (m_clk),
        .rst_w_n  (s_rst_n),
        .rst_r_n  (m_rst_n),
        .w_en     (s_valid),
        .r_en     (fifo_r_en),
        .data_in  (s_data),
        .full     (s_full),
        .empty    (fifo_empty),
        .data_out (fifo_r_dout)
    );

    assign s_overflow = s_valid && s_full;

    // ------------------------------------------------------------------------
    // Read side: head + skid registers (data_out has 1-cycle read latency)
    // ------------------------------------------------------------------------
    reg [WIDTH-1:0] head_data;
    reg             head_valid;
    reg [WIDTH-1:0] skid_data;
    reg             skid_valid;
    reg             r_en_pipe;

    // issue a read only if, after this cycle's pop, there is still a free
    // slot (head or skid) for the word arriving next cycle -> 1 word/cycle
    wire       pop          = m_axis_tvalid && m_axis_tready;
    wire [1:0] occupied     = head_valid + skid_valid + r_en_pipe;
    wire       read_allowed = (occupied - pop) < 2'd2;
    assign fifo_r_en        = !fifo_empty && read_allowed;

    always @(posedge m_clk or negedge m_rst_n) begin
        if (!m_rst_n) begin
            head_data  <= {WIDTH{1'b0}};
            head_valid <= 1'b0;
            skid_data  <= {WIDTH{1'b0}};
            skid_valid <= 1'b0;
            r_en_pipe  <= 1'b0;
        end else begin
            r_en_pipe <= fifo_r_en;

            // downstream handshake
            if (m_axis_tvalid && m_axis_tready) begin
                if (skid_valid) begin
                    head_data  <= skid_data;
                    head_valid <= 1'b1;
                    skid_valid <= 1'b0;
                end else begin
                    head_valid <= 1'b0;
                end
            end

            // data arriving from the FIFO
            if (r_en_pipe) begin
                if (!head_valid || (m_axis_tvalid && m_axis_tready && !skid_valid)) begin
                    head_data  <= fifo_r_dout;
                    head_valid <= 1'b1;
                end else begin
                    skid_data  <= fifo_r_dout;
                    skid_valid <= 1'b1;
                end
            end
        end
    end

    assign m_axis_tvalid = head_valid;
    assign m_axis_tdata  = head_data;

endmodule
