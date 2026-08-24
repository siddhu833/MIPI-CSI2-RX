// Synchronous FIFO with simultaneous read/write capability
// Depth: 32 bytes, Width: 8 bits

module sync_fifo #(
    parameter DEPTH = 32,
    parameter WIDTH = 8,
    parameter ADDR_WIDTH = 5  // log2(32) = 5
)(
    input  wire             clk,
    input  wire             rst_n,
    
    // Write interface
    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    output wire             full,
    
    // Read interface
    input  wire             rd_en,
    output wire [WIDTH-1:0] rd_data,
    output wire             empty,
    
    // Control
    input  wire             flush
);

    // Memory array
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    
    // Pointers
    reg [ADDR_WIDTH:0] wr_ptr;  // Extra bit for full/empty detection
    reg [ADDR_WIDTH:0] rd_ptr;  // Extra bit for full/empty detection
    
    // Status flags
    assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && 
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign empty = (wr_ptr == rd_ptr);
    
    // Write logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (flush) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end
    
    // Read logic (Pointer only)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else if (flush) begin
            rd_ptr <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr <= rd_ptr + 1;
        end
    end
    
    // FWFT read data
    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

endmodule
