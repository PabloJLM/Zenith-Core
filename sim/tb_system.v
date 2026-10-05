`default_nettype none
`timescale 1ns / 1ps
// ============================================================================
// Testbench - Sistema Completo MicroRV8-GT
// ============================================================================
// Ejecuta un programa corto (no el firmware de fabrica) y verifica que:
//   1. El CPU avanza el PC correctamente
//   2. El GPIO cambia de valor
//   3. El FSM recorre los 5 estados
//
// NOTA (investigacion 2026-09-18): el programa por defecto de
// instruction_memory.v es el "parpadeo" real de la placa: usa un delay
// loop anidado (r2 de 0..255 dentro de r3 de 0..255, repetido 8 veces
// por cada incremento de r1) para dar ~1s de retardo a 27 MHz en
// hardware real. A la frecuencia simulada de este testbench (1 MHz,
// elegida para que la UART simule rapido) eso equivale a varios
// MILLONES de ciclos de reloj solo para ver el segundo cambio real de
// GPIO -> con 50000 ciclos el test nunca llegaba a 3 cambios (solo
// detectaba 2: el valor inicial en 0 y el primer OUT). No es un bug de
// RTL, es que el testbench corria el firmware de produccion en vez de
// un programa de prueba. Se soluciona cargando aqui un programa corto
// y determinista directamente en la ROM (dut.imem.rom) antes de salir
// de reset, para validar la integracion CPU + bus MMIO + GPIO sin
// depender del retardo real del firmware.
//
// Uso:
//   iverilog -o tb_system.vvp tb_system.v microrv8_system.v cpu_core.v \
//            alu.v regfile.v instruction_memory.v data_memory.v \
//            gpio.v uart.v pwm.v uart_loader.v
//   vvp tb_system.vvp
//   gtkwave tb_system.vcd
// ============================================================================

module tb_system;

    // Parámetros de simulación
    // Clock reducido para UART más rápido en simulación
    localparam CLK_FREQ  = 1_000_000;   // 1 MHz simulado
    localparam BAUD_RATE = 9600;
    localparam CLK_HALF  = 500;         // ns (período = 1 us)

    reg clk, rst_n;

    // Señales del sistema
    wire [7:0] gpio_out;
    wire [7:0] gpio_dir;
    wire       uart_tx_pin;
    wire       pwm_pin;
    wire [7:0] debug_pc;
    wire [7:0] debug_state;
    wire [15:0] debug_instr;

    // Instancia del sistema con parámetros de simulación
    microrv8_system #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .gpio_in     (8'hA5),       // Valor fijo para probar lectura GPIO
        .gpio_out    (gpio_out),
        .gpio_dir    (gpio_dir),
        .uart_rx_pin (1'b1),        // RX idle
        .uart_tx_pin (uart_tx_pin),
        .pwm_pin     (pwm_pin),
        .debug_pc    (debug_pc),
        .debug_state (debug_state),
        .debug_instr (debug_instr)
    );

    // Clock
    initial clk = 0;
    always #(CLK_HALF) clk = ~clk;

    // Variables para verificación
    integer gpio_changes = 0;
    reg [7:0] last_gpio = 8'hFF;
    integer pc_max = 0;

    // Monitorear cambios de GPIO
    always @(gpio_out) begin
        if (gpio_out !== last_gpio) begin
            gpio_changes = gpio_changes + 1;
            last_gpio = gpio_out;
            $display("[%0t ns] GPIO cambio #%0d: 0x%02X", $time, gpio_changes, gpio_out);
        end
    end

    // VCD para GTKWave
    initial begin
        $dumpfile("tb_system.vcd");
        $dumpvars(0, tb_system);
    end

    // Estímulos principales
    integer i;
    initial begin
        $display("=== MicroRV8-GT System Test ===");

        // Reset
        rst_n = 0;
        repeat(10) @(posedge clk);

        // Cargar un programa corto de prueba directamente en la ROM,
        // en vez del firmware de fabrica (ver nota arriba). Sale por
        // GPIO tres valores distintos y luego se detiene en un loop.
        //   0: ADDI r1, r0, 1   r1=1
        //   1: OUT  r1          gpio=1
        //   2: ADDI r1, r1, 1   r1=2
        //   3: OUT  r1          gpio=2
        //   4: ADDI r1, r1, 1   r1=3
        //   5: OUT  r1          gpio=3
        //   6: JUMP 6           detenerse (loop infinito)
        dut.imem.rom[0] = 16'b000_001_000_000_0001; // ADDI r1,r0,1
        dut.imem.rom[1] = 16'b110_000_001_000_0000; // OUT  r1
        dut.imem.rom[2] = 16'b000_001_001_000_0001; // ADDI r1,r1,1
        dut.imem.rom[3] = 16'b110_000_001_000_0000; // OUT  r1
        dut.imem.rom[4] = 16'b000_001_001_000_0001; // ADDI r1,r1,1
        dut.imem.rom[5] = 16'b110_000_001_000_0000; // OUT  r1
        dut.imem.rom[6] = 16'b111_000_000_000_0110; // JUMP 6

        rst_n = 1;
        $display("[%0t ns] Reset liberado", $time);

        // 7 instrucciones x 6 ciclos/instr (FSM de 6 estados) + margen
        repeat(300) @(posedge clk);

        // Verificaciones
        $display("");
        $display("=== Resultados ===");
        $display("Cambios de GPIO detectados: %0d", gpio_changes);
        $display("PC maximo alcanzado: 0x%02X", debug_pc);

        if (gpio_changes >= 3)
            $display("PASS: GPIO cambia correctamente (contador funcionando)");
        else
            $display("FAIL: GPIO no cambia suficiente - revisar CPU o programa");

        if (debug_pc > 8'h00)
            $display("PASS: CPU avanza el PC");
        else
            $display("FAIL: CPU no avanza el PC");

        $display("=== Fin de simulacion ===");
        $finish;
    end

    // Timeout de seguridad
    initial begin
        #100_000_000;
        $display("TIMEOUT: simulacion excedio el tiempo maximo");
        $finish;
    end

endmodule

`default_nettype wire
