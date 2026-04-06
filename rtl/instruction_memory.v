`default_nettype none
// ============================================================================
// Instruction Memory - MicroRV8-GT (BRAM sincrona)
// ============================================================================
// Lectura SINCRONA: la instruccion llega 1 ciclo despues de presentar addr.
// El cpu_core tiene estado S_WAIT para absorber esta latencia.
// Escritura sincrona: uart_loader escribe en el flanco positivo del clock.
// Gowin infiere esto correctamente como SDPB (Simple Dual Port BRAM).
// ============================================================================

module instruction_memory (
    input  wire        clk,
    input  wire [8:0]  addr,
    output reg  [15:0] data_out,   // reg: lectura sincrona
    input  wire [8:0]  wr_addr,
    input  wire [15:0] wr_data,
    input  wire        wr_en
);

    reg [15:0] rom [0:511];

    // Lectura SINCRONA — 1 ciclo de latencia
    always @(posedge clk) begin
        data_out <= rom[addr];
    end

    // Escritura sincrona (uart_loader)
    always @(posedge clk) begin
        if (wr_en)
            rom[wr_addr] <= wr_data;
    end

    initial begin
`ifdef PROGRAM_HEX
        $readmemh(`PROGRAM_HEX, rom);
`else
        rom[0]  = 16'h0400; // ADDI r1, r0,  0
        rom[1]  = 16'h0481; // ADDI r1, r1,  1    [main_loop]
        rom[2]  = 16'hC080; // OUT  r1
        rom[3]  = 16'h1007; // ADDI r4, r0,  7
        rom[4]  = 16'h0C00; // ADDI r3, r0,  0    [outer_loop]
        rom[5]  = 16'h0D8F; // ADDI r3, r3, -1    [mid_loop]
        rom[6]  = 16'h0800; // ADDI r2, r0,  0
        rom[7]  = 16'h090F; // ADDI r2, r2, -1    [inner_loop]
        rom[8]  = 16'h8801; // BEQ  r2, r0, +1
        rom[9]  = 16'hE007; // JUMP 7
        rom[10] = 16'h8C01; // BEQ  r3, r0, +1
        rom[11] = 16'hE005; // JUMP 5
        rom[12] = 16'h120F; // ADDI r4, r4, -1
        rom[13] = 16'h9001; // BEQ  r4, r0, +1
        rom[14] = 16'hE004; // JUMP 4
        rom[15] = 16'hE001; // JUMP 1
`endif
    end

endmodule

`default_nettype wire