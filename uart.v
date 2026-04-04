`default_nettype none
// ============================================================================
// UART TX - MicroRV8-GT
// ============================================================================
// 8N1, baud rate configurable por parámetro.
// Tang Nano 9K = 27 MHz -> BAUD_DIV = 27_000_000 / 115200 = 234
// Para simulación usar CLK_FREQ bajo (ej: 1_000_000) para no esperar miles de ciclos.
// ============================================================================

module uart_tx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,      // Byte a enviar
    input  wire       tx_start,     // Pulso de 1 ciclo para iniciar
    output reg        tx_busy,      // 1 mientras transmite
    output reg        tx            // Pin serial (idle = 1)
);

    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0]  state;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;
    reg [15:0] baud_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            tx        <= 1'b1;
            tx_busy   <= 1'b0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'h00;
            baud_cnt  <= 16'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        shift_reg <= data_in;
                        tx_busy   <= 1'b1;
                        baud_cnt  <= 16'd0;
                        state     <= ST_START;
                    end
                end

                ST_START: begin
                    tx <= 1'b0;                         // start bit
                    if (baud_cnt < BAUD_DIV - 1) begin
                        baud_cnt <= baud_cnt + 1;
                    end else begin
                        baud_cnt <= 16'd0;
                        bit_idx  <= 3'd0;
                        state    <= ST_DATA;
                    end
                end

                ST_DATA: begin
                    tx <= shift_reg[0];                 // LSB primero
                    if (baud_cnt < BAUD_DIV - 1) begin
                        baud_cnt <= baud_cnt + 1;
                    end else begin
                        baud_cnt  <= 16'd0;
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx == 3'd7) begin
                            state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end

                ST_STOP: begin
                    tx <= 1'b1;                         // stop bit
                    if (baud_cnt < BAUD_DIV - 1) begin
                        baud_cnt <= baud_cnt + 1;
                    end else begin
                        baud_cnt <= 16'd0;
                        state    <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule


// ============================================================================
// UART RX - MicroRV8-GT
// ============================================================================
// Receptor para programar la instruction memory desde PC vía UART.
// El host envía pares de bytes (instrucción 16 bits, big-endian).
// ============================================================================

module uart_rx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,           // Pin serial entrada (idle = 1)
    output reg  [7:0] data_out,     // Byte recibido
    output reg        data_valid    // Pulso 1 ciclo cuando byte listo
);

    localparam BAUD_DIV  = CLK_FREQ / BAUD_RATE;
    localparam HALF_DIV  = BAUD_DIV / 2;

    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0]  state;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;
    reg [15:0] baud_cnt;

    // Sincronizador de 2 flip-flops para rx (cruce de dominio de clock)
    reg rx_s1, rx_s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rx_s1 <= 1'b1; rx_s <= 1'b1; end
        else begin rx_s1 <= rx; rx_s <= rx_s1; end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            data_out   <= 8'h00;
            data_valid <= 1'b0;
            bit_idx    <= 3'd0;
            shift_reg  <= 8'h00;
            baud_cnt   <= 16'd0;
        end else begin
            data_valid <= 1'b0;     // default

            case (state)
                ST_IDLE: begin
                    if (!rx_s) begin    // flanco bajada = start bit
                        baud_cnt <= 16'd0;
                        state    <= ST_START;
                    end
                end

                ST_START: begin
                    // Muestrear en el centro del start bit
                    if (baud_cnt < HALF_DIV - 1) begin
                        baud_cnt <= baud_cnt + 1;
                    end else begin
                        baud_cnt <= 16'd0;
                        bit_idx  <= 3'd0;
                        state    <= ST_DATA;
                    end
                end

                ST_DATA: begin
                    if (baud_cnt < BAUD_DIV - 1) begin
                        baud_cnt <= baud_cnt + 1;
                    end else begin
                        baud_cnt  <= 16'd0;
                        shift_reg <= {rx_s, shift_reg[7:1]};  // LSB primero
                        if (bit_idx == 3'd7) begin
                            state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end

                ST_STOP: begin
                    if (baud_cnt < BAUD_DIV - 1) begin
                        baud_cnt <= baud_cnt + 1;
                    end else begin
                        baud_cnt   <= 16'd0;
                        data_out   <= shift_reg;
                        data_valid <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule


// ============================================================================
// UART MMIO Wrapper - MicroRV8-GT
// ============================================================================
// Registros:
//   0x83 UART_TX   (W) - escribe byte para transmitir
//   0x84 UART_STAT (R) - bit0 = tx_busy
// ============================================================================

module uart_mmio #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire        clk,
    input  wire        rst_n,

    // Bus MMIO
    input  wire [7:0]  mmio_addr,
    input  wire [7:0]  mmio_data_in,
    output reg  [7:0]  mmio_data_out,
    input  wire        mmio_we,
    input  wire        mmio_re,

    // Pines físicos
    output wire        uart_tx_pin
);

    localparam ADDR_TX   = 8'h83;
    localparam ADDR_STAT = 8'h84;

    reg [7:0] tx_data;
    reg       tx_start;
    wire      tx_busy;

    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .data_in  (tx_data),
        .tx_start (tx_start),
        .tx_busy  (tx_busy),
        .tx       (uart_tx_pin)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data  <= 8'h00;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            if (mmio_we && mmio_addr == ADDR_TX && !tx_busy) begin
                tx_data  <= mmio_data_in;
                tx_start <= 1'b1;
            end
        end
    end

    always @(*) begin
        mmio_data_out = 8'h00;
        if (mmio_re && mmio_addr == ADDR_STAT)
            mmio_data_out = {7'b0, tx_busy};
    end

endmodule

`default_nettype wire
