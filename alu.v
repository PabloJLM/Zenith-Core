`default_nettype none

// ALU de 8 bits - El corazón de tu CPU
module alu_8bit (
    input wire [7:0] a,          // Operando A
    input wire [7:0] b,          // Operando B
    input wire [2:0] op,         // Operación
    output reg [7:0] result,     // Resultado
    output wire zero,            // Flag: resultado es cero
    output wire carry,           // Flag: carry out
    output wire negative         // Flag: resultado negativo
);

    // Operaciones soportadas
    localparam OP_ADD  = 3'b000;
    localparam OP_SUB  = 3'b001;
    localparam OP_AND  = 3'b010;
    localparam OP_OR   = 3'b011;
    localparam OP_XOR  = 3'b100;
    localparam OP_SLL  = 3'b101;  // Shift Left Logical
    localparam OP_SRL  = 3'b110;  // Shift Right Logical
    localparam OP_SLT  = 3'b111;  // Set Less Than

    reg [8:0] result_extended;  // Para detectar carry
    
    always @(*) begin
        result_extended = 9'b0;
        case (op)
            OP_ADD: result_extended = {1'b0, a} + {1'b0, b};
            OP_SUB: result_extended = {1'b0, a} - {1'b0, b};
            OP_AND: result_extended = {1'b0, a & b};
            OP_OR:  result_extended = {1'b0, a | b};
            OP_XOR: result_extended = {1'b0, a ^ b};
            OP_SLL: result_extended = {1'b0, a << b[2:0]};
            OP_SRL: result_extended = {1'b0, a >> b[2:0]};
            OP_SLT: result_extended = {1'b0, (a < b) ? 8'h01 : 8'h00};
            default: result_extended = 9'b0;
        endcase
        
        result = result_extended[7:0];
    end
    
    // Flags
    assign zero = (result == 8'h00);
    assign carry = result_extended[8];
    assign negative = result[7];

endmodule

`default_nettype wire