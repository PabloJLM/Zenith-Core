`timescale 1ns/1ps

module tb_cpu_complete;
    reg clk, rst_n;
    wire [7:0] mem_addr;
    reg [15:0] mem_rdata;
    wire [7:0] mem_wdata;
    wire mem_we;
    wire [7:0] gpio_out;
    reg [7:0] gpio_in;
    wire [7:0] debug_pc, debug_state;
    
    // Memoria de programa
    reg [15:0] program_memory [0:255];
    
    // Asignar lectura de memoria
    always @(*) begin
        mem_rdata = program_memory[mem_addr];
    end
    
    // Instanciar CPU
    cpu_core cpu (
        .clk(clk),
        .rst_n(rst_n),
        .mem_addr(mem_addr),
        .mem_rdata(mem_rdata),
        .mem_wdata(mem_wdata),
        .mem_we(mem_we),
        .gpio_out(gpio_out),
        .gpio_in(gpio_in),
        .debug_pc(debug_pc),
        .debug_state(debug_state)
    );
    
    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;
    
    initial begin
        $dumpfile("sim/cpu_waveform.vcd");
        $dumpvars(0, tb_cpu_complete);
        
        // Cargar programa: Fibonacci
        // r1 = 1
        program_memory[0] = 16'b000_001_000_000_0001; // ADDI r1, r0, 1
        
        // r2 = 1
        program_memory[1] = 16'b000_010_000_000_0001; // ADDI r2, r0, 1
        
        // Loop:
        // r3 = r1 + r2
        program_memory[2] = 16'b001_011_001_010_0000; // ADD r3, r1, r2
        
        // GPIO = r3
        program_memory[3] = 16'b110_011_000_000_0000; // STORE r3 to GPIO
        
        // r1 = r2
        program_memory[4] = 16'b001_001_010_000_0000; // ADD r1, r2, r0
        
        // r2 = r3
        program_memory[5] = 16'b001_010_011_000_0000; // ADD r2, r3, r0
        
        // JUMP 2
        program_memory[6] = 16'b111_000_000_000_0010; // JUMP 2
        
        $display("\n╔══════════════════════════════════════════════╗");
        $display("║   MicroRV8-GT CPU Core Test                 ║");
        $display("║   Programa: Secuencia de Fibonacci          ║");
        $display("╚══════════════════════════════════════════════╝\n");
        
        // Reset
        rst_n = 0;
        gpio_in = 0;
        #30 rst_n = 1;
        
        // Ejecutar 200 ciclos
        $display("Ciclo | PC | Estado | GPIO (Fibonacci)");
        $display("------|----| -------|----------------");
        
        repeat(200) begin
            @(posedge clk);
            #1;
            $display("%5d | %2d |   %1d    | %3d", 
                     $time/10, debug_pc, debug_state[2:0], gpio_out);
        end
        
        $display("\n✅ Simulación completa");
        $display("💡 Revisa que GPIO muestre: 1, 1, 2, 3, 5, 8, 13...\n");
        
        $finish;
    end

endmodule