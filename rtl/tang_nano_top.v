`default_nettype none
// ============================================================================
// Tang Nano 9K - Top Level - MicroRV8-GT
// ============================================================================
// LED 5 (el más alejado del USB) muestra el estado del uart_loader:
//   LED 5 ENCENDIDO = loader activo, recibiendo programa por UART
//   LED 5 APAGADO   = CPU corriendo normalmente
// Esto evita que Gowin elimine el uart_loader por optimización.
// ============================================================================

module tang_nano_top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    output wire [5:0] led_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire       pwm_out
);

    wire [7:0] gpio_out_full;
    wire [7:0] gpio_dir_full;
    wire       loader_active;

    microrv8_system #(
        .CLK_FREQ  (27_000_000),
        .BAUD_RATE (115200)
    ) sys (
        .clk           (sys_clk),
        .rst_n         (sys_rst_n),
        .gpio_in       (8'h00),
        .gpio_out      (gpio_out_full),
        .gpio_dir      (gpio_dir_full),
        .uart_rx_pin   (uart_rx),
        .uart_tx_pin   (uart_tx),
        .pwm_pin       (pwm_out),
        .debug_pc      (),
        .debug_state   (),
        .debug_instr   (),
        .loader_active (loader_active)
    );

    // LEDs activos en bajo.
    // Bits 4:0 muestran GPIO normalmente.
    // Bit 5 (LED más alejado del USB) muestra si el loader está recibiendo:
    //   loader_active=1 -> led_n[5]=0 -> LED 5 encendido
    //   loader_active=0 -> led_n[5]=~gpio_out_full[5] -> normal
    assign led_n[4:0] = ~gpio_out_full[4:0];
    assign led_n[5]   = loader_active ? 1'b0 : ~gpio_out_full[5];

endmodule

`default_nettype wire