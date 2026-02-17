`timescale 1ns/1ps

module tb_regfile;
    reg clk;
    reg rst_n;
    reg [2:0] rs1_addr, rs2_addr, rd_addr;
    wire [7:0] rs1_data, rs2_data;
    reg [7:0] rd_data;
    reg rd_we;
    
    // Instanciar DUT
    regfile dut (
        .clk(clk),
        .rst_n(rst_n),
        .rs1_addr(rs1_addr),
        .rs1_data(rs1_data),
        .rs2_addr(rs2_addr),
        .rs2_data(rs2_data),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_we(rd_we)
    );
    
    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;
    
    initial begin
        $dumpfile("sim/regfile_waveform.vcd");
        $dumpvars(0, tb_regfile);
        
        $display("\n╔════════════════════════════════════════╗");
        $display("║   Register File Test Suite            ║");
        $display("╚════════════════════════════════════════╝\n");
        
        // Reset
        rst_n = 0;
        rd_we = 0;
        #20 rst_n = 1;
        
        // Test 1: Escribir en registros
        $display("─── Test 1: Escritura ───");
        @(posedge clk);
        rd_addr = 3'd1; rd_data = 8'hAA; rd_we = 1;
        @(posedge clk);
        rd_addr = 3'd2; rd_data = 8'hBB; rd_we = 1;
        @(posedge clk);
        rd_addr = 3'd3; rd_data = 8'hCC; rd_we = 1;
        @(posedge clk);
        rd_we = 0;
        
        // Test 2: Leer registros
        $display("─── Test 2: Lectura ───");
        rs1_addr = 3'd1; rs2_addr = 3'd2;
        #1;
        $display("r1 = 0x%02h (esperado: 0xAA)", rs1_data);
        $display("r2 = 0x%02h (esperado: 0xBB)", rs2_data);
        
        // Test 3: r0 siempre es 0
        $display("\n─── Test 3: r0 inmutable ───");
        @(posedge clk);
        rd_addr = 3'd0; rd_data = 8'hFF; rd_we = 1;
        @(posedge clk);
        rd_we = 0;
        rs1_addr = 3'd0;
        #1;
        if (rs1_data == 8'h00)
            $display(" PASS: r0 permanece en 0");
        else
            $display(" ERROR: r0 = 0x%02h (debería ser 0x00)", rs1_data);
        
        #50;
        $display("\n Tests completos\n");
        $finish;
    end

endmodule