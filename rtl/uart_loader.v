`default_nettype none
// ============================================================================
// UART Loader - MicroRV8-GT
// ============================================================================
// Permite cargar un programa en la instruction memory desde una PC via UART.
// Protocolo:
//   1. Host envía 0xAA 0x55 (sync header)
//   2. Host envía 2 bytes: numero de instrucciones (big-endian, max 512)
//   3. Host envía N*2 bytes: instrucciones (big-endian, 16 bits cada una)
//   4. Loader pulsa done cuando termina; CPU sale de reset
//
// Mientras loading=1, el CPU permanece en reset.
// ============================================================================

module uart_loader #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire        clk,
    input  wire        rst_n,

    // Pin UART RX
    input  wire        rx,

    // Interfaz con instruction memory
    output reg  [8:0]  wr_addr,     // Dirección a escribir en ROM
    output reg  [15:0] wr_data,     // Instrucción a escribir
    output reg         wr_en,       // Pulso de escritura

    // Control
    output reg         loading,     // 1 = cargando (CPU en reset)
    output reg         load_done    // Pulso cuando carga terminó
);

    // Estados del protocolo
    localparam ST_SYNC1   = 3'd0;   // Esperar 0xAA
    localparam ST_SYNC2   = 3'd1;   // Esperar 0x55
    localparam ST_LEN_HI  = 3'd2;   // Byte alto del conteo
    localparam ST_LEN_LO  = 3'd3;   // Byte bajo del conteo
    localparam ST_INSTR_H = 3'd4;   // Byte alto de instrucción
    localparam ST_INSTR_L = 3'd5;   // Byte bajo de instrucción
    localparam ST_DONE    = 3'd6;   // Carga completa

    reg [2:0]  state;
    reg [8:0]  total;               // Cantidad de instrucciones a recibir
    reg [8:0]  count;               // Instrucciones recibidas
    reg [7:0]  instr_hi;            // Byte alto temporal

    // Señales del UART RX
    wire [7:0] rx_byte;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx         (rx),
        .data_out   (rx_byte),
        .data_valid (rx_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_SYNC1;
            loading   <= 1'b0;
            load_done <= 1'b0;
            wr_en     <= 1'b0;
            wr_addr   <= 9'd0;
            wr_data   <= 16'd0;
            total     <= 9'd0;
            count     <= 9'd0;
            instr_hi  <= 8'd0;
        end else begin
            wr_en     <= 1'b0;
            load_done <= 1'b0;

            case (state)
                ST_SYNC1: begin
                    if (rx_valid && rx_byte == 8'hAA) begin
                        state   <= ST_SYNC2;
                        loading <= 1'b1;
                    end
                end

                ST_SYNC2: begin
                    if (rx_valid) begin
                        if (rx_byte == 8'h55)
                            state <= ST_LEN_HI;
                        else
                            state <= ST_SYNC1;  // sync perdido, reintentar
                    end
                end

                ST_LEN_HI: begin
                    if (rx_valid) begin
                        total[8]   <= rx_byte[0];   // solo bit 0 (max 512)
                        state      <= ST_LEN_LO;
                    end
                end

                ST_LEN_LO: begin
                    if (rx_valid) begin
                        total[7:0] <= rx_byte;
                        count      <= 9'd0;
                        wr_addr    <= 9'd0;
                        state      <= ST_INSTR_H;
                    end
                end

                ST_INSTR_H: begin
                    if (rx_valid) begin
                        instr_hi <= rx_byte;
                        state    <= ST_INSTR_L;
                    end
                end

                ST_INSTR_L: begin
                    if (rx_valid) begin
                        wr_data <= {instr_hi, rx_byte};
                        wr_en   <= 1'b1;
                        count   <= count + 9'd1;
                        wr_addr <= wr_addr + 9'd1;

                        if (count + 9'd1 >= total)
                            state <= ST_DONE;
                        else
                            state <= ST_INSTR_H;
                    end
                end

                ST_DONE: begin
                    loading   <= 1'b0;
                    load_done <= 1'b1;
                    state     <= ST_SYNC1;  // listo para próxima carga
                end

                default: state <= ST_SYNC1;
            endcase
        end
    end

endmodule

`default_nettype wire
