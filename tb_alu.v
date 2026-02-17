`timescale 1ns/1ps

module tb_alu;
    reg [7:0] a, b;
    reg [2:0] op;
    wire [7:0] result;
    wire zero, carry, negative;
    
    // Instanciar ALU
    alu_8bit dut (
        .a(a),
        .b(b),
        .op(op),
        .result(result),
        .zero(zero),
        .carry(carry),
        .negative(negative)
    );
    
    // Nombres de operaciones para display
    reg [31:0] op_name;
    always @(*) begin
        case (op)
            3'b000: op_name = "ADD";
            3'b001: op_name = "SUB";
            3'b010: op_name = "AND";
            3'b011: op_name = "OR ";
            3'b100: op_name = "XOR";
            3'b101: op_name = "SLL";
            3'b110: op_name = "SRL";
            3'b111: op_name = "SLT";
            default: op_name = "???";
        endcase
    end
    
    // Test vectors
    integer errors = 0;
    
    task check_result;
        input [7:0] expected;
        input [31:0] test_name;
        begin
            #1;
            if (result !== expected) begin
                $display(" ERROR: %s", test_name);
                $display("   A=%d, B=%d, Op=%s", a, b, op_name);
                $display("   Expected: %d, Got: %d", expected, result);
                errors = errors + 1;
            end else begin
                $display(" PASS: %s (A=%d, B=%d, Result=%d)", 
                         op_name, a, b, result);
            end
        end
    endtask
    
    initial begin
        $dumpfile("sim/alu_waveform.vcd");
        $dumpvars(0, tb_alu);
        
        $display("\n╔════════════════════════════════════════╗");
        $display("║   MicroRV8-GT ALU Test Suite         ║");
        $display("║   Diseñado en Guatemala 🇬🇹            ║");
        $display("╚════════════════════════════════════════╝\n");
        
        // Test 1: Suma
        $display("─── Test 1: Adición ───");
        a = 8'd5; b = 8'd3; op = 3'b000;
        check_result(8'd8, "5 + 3 = 8");
        
        a = 8'd255; b = 8'd1; op = 3'b000;
        check_result(8'd0, "255 + 1 = 0 (overflow)");
        if (!carry) begin
            $display(" ERROR: Carry flag debería estar activo");
            errors = errors + 1;
        end
        
        // Test 2: Resta
        $display("\n─── Test 2: Sustracción ───");
        a = 8'd10; b = 8'd3; op = 3'b001;
        check_result(8'd7, "10 - 3 = 7");
        
        a = 8'd3; b = 8'd10; op = 3'b001;
        check_result(8'd249, "3 - 10 = -7 (249 en complemento a 2)");
        
        // Test 3: Operaciones lógicas
        $display("\n─── Test 3: Operaciones Lógicas ───");
        a = 8'b11110000; b = 8'b10101010; op = 3'b010;
        check_result(8'b10100000, "AND");
        
        a = 8'b11110000; b = 8'b10101010; op = 3'b011;
        check_result(8'b11111010, "OR");
        
        a = 8'b11110000; b = 8'b10101010; op = 3'b100;
        check_result(8'b01011010, "XOR");
        
        // Test 4: Shifts
        $display("\n─── Test 4: Desplazamientos ───");
        a = 8'b00000011; b = 8'd2; op = 3'b101;
        check_result(8'b00001100, "3 << 2 = 12");
        
        a = 8'b11000000; b = 8'd2; op = 3'b110;
        check_result(8'b00110000, "192 >> 2 = 48");
        
        // Test 5: Comparación
        $display("\n─── Test 5: Comparación (SLT) ───");
        a = 8'd5; b = 8'd10; op = 3'b111;
        check_result(8'd1, "5 < 10 = TRUE");
        
        a = 8'd10; b = 8'd5; op = 3'b111;
        check_result(8'd0, "10 < 5 = FALSE");
        
        // Test 6: Flag Zero
        $display("\n─── Test 6: Zero Flag ───");
        a = 8'd5; b = 8'd5; op = 3'b001;
        #1;
        if (zero)
            $display(" PASS: Zero flag activo (5 - 5 = 0)");
        else begin
            $display(" ERROR: Zero flag debería estar activo");
            errors = errors + 1;
        end
        
        // Resumen
        $display("\n╔════════════════════════════════════════╗");
        if (errors == 0) begin
            $display("║    TODOS LOS TESTS PASARON       ║");
            $display("║   Tu ALU funciona perfectamente       ║");
        end else begin
            $display("║     %0d ERRORES ENCONTRADOS          ║", errors);
            $display("║   Revisa el código y reintenta        ║");
        end
        $display("╚════════════════════════════════════════╝\n");
        
        $finish;
    end

endmodule