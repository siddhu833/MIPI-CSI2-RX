`timescale 1ns / 1ps

module tb_sync_fifo();

    // Parameters
    parameter DEPTH = 4;
    parameter WIDTH = 8;
    parameter ADDR_WIDTH = 2;

    // Inputs
    reg clk;
    reg rst_n;
    reg wr_en;
    reg [WIDTH-1:0] wr_data;
    reg rd_en;
    reg flush;

    // Outputs
    wire full;
    wire [WIDTH-1:0] rd_data;
    wire empty;

    // Instantiate the Unit Under Test (UUT)
    sync_fifo #(
        .DEPTH(DEPTH),
        .WIDTH(WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk), 
        .rst_n(rst_n), 
        .wr_en(wr_en), 
        .wr_data(wr_data), 
        .full(full), 
        .rd_en(rd_en), 
        .rd_data(rd_data), 
        .empty(empty), 
        .flush(flush)
    );

    // Clock generation (100 MHz)
    always #5 clk = ~clk;

    integer i;
    reg error_flag;

    initial begin
        // Initialize Inputs
        clk = 0;
        rst_n = 0;
        wr_en = 0;
        wr_data = 0;
        rd_en = 0;
        flush = 0;
        error_flag = 0;

        $display("=================================================");
        $display("   Synchronous FIFO Testbench Started");
        $display("=================================================");

        // Wait for global reset to finish
        #20;
        rst_n = 1;
        #10;
        
        // ---------------------------------------------------------
        // TEST 1: Initial State Check
        // ---------------------------------------------------------
        $display("\n--- TEST 1: Initial State ---");
        if (empty && !full) 
            $display("[PASS] FIFO successfully starts Empty.");
        else 
            $display("[FAIL] Initial state incorrect. Empty: %b, Full: %b", empty, full);

        // ---------------------------------------------------------
        // TEST 2: Write Burst until Full
        // ---------------------------------------------------------
        $display("\n--- TEST 2: Write %0d bytes until Full ---", DEPTH);
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clk);
            wr_en = 1'b1;
            wr_data = i + 10; // Write values 10, 11, 12...
        end
        @(posedge clk);
        wr_en = 1'b0; // Stop writing
        
        #10;
        if (full && !empty) 
            $display("[PASS] FIFO correctly asserts FULL flag.");
        else 
            $display("[FAIL] FULL flag logic failed!");

        // ---------------------------------------------------------
        // TEST 3: Overwrite Protection
        // ---------------------------------------------------------
        $display("\n--- TEST 3: Overwrite Protection ---");
        @(posedge clk);
        wr_en = 1'b1;
        wr_data = 8'hFF; // Try to write 0xFF to a full FIFO
        @(posedge clk);
        wr_en = 1'b0;
        
        #10;
        $display("[INFO] Attempted write while full. Read test will verify it blocked corruption.");

        // ---------------------------------------------------------
        // TEST 4: Read Burst until Empty
        // ---------------------------------------------------------
        $display("\n--- TEST 4: Read Data Verification ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            // FWFT (First Word Fall Through) means rd_data is available BEFORE we pulse rd_en
            if (rd_data !== (i + 10)) begin
                $display("[FAIL] Data mismatch at index %0d! Expected: %0d, Got: %0d", i, i+10, rd_data);
                error_flag = 1;
            end
            @(posedge clk);
            rd_en = 1'b1;
        end
        @(posedge clk);
        rd_en = 1'b0;
        
        #10;
        if (!error_flag)
            $display("[PASS] All %0d bytes read correctly. Overwrite was successfully blocked.", DEPTH);
            
        if (empty && !full) 
            $display("[PASS] FIFO correctly asserts EMPTY flag.");
        else 
            $display("[FAIL] EMPTY flag logic failed!");

        // ---------------------------------------------------------
        // TEST 5: Flush (Wipe) Functionality
        // ---------------------------------------------------------
        $display("\n--- TEST 5: Flush (Pointer Reset) Functionality ---");
        // Write 3 random values
        for (i = 0; i < 3; i = i + 1) begin
            @(posedge clk);
            wr_en = 1'b1;
            wr_data = i * 2;
        end
        @(posedge clk);
        wr_en = 1'b0;
        
        // Assert flush to abruptly wipe the pointers
        @(posedge clk);
        flush = 1'b1;
        @(posedge clk);
        flush = 1'b0;
        
        #10;
        if (empty && !full) 
            $display("[PASS] Flush command successfully wiped the pointers.");
        else 
            $display("[FAIL] Flush command failed to empty the FIFO!");

        $display("\n=================================================");
        $display("   All FIFO tests completed.");
        $display("=================================================\n");
        $finish;
    end

endmodule
