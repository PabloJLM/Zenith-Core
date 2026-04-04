`default_nettype none
// ============================================================================
// Instruction Memory - MicroRV8-GT
// ============================================================================
// 512 x 16 bits. Lectura COMBINACIONAL (sin latencia) para que el CPU
// vea la instruccion en el mismo ciclo que presenta el PC.
// Escritura SINCRONA desde uart_loader.
//
// ISA v2 encoding para el programa por defecto (contador en GPIO):
//   Tipo I:  [000|rd|rs1|funct3|imm4]
//   Tipo R:  [001|rd|rs1|funct3|rs2|0]
//   Tipo O:  [110|000|rs1|000|0000]
//   Tipo B:  [100|rs1_beq|rs2_beq|000|imm4]  (rs1=[12:10], rs2=[9:7])
//   Tipo J:  [111|target13]
// ============================================================================

module instruction_memory (
    input  wire        clk,
    input  wire [8:0]  addr,
    output wire [15:0] data_out,
    input  wire [8:0]  wr_addr,
    input  wire [15:0] wr_data,
    input  wire        wr_en
);

    reg [15:0] rom [0:511];

    // Lectura combinacional
    assign data_out = rom[addr];

    // Escritura sincrona (loader)
    always @(posedge clk) begin
        if (wr_en) rom[wr_addr] <= wr_data;
    end

    integer i;
    initial begin
        for (i = 0; i < 512; i = i + 1) rom[i] = 16'h0000;

`ifdef PROGRAM_HEX
        $readmemh(`PROGRAM_HEX, rom);
`else
        // ----------------------------------------------------------------
        // Programa: contador r1 visible en GPIO, con delay de 15 pasos
        //
        // r1 = contador
        // r2 = variable delay
        // r3 = maximo delay (15)
        // r4 = temporal (r2 - r3 para comparacion)
        //
        // Codificacion ISA v2:
        //
        // Tipo I  [000|rd|rs1|funct3|imm4]
        //   ADDI rd, rs1, imm:  funct3=000(ADD)
        //
        // Tipo R  [001|rd|rs1|funct3|rs2|0]
        //   SUB rd, rs1, rs2:   funct3=001(SUB)
        //   ADD rd, rs1, rs2:   funct3=000(ADD)
        //
        // Tipo O  [110|000|rs1|000|0000]
        //   OUT rs1
        //
        // Tipo B  [100|rs1|rs2|000|imm4]   rs1=[12:10], rs2=[9:7]
        //   BEQ rs1, rs2, offset
        //
        // Tipo J  [111|000000000000000] pero solo 9 bits de target en [8:0]
        //   JUMP target:  [111|xxxx|target9]
        // ----------------------------------------------------------------

        // 0: ADDI r1, r0, 0    -> r1 = 0
        //    [000|001|000|000|0000]
        rom[0] = 16'b000_001_000_000_0000;

        // 1: ADDI r3, r0, 15   -> r3 = 15
        //    [000|011|000|000|1111]
        rom[1] = 16'b000_011_000_000_1111;

        // 2: ADDI r1, r1, 1    -> r1++
        //    [000|001|001|000|0001]  rd=r1, rs1=r1, funct3=000(ADD), imm=1
        rom[2] = 16'b000_001_001_000_0001;

        // 3: OUT r1             -> GPIO = r1
        //    [110|000|001|000|0000]
        rom[3] = 16'b110_000_001_000_0000;

        // 4: ADDI r2, r0, 0    -> r2 = 0 (delay = 0)
        //    [000|010|000|000|0000]
        rom[4] = 16'b000_010_000_000_0000;

        // 5: ADDI r2, r2, 1    -> r2++
        //    [000|010|010|000|0001]
        rom[5] = 16'b000_010_010_000_0001;

        // 6: SUB r4, r2, r3    -> r4 = r2 - r3
        //    Tipo R: [001|rd|rs1|funct3|rs2|0]
        //    rd=r4=100, rs1=r2=010, funct3=001(SUB), rs2=r3=011
        //    [001|100|010|001|011|0]
        rom[6] = 16'b001_100_010_001_0110;

        // 7: BEQ r4, r0, -2    -> si r4 == r0(0), PC = 7+1+(-2) = 6
        //    Queremos saltar a addr 5 si r4==0: offset = 5-(7+1) = -3
        //    Tipo B: [100|rs1|rs2|000|imm4]  rs1=r4=[12:10], rs2=r0=[9:7]
        //    imm4 = -3 = 1101 en complemento a 2 de 4 bits
        //    [100|100|000|000|1101]
        rom[7] = 16'b100_100_000_000_1101;

        // 8: JUMP 2             -> PC = 2 (loop principal)
        //    Tipo J: [111|target13] target=2 en bits [8:0]
        //    [111|0000|000000010]
        rom[8] = 16'b111_0000_000000010;
`endif
    end

endmodule

`default_nettype wire
