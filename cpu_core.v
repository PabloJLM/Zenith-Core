`default_nettype none
// ============================================================================
// CPU Core - MicroRV8-GT  (ISA v2 - definitivo)
// ============================================================================
// Formato de instruccion (16 bits):
//
//  Tipo I  [000|rd|rs1|funct3|imm4]   ALU-Immediate
//  Tipo R  [001|rd|rs1|funct3|rs2|0]  ALU-Register  (rs2 en bits[3:1])
//  Tipo L  [010|rd|rs1|000|imm4]      Load
//  Tipo S  [011|rs2|rs1|000|imm4]     Store  (dato=rs2 en [12:10])
//  Tipo B  [100|rs1|rs2|000|imm4]     BEQ    (offset relativo)
//  Tipo K  [101|rd|target9]           JAL    (target en [8:0])
//  Tipo O  [110|000|rs1|000|0000]     OUT    (GPIO)
//  Tipo J  [111|target13]             JUMP   (target en [12:0], usamos [8:0])
//
// funct3: 000=ADD 001=SUB 010=AND 011=OR 100=XOR 101=SLL 110=SRL 111=SLT
//
// BEQ: si regfile[rs1] == regfile[rs2], PC = PC+1+sign_ext(imm4)
//      rs1 en [12:10], rs2 en [9:7]
// ============================================================================

module cpu_core (
    input  wire        clk,
    input  wire        rst_n,
    output wire [8:0]  pc_out,
    input  wire [15:0] instruction_in,
    output reg  [7:0]  mem_addr,
    output reg  [7:0]  mem_wdata,
    input  wire [7:0]  mem_rdata,
    output reg         mem_we,
    output reg         mem_re,
    output reg  [7:0]  gpio_out,
    output wire [7:0]  debug_pc,
    output wire [7:0]  debug_state,
    output wire [15:0] debug_instr
);

    reg [8:0]  pc;
    reg [15:0] ir;

    assign pc_out      = pc;
    assign debug_pc    = pc[7:0];
    assign debug_instr = ir;

    // Campos del instruction register
    wire [2:0] f_op  = ir[15:13];
    wire [2:0] f_rd  = ir[12:10];
    wire [2:0] f_rs1 = ir[9:7];
    wire [2:0] f_fn3 = ir[6:4];
    wire [3:0] f_imm = ir[3:0];
    wire [8:0] f_tgt = ir[8:0];        // target JUMP/JAL
    // rs2 segun tipo:
    wire [2:0] f_rs2_r = ir[3:1];      // ALU-R: rs2 en [3:1]
    // En tipo S: rs2 (dato) esta en [12:10] = f_rd
    // En tipo B: rs1 en [12:10]=f_rd, rs2 en [9:7]=f_rs1

    wire [7:0] se8 = {{4{f_imm[3]}}, f_imm};   // sign-ext 4->8
    wire [8:0] se9 = {{5{f_imm[3]}}, f_imm};   // sign-ext 4->9

    // Regfile
    reg  [2:0] rf_rs2_addr;
    wire [7:0] rdata1, rdata2;
    reg  [7:0] rf_wdata;
    reg        rf_we;

    regfile rf0 (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (f_rs1),
        .rs1_data (rdata1),
        .rs2_addr (rf_rs2_addr),
        .rs2_data (rdata2),
        .rd_addr  (f_rd),
        .rd_data  (rf_wdata),
        .rd_we    (rf_we)
    );

    // ALU - operando B es registro
    reg  [2:0] alu_op;
    reg  [7:0] alu_b;
    wire [7:0] alu_out;
    wire       alu_z, alu_c, alu_n;

    alu_8bit alu0 (
        .a        (rdata1),
        .b        (alu_b),
        .op       (alu_op),
        .result   (alu_out),
        .zero     (alu_z),
        .carry    (alu_c),
        .negative (alu_n)
    );

    // Latches de resultado
    reg [7:0] res_lat;
    reg       z_lat;

    // FSM
    localparam S0=3'd0,S1=3'd1,S2=3'd2,S3=3'd3,S4=3'd4;
    reg [2:0] st;
    assign debug_state = {5'b0, st};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= S0;
            pc          <= 9'd0;
            ir          <= 16'd0;
            rf_we       <= 0;
            rf_wdata    <= 0;
            alu_op      <= 0;
            alu_b       <= 0;
            res_lat     <= 0;
            z_lat       <= 0;
            mem_we      <= 0;
            mem_re      <= 0;
            mem_addr    <= 0;
            mem_wdata   <= 0;
            gpio_out    <= 0;
            rf_rs2_addr <= 0;
        end else begin
            rf_we  <= 0;
            mem_we <= 0;
            mem_re <= 0;

            case (st)
                //------------------------------------------------------
                // S0 FETCH
                //------------------------------------------------------
                S0: begin
                    ir <= instruction_in;   // combinacional, ya valido
                    st <= S1;
                end

                //------------------------------------------------------
                // S1 DECODE
                //------------------------------------------------------
                S1: begin
                    case (f_op)
                        3'b000: begin   // ALU-I
                            alu_op      <= f_fn3;
                            alu_b       <= se8;
                            rf_rs2_addr <= 3'd0;
                        end
                        3'b001: begin   // ALU-R
                            alu_op      <= f_fn3;
                            rf_rs2_addr <= f_rs2_r;
                            alu_b       <= 8'd0;    // placeholder
                        end
                        3'b010: begin   // LOAD
                            alu_op      <= 3'b000;
                            alu_b       <= se8;
                            rf_rs2_addr <= 3'd0;
                        end
                        3'b011: begin   // STORE  dato=rs2=f_rd, base=rs1=f_rs1
                            alu_op      <= 3'b000;
                            alu_b       <= se8;
                            rf_rs2_addr <= f_rd;    // dato a guardar
                        end
                        3'b100: begin   // BEQ  rs1=f_rd, rs2=f_rs1
                            // rdata1 = regfile[f_rs1] = BEQ.rs2
                            // necesitamos regfile[f_rd] = BEQ.rs1 -> via rdata2
                            alu_op      <= 3'b001;  // SUB
                            rf_rs2_addr <= f_rd;    // BEQ.rs1 como "segundo operando"
                            alu_b       <= 8'd0;    // placeholder
                        end
                        default: begin
                            alu_op      <= 3'b000;
                            alu_b       <= 8'd0;
                            rf_rs2_addr <= 3'd0;
                        end
                    endcase
                    st <= S2;
                end

                //------------------------------------------------------
                // S2 EXECUTE  - rdata2 ya disponible tras DECODE
                //------------------------------------------------------
                S2: begin
                    // ALU-R: alu_b = rs2
                    // BEQ:   calcular rdata2(BEQ.rs1) - rdata1(BEQ.rs2)
                    //        alu_a=rdata1=BEQ.rs2, alu_b=rdata2=BEQ.rs1
                    //        Queremos BEQ.rs1 - BEQ.rs2:
                    //        Usaremos alu con a=rdata2, b=rdata1.
                    //        Como alu_a esta fijo a rdata1, hacemos: alu_b=rdata2
                    //        y el resultado es rdata1 - rdata2. Zero si iguales.
                    if (f_op == 3'b001 || f_op == 3'b100)
                        alu_b <= rdata2;

                    res_lat <= alu_out;
                    z_lat   <= alu_z;
                    st      <= S3;
                end

                //------------------------------------------------------
                // S3 MEMORY - alu_out ahora usa alu_b correcto para R/B
                //------------------------------------------------------
                S3: begin
                    // recapturar resultado con alu_b actualizado (valido este ciclo)
                    if (f_op == 3'b001 || f_op == 3'b100) begin
                        res_lat <= alu_out;
                        z_lat   <= alu_z;
                    end

                    case (f_op)
                        3'b010: begin   // LOAD
                            mem_addr <= res_lat;
                            mem_re   <= 1'b1;
                        end
                        3'b011: begin   // STORE
                            mem_addr  <= res_lat;
                            mem_wdata <= rdata2;    // dato = regfile[f_rd]
                            mem_we    <= 1'b1;
                        end
                        3'b110: gpio_out <= rdata1; // OUT rs1=[9:7]
                        default: ;
                    endcase
                    st <= S4;
                end

                //------------------------------------------------------
                // S4 WRITEBACK
                //------------------------------------------------------
                S4: begin
                    case (f_op)
                        3'b000, 3'b001: begin   // ALU-I / ALU-R
                            rf_wdata <= res_lat;
                            rf_we    <= 1'b1;
                            pc       <= pc + 9'd1;
                        end
                        3'b010: begin           // LOAD
                            rf_wdata <= mem_rdata;
                            rf_we    <= 1'b1;
                            pc       <= pc + 9'd1;
                        end
                        3'b011: pc <= pc + 9'd1; // STORE
                        3'b100: begin            // BEQ
                            if (z_lat) pc <= pc + 9'd1 + se9;
                            else       pc <= pc + 9'd1;
                        end
                        3'b101: begin            // JAL
                            rf_wdata <= pc[7:0] + 8'd1;
                            rf_we    <= 1'b1;
                            pc       <= f_tgt;
                        end
                        3'b110: pc <= pc + 9'd1; // OUT
                        3'b111: pc <= f_tgt;     // JUMP
                        default: pc <= pc + 9'd1;
                    endcase
                    st <= S0;
                end

                default: st <= S0;
            endcase
        end
    end

endmodule

`default_nettype wire
