`default_nettype none
// ============================================================================
// Instruction Memory - MicroRV8-GT
// ============================================================================
// - Lectura combinacional (sin latencia de BRAM)
// - Escritura sincrona para uart_loader
// - Sin loop for en initial (compatible con Gowin EDA)
// - Programa por defecto: contador visible en LEDs (~6 Hz)
//
// Registros del programa:
//   r1 = contador GPIO  (incrementa en cada vuelta)
//   r2 = inner loop     (cuenta 0->255 con overflow, 256 iters)
//   r3 = mid loop       (cuenta 0->255 con overflow, 256 iters)
//   r4 = outer loop     (cuenta desde 7 hasta 0, 7 iters)
//   Delay total: 7 * 256 * 256 iteraciones ~ 0.17s por cambio
// ============================================================================

module instruction_memory (
    input  wire        clk,
    input  wire [8:0]  addr,
    output wire [15:0] data_out,
    input  wire [8:0]  wr_addr,
    input  wire [15:0] wr_data,
    input  wire        wr_en
);

    (* ram_style = "block" *) reg [15:0] rom [0:511];

    assign data_out = rom[addr];

    always @(posedge clk) begin
        if (wr_en)
            rom[wr_addr] <= wr_data;
    end

    initial begin

`ifdef PROGRAM_HEX
        $readmemh(`PROGRAM_HEX, rom);
`else
        // Encodings verificados para cpu_core.v ISA v2:
        //   I-type: [15:13]=000 [12:10]=rd  [9:7]=rs1  [6:4]=funct3 [3:0]=imm4
        //   B-type: [15:13]=100 [12:10]=rs1 [9:7]=rs2  [3:0]=imm4 (offset relativo PC+1)
        //   J-type: [15:13]=111 [8:0]=target (f_tgt = ir[8:0])
        //   O-type: [15:13]=110 [9:7]=rs1
        //   funct3: ADD=000   imm -1 = 4'b1111

        rom[0]  = 16'h0400; // ADDI r1, r0,  0    r1 = 0
        rom[1]  = 16'h0481; // ADDI r1, r1,  1    r1++           [main_loop]
        rom[2]  = 16'hC080; // OUT  r1             GPIO = r1
        rom[3]  = 16'h1007; // ADDI r4, r0,  7    r4 = 7
        rom[4]  = 16'h0C00; // ADDI r3, r0,  0    r3 = 0         [outer_loop]
        rom[5]  = 16'h0D8F; // ADDI r3, r3, -1    r3--           [mid_loop]
        rom[6]  = 16'h0800; // ADDI r2, r0,  0    r2 = 0
        rom[7]  = 16'h090F; // ADDI r2, r2, -1    r2--           [inner_loop]
        rom[8]  = 16'h8801; // BEQ  r2, r0,  +1   si r2==0 saltar a addr 10
        rom[9]  = 16'hE007; // JUMP 7              loop inner
        rom[10] = 16'h8C01; // BEQ  r3, r0,  +1   si r3==0 saltar a addr 12
        rom[11] = 16'hE005; // JUMP 5              loop mid
        rom[12] = 16'h120F; // ADDI r4, r4, -1    r4--
        rom[13] = 16'h9001; // BEQ  r4, r0,  +1   si r4==0 saltar a addr 15
        rom[14] = 16'hE004; // JUMP 4              loop outer
        rom[15] = 16'hE001; // JUMP 1              fin delay -> main_loop
`endif
    end

endmodule

`default_nettype wire