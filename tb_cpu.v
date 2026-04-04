`default_nettype none
`timescale 1ns / 1ps
// ============================================================================
// Testbench - CPU Core (unit test) - ISA revision 2
// ============================================================================
// Memoria de instrucciones asincrona para testing directo sin latencia BRAM.
//
// Programa de prueba:
//   0: ADDI r1, r0, 5    r1=5
//   1: ADDI r2, r0, 3    r2=3
//   2: ADD  r3, r1, r2   r3=8
//   3: SUB  r4, r1, r2   r4=2
//   4: AND  r5, r1, r2   r5=1
//   5: OR   r6, r1, r2   r6=7
//   6: OUT  r1           gpio=5
//   7: BEQ  r4, r4, 1   branch tomado -> PC=9
//   8: NOP               no se ejecuta
//   9: JUMP 0            loop
// ============================================================================

module tb_cpu;

    reg clk, rst_n;

    wire [8:0]  pc;
    wire [15:0] instruction;
    wire [7:0]  mem_addr, mem_wdata;
    reg  [7:0]  mem_rdata;
    wire        mem_we, mem_re;
    wire [7:0]  gpio_out;
    wire [7:0]  debug_pc, debug_state;
    wire [15:0] debug_instr;

    reg [15:0] imem [0:31];
    assign instruction = imem[pc[4:0]];

    cpu_core dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .pc_out         (pc),
        .instruction_in (instruction),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_rdata      (mem_rdata),
        .mem_we         (mem_we),
        .mem_re         (mem_re),
        .gpio_out       (gpio_out),
        .debug_pc       (debug_pc),
        .debug_state    (debug_state),
        .debug_instr    (debug_instr)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer k, errors;

    initial begin
        $dumpfile("tb_cpu.vcd");
        $dumpvars(0, tb_cpu);

        for (k = 0; k < 32; k = k + 1) imem[k] = 16'h0000;
        mem_rdata = 8'hAB;
        errors = 0;

        // ISA revision 2 encodings
        // I-type: [15:13]=op [12:10]=rd [9:7]=rs1 [6:4]=funct3 [3:0]=imm4
        // R-type: [15:13]=op [12:10]=rd [9:7]=rs1 [6:4]=rs2    [3:1]=funct3 [0]=0
        // B-type: [15:13]=op [12:10]=rs1 [9:7]=rs2 [3:0]=imm4
        // J-type: [15:13]=op [12:10]=rd  [9:0]=target
        // O-type: [15:13]=op [12:10]=0   [9:7]=rs1

        // 0: ADDI r1, r0, 5  -> op=000 rd=001 rs1=000 funct3=000 imm=0101
        imem[0]  = 16'b000_001_000_000_0101;
        // 1: ADDI r2, r0, 3  -> op=000 rd=010 rs1=000 funct3=000 imm=0011
        imem[1]  = 16'b000_010_000_000_0011;
        // 2: ADD r3, r1, r2  -> op=001 rd=011 rs1=001 rs2=010 funct3=000(ADD)
        //    R-type: [3:1]=funct3=000
        imem[2]  = 16'b001_011_001_010_0000;  // funct3 en [3:1]=000, [0]=0
        // 3: SUB r4, r1, r2  -> op=001 rd=100 rs1=001 rs2=010 funct3=001(SUB)
        //    [3:1]=001 [0]=0 -> [3:0]=0010
        imem[3]  = 16'b001_100_001_010_0010;
        // 4: AND r5, r1, r2  -> funct3=010 -> [3:0]=0100
        imem[4]  = 16'b001_101_001_010_0100;
        // 5: OR  r6, r1, r2  -> funct3=011 -> [3:0]=0110
        imem[5]  = 16'b001_110_001_010_0110;
        // 6: OUT r1          -> op=110 [12:10]=000 [9:7]=rs1=001
        imem[6]  = 16'b110_000_001_000_0000;
        // 7: BEQ r4, r4, 1  -> op=100 rs1=100 rs2=100 imm=0001
        //    PC_next = PC+1+1 = 7+1+1 = 9 (salta sobre NOP)
        imem[7]  = 16'b100_100_100_000_0001;
        // 8: NOP             -> no debe ejecutarse
        imem[8]  = 16'h0000;
        // 9: JUMP 0          -> op=111 target=0
        imem[9]  = 16'b111_000_000_000_0000;

        $display("=== CPU Core Unit Test (ISA r2) ===");
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        $display("[%0t ns] Reset liberado", $time);

        // 10 instrucciones x 5 ciclos = 50 ciclos por vuelta; correr 3 vueltas
        repeat(160) @(posedge clk);

        $display("[%0t ns] GPIO = 0x%02X (esperado 0x05)", $time, gpio_out);
        if (gpio_out !== 8'h05) begin
            $display("FAIL: GPIO incorrecto (obtenido 0x%02X)", gpio_out);
            errors = errors + 1;
        end else
            $display("PASS: GPIO = 5 correcto");

        $display("[%0t ns] PC = 0x%02X", $time, debug_pc);
        $display("[%0t ns] Estado = %0d", $time, debug_state[2:0]);

        $display("");
        if (errors == 0)
            $display("RESULTADO: PASS");
        else
            $display("RESULTADO: FAIL (%0d errores)", errors);
        $display("=== Fin ===");
        $finish;
    end

    initial begin #5_000_000; $display("TIMEOUT"); $finish; end

endmodule

`default_nettype wire
