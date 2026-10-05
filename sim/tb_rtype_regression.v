`default_nettype none
`timescale 1ns / 1ps
// ============================================================================
// Testbench de regresion - Decodificacion R-type (ADD/SUB/AND/OR)
// ============================================================================
// Evidencia reproducible del bug de decodificacion R-type en cpu_core.v:
// rs2 se leia de ir[3:1] (deberia ser ir[6:4]) y funct3 usaba el campo
// de I-type ir[6:4] (deberia ser ir[3:1]). Con r1=5, r2=3 el bug hacia
// que ADD diera r3=0 en vez de 8, y SUB diera r4=5 en vez de 2.
//
// Programa de prueba:
//   0: ADDI r1, r0, 5    r1=5
//   1: ADDI r2, r0, 3    r2=3
//   2: ADD  r3, r1, r2   r3=8  (5+3)
//   3: SUB  r4, r1, r2   r4=2  (5-3)
//   4: AND  r5, r1, r2   r5=1  (5&3)
//   5: OR   r6, r1, r2   r6=7  (5|3)
//   6: JUMP 6            loop infinito (halt)
// ============================================================================

module tb_rtype_regression;

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

    task check8(input [127:0] name, input [7:0] got, input [7:0] expected);
        begin
            if (got !== expected) begin
                $display("FAIL: %0s = 0x%02X (esperado 0x%02X)", name, got, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = 0x%02X correcto", name, got);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_rtype_regression.vcd");
        $dumpvars(0, tb_rtype_regression);

        for (k = 0; k < 32; k = k + 1) imem[k] = 16'h0000;
        mem_rdata = 8'hAB;
        errors = 0;

        // R-type: [15:13]=op(001) [12:10]=rd [9:7]=rs1 [6:4]=rs2 [3:1]=funct3 [0]=0
        // 0: ADDI r1, r0, 5  -> op=000 rd=001 rs1=000 funct3=000 imm=0101
        imem[0] = 16'b000_001_000_000_0101;
        // 1: ADDI r2, r0, 3  -> op=000 rd=010 rs1=000 funct3=000 imm=0011
        imem[1] = 16'b000_010_000_000_0011;
        // 2: ADD r3, r1, r2  -> rd=011 rs1=001 rs2=010 funct3=000(ADD)
        imem[2] = 16'b001_011_001_010_0000;
        // 3: SUB r4, r1, r2  -> rd=100 rs1=001 rs2=010 funct3=001(SUB)
        imem[3] = 16'b001_100_001_010_0010;
        // 4: AND r5, r1, r2  -> rd=101 rs1=001 rs2=010 funct3=010(AND)
        imem[4] = 16'b001_101_001_010_0100;
        // 5: OR  r6, r1, r2  -> rd=110 rs1=001 rs2=010 funct3=011(OR)
        imem[5] = 16'b001_110_001_010_0110;
        // 6: JUMP 6          -> op=111 target=6 (detiene el programa)
        imem[6] = 16'b111_000_000_000_0110;

        $display("=== Regresion R-type: ADD/SUB/AND/OR (r1=5, r2=3) ===");
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        $display("[%0t ns] Reset liberado", $time);

        // 7 instrucciones x 6 ciclos/instr aprox, con margen
        repeat(80) @(posedge clk);

        $display("[%0t ns] r1=0x%02X r2=0x%02X r3=0x%02X r4=0x%02X r5=0x%02X r6=0x%02X",
                  $time, dut.regs[1], dut.regs[2], dut.regs[3], dut.regs[4], dut.regs[5], dut.regs[6]);

        check8("r1 (ADDI)",       dut.regs[1], 8'd5);
        check8("r2 (ADDI)",       dut.regs[2], 8'd3);
        check8("r3 (ADD r1+r2)",  dut.regs[3], 8'd8);
        check8("r4 (SUB r1-r2)",  dut.regs[4], 8'd2);
        check8("r5 (AND r1&r2)",  dut.regs[5], 8'd1);
        check8("r6 (OR  r1|r2)",  dut.regs[6], 8'd7);

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
