`default_nettype none
// ============================================================================
// Tang Nano 9K - Top Level - MicroRV8-GT
// ============================================================================
// Mapeo de pines Tang Nano 9K:
//   CLK   -> Pin 52 (27 MHz oscilador interno)
//   RST_N -> Botton S1 (Pin 4, activo bajo)
//   LEDs  -> gpio_out[5:0] (Pines 10,11,13,14,15,16)
//   UART TX -> Pin 18 (TX a USB-UART del FPGA)
//   UART RX -> Pin 17 (RX desde USB-UART del FPGA)
//   PWM   -> Pin 25 (salida PWM libre)
//
// Para sintetizar en Gowin IDE:
//   1. Crear proyecto GW1NR-9 (Tang Nano 9K)
//   2. Agregar todos los archivos .v de este directorio
//   3. Definir este módulo como top
//   4. Asignar pines según .cst incluido en este proyecto
// ============================================================================

module tang_nano_top (
    input  wire       sys_clk,      // 27 MHz
    input  wire       sys_rst_n,    // Botón S1

    // LEDs (activo bajo en Tang Nano 9K)
    output wire [5:0] led_n,

    // UART (hacia conversor USB-UART de la placa)
    input  wire       uart_rx,
    output wire       uart_tx,

    // PWM
    output wire       pwm_out
);

    // Señales GPIO completas del sistema
    wire [7:0] gpio_out_full;
    wire [7:0] gpio_dir_full;

    microrv8_system #(
        .CLK_FREQ  (27_000_000),
        .BAUD_RATE (115200)
    ) sys (
        .clk          (sys_clk),
        .rst_n        (sys_rst_n),
        .gpio_in      (8'h00),          // Sin entradas GPIO físicas en este ejemplo
        .gpio_out     (gpio_out_full),
        .gpio_dir     (gpio_dir_full),
        .uart_rx_pin  (uart_rx),
        .uart_tx_pin  (uart_tx),
        .pwm_pin      (pwm_out),
        // Debug no conectado a pines (usar SignalTap o comentar)
        .debug_pc     (),
        .debug_state  (),
        .debug_instr  ()
    );

    // Los 6 LEDs muestran los 6 bits bajos del GPIO
    // LEDs activos en bajo en Tang Nano 9K
    assign led_n = ~gpio_out_full[5:0];

endmodule

`default_nettype wire
