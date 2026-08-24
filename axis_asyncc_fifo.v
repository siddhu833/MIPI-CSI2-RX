`timescale 1ns/1ps

module axis_asyncc_fifo #(
    parameter depth = 4096,
    parameter width = 8
)(
    // Write Domain (AXI-Stream Slave)
    input  wire                   s_axis_aclk,
    input  wire                   s_axis_aresetn,
    input  wire [width-1:0]       s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,

    // Read Domain (AXI-Stream Master)
    input  wire                   m_axis_aclk,
    input  wire                   m_axis_aresetn,
    output wire [width-1:0]       m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast
);

    // FIFO Data: Bit [width] stores tlast, Bits [width-1:0] store tdata
    wire [width:0] fifo_din = {s_axis_tlast, s_axis_tdata};
    wire [width:0] fifo_dout;
    wire fifo_empty;
    wire fifo_full;

    // FIFO Write Control: Write when handshake occurs
    wire fifo_wr = s_axis_tvalid && s_axis_tready;
    assign s_axis_tready = !fifo_full;

    // Instantiate your Asynchronous FIFO
    asyncc_fifo #(
        .depth(depth),
        .width(width + 1)
    ) fifo_core (
        .clk_w(s_axis_aclk),
        .clk_r(m_axis_aclk),
        .rst_w(!s_axis_aresetn),
        .rst_r(!m_axis_aresetn),
        .w_en(fifo_wr),
        .r_en(fifo_rd),
        .data_in(fifo_din),
        .full(fifo_full),
        .empty(fifo_empty),
        .data_out(fifo_dout)
    );

    // Skid Buffer Registers
    reg [width:0] data_reg;
    reg           data_valid;
    reg [width:0] temp_reg;
    reg           temp_valid;
    reg           fifo_rd_d;

    // We can read from the FIFO if it is not empty AND we have room for the data.
    // Room exists if the sum of occupied slots (registers + in-flight read) is less than 2,
    // taking into account if a slot is being freed on this cycle by m_axis_tready.
    wire [1:0] occupied_slots = data_valid + temp_valid + fifo_rd_d;
    wire fifo_rd = !fifo_empty && (occupied_slots < 2 || (occupied_slots == 2 && m_axis_tready));

    always @(posedge m_axis_aclk or negedge m_axis_aresetn) begin
        if (!m_axis_aresetn) begin
            data_reg   <= 0;
            data_valid <= 0;
            temp_reg   <= 0;
            temp_valid <= 0;
            fifo_rd_d  <= 0;
        end else begin
            fifo_rd_d <= fifo_rd;

            // Load data from FIFO output (which was requested on the previous cycle)
            if (fifo_rd_d) begin
                if (!data_valid || (data_valid && m_axis_tready)) begin
                    // data_reg is free (either empty or being cleared now)
                    if (temp_valid) begin
                        data_reg   <= temp_reg;
                        temp_reg   <= fifo_dout;
                        temp_valid <= 1;
                    end else begin
                        data_reg   <= fifo_dout;
                        data_valid <= 1;
                    end
                end else begin
                    // data_reg is full and stalled, save to backup
                    temp_reg   <= fifo_dout;
                    temp_valid <= 1;
                end
            end
            // No new data from FIFO, but backup needs to be shifted to main
            else if (temp_valid && m_axis_tready) begin
                data_reg   <= temp_reg;
                data_valid <= 1;
                temp_valid <= 0;
            end
            // No new data, and downstream accepts the current data
            else if (m_axis_tready) begin
                data_valid <= 0;
            end
        end
    end

    // Map Skid Buffer to AXI-Stream Master Interface
    assign m_axis_tvalid = data_valid;
    assign m_axis_tdata  = data_reg[width-1:0];
    assign m_axis_tlast  = data_reg[width];

endmodule
