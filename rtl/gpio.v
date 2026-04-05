`default_nettype none
// ============================================================================
// GPIO 8 bits - MicroRV8-GT
// ============================================================================
// Registros MMIO:
//   0x80 GPIO_OUT  (W) - salida a pines físicos
//   0x81 GPIO_IN   (R) - lectura de pines físicos
//   0x82 GPIO_DIR  (W) - dirección bit a bit: 0=input, 1=output
// ============================================================================

module gpio_8bit (
    input  wire        clk,
    input  wire        rst_n,

    // Bus MMIO
    input  wire [7:0]  mmio_addr,
    input  wire [7:0]  mmio_data_in,
    output reg  [7:0]  mmio_data_out,
    input  wire        mmio_we,
    input  wire        mmio_re,

    // Pines físicos
    input  wire [7:0]  gpio_in,
    output reg  [7:0]  gpio_out,
    output reg  [7:0]  gpio_dir
);

    localparam ADDR_OUT = 8'h80;
    localparam ADDR_IN  = 8'h81;
    localparam ADDR_DIR = 8'h82;

    // Escritura síncrona
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_out <= 8'h00;
            gpio_dir <= 8'hFF;  // todos como output por defecto
        end else if (mmio_we) begin
            case (mmio_addr)
                ADDR_OUT: gpio_out <= mmio_data_in;
                ADDR_DIR: gpio_dir <= mmio_data_in;
                default: ;
            endcase
        end
    end

    // Lectura combinacional
    always @(*) begin
        mmio_data_out = 8'h00;
        if (mmio_re) begin
            case (mmio_addr)
                ADDR_OUT: mmio_data_out = gpio_out;
                ADDR_IN:  mmio_data_out = gpio_in;
                ADDR_DIR: mmio_data_out = gpio_dir;
                default:  mmio_data_out = 8'h00;
            endcase
        end
    end

endmodule

`default_nettype wire
