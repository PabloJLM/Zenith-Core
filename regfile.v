`default_nettype none

// Banco de registros: 8 registros x 8 bits
// Arquitectura RISC-V style: r0 siempre es 0
module regfile (
    input wire clk,
    input wire rst_n,
    
    // Puerto de lectura 1
    input wire [2:0] rs1_addr,
    output wire [7:0] rs1_data,
    
    // Puerto de lectura 2
    input wire [2:0] rs2_addr,
    output wire [7:0] rs2_data,
    
    // Puerto de escritura
    input wire [2:0] rd_addr,
    input wire [7:0] rd_data,
    input wire rd_we            // Write enable
);

    // 8 registros de 8 bits
    reg [7:0] registers [0:7];
    
    // Lecturas son combinacionales
    assign rs1_data = (rs1_addr == 3'b000) ? 8'h00 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 3'b000) ? 8'h00 : registers[rs2_addr];
    
    // Escritura es síncrona
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset: todos los registros a 0
            registers[0] <= 8'h00;
            registers[1] <= 8'h00;
            registers[2] <= 8'h00;
            registers[3] <= 8'h00;
            registers[4] <= 8'h00;
            registers[5] <= 8'h00;
            registers[6] <= 8'h00;
            registers[7] <= 8'h00;
        end else if (rd_we && rd_addr != 3'b000) begin
            // r0 nunca se escribe (siempre 0 en RISC-V)
            registers[rd_addr] <= rd_data;
        end
    end

endmodule

`default_nettype wire