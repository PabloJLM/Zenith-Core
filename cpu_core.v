`default_nettype none

// MicroRV8-GT CPU Core
// Primer microcontrolador guatemalteco diseñado desde cero
// Arquitectura: RISC-V subset de 8 bits
module cpu_core (
    input wire clk,
    input wire rst_n,
    
    // Interface de memoria externa
    output wire [7:0] mem_addr,
    input wire [15:0] mem_rdata,
    output wire [7:0] mem_wdata,
    output wire mem_we,
    
    // GPIO (para debug y I/O)
    output wire [7:0] gpio_out,
    input wire [7:0] gpio_in,
    
    // Debug signals
    output wire [7:0] debug_pc,
    output wire [7:0] debug_state
);

    // ========== PROGRAM COUNTER ==========
    reg [7:0] pc;
    assign debug_pc = pc;
    assign mem_addr = pc;
    
    // ========== INSTRUCTION REGISTER ==========
    reg [15:0] ir;
    wire [2:0] opcode = ir[15:13];
    wire [2:0] rd = ir[12:10];
    wire [2:0] rs1 = ir[9:7];
    wire [2:0] rs2 = ir[6:4];
    wire [3:0] imm = ir[3:0];
    wire [7:0] imm_ext = {{4{imm[3]}}, imm}; // Sign extend
    
    // ========== REGISTER FILE ==========
    wire [7:0] rs1_data, rs2_data;
    reg [7:0] rd_data;
    reg rd_we;
    
    regfile rf (
        .clk(clk),
        .rst_n(rst_n),
        .rs1_addr(rs1),
        .rs1_data(rs1_data),
        .rs2_addr(rs2),
        .rs2_data(rs2_data),
        .rd_addr(rd),
        .rd_data(rd_data),
        .rd_we(rd_we)
    );
    
    // ========== ALU ==========
    wire [7:0] alu_a, alu_b;
    reg [2:0] alu_op;
    wire [7:0] alu_result;
    wire alu_zero, alu_carry, alu_negative;
    
    alu_8bit alu (
        .a(alu_a),
        .b(alu_b),
        .op(alu_op),
        .result(alu_result),
        .zero(alu_zero),
        .carry(alu_carry),
        .negative(alu_negative)
    );
    
    // ALU input muxes
    assign alu_a = rs1_data;
    assign alu_b = (opcode == 3'b000) ? imm_ext : rs2_data;
    
    // ========== CONTROL FSM ==========
    localparam STATE_FETCH   = 3'b000;
    localparam STATE_DECODE  = 3'b001;
    localparam STATE_EXECUTE = 3'b010;
    localparam STATE_MEMORY  = 3'b011;
    localparam STATE_WRITE   = 3'b100;
    
    reg [2:0] state;
    assign debug_state = {5'b0, state};
    
    // ========== GPIO REGISTER ==========
    reg [7:0] gpio_reg;
    assign gpio_out = gpio_reg;
    
    // ========== MAIN FSM ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_FETCH;
            pc <= 8'h00;
            ir <= 16'h0000;
            rd_we <= 0;
            gpio_reg <= 8'h00;
            alu_op <= 3'b000;
        end else begin
            case (state)
                STATE_FETCH: begin
                    ir <= mem_rdata;
                    state <= STATE_DECODE;
                end
                
                STATE_DECODE: begin
                    // Preparar ALU operation
                    case (opcode)
                        3'b000, 3'b001: alu_op <= rs1; // ALU ops
                        default: alu_op <= 3'b000;
                    endcase
                    state <= STATE_EXECUTE;
                end
                
                STATE_EXECUTE: begin
                    state <= STATE_MEMORY;
                end
                
                STATE_MEMORY: begin
                    // Acceso a memoria o GPIO
                    if (opcode == 3'b110) begin // STORE to GPIO
                        gpio_reg <= rs1_data;
                    end
                    state <= STATE_WRITE;
                end
                
                STATE_WRITE: begin
                    // Writeback
                    rd_we <= 0;
                    case (opcode)
                        3'b000, 3'b001: begin // ALU ops
                            rd_data <= alu_result;
                            rd_we <= 1;
                            pc <= pc + 1;
                        end
                        3'b111: begin // JUMP
                            pc <= imm_ext;
                        end
                        default: begin
                            pc <= pc + 1;
                        end
                    endcase
                    state <= STATE_FETCH;
                end
                
                default: state <= STATE_FETCH;
            endcase
        end
    end
    
    // Memory write (para futuro)
    assign mem_wdata = rs2_data;
    assign mem_we = 0;

endmodule

`default_nettype wire