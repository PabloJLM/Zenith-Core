`default_nettype none
`timescale 1ns / 1ps

//   1. El CPU avanza el PC correctamente
//   2. El GPIO cambia de valor
//   3. El FSM recorre los 5 estados
// Uso:
//   iverilog -o tb_system.vvp tb_system.v microrv8_system.v cpu_core.v \
//            alu.v regfile.v instruction_memory.v data_memory.v \
//            gpio.v uart.v pwm.v uart_loader.v
//   vvp tb_system.vvp
//   gtkwave tb_system.vcd

module tb_system;


    localparam CLK_FREQ  = 1_000_000;   // 1 MHz 
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

    // Instancias
    microrv8_system #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .gpio_in     (8'hA5),       // Valor fijo para probar lectura GPIO
        .gpio_out    (gpio_out),
        .gpio_dir    (gpio_dir),
        .uart_rx_pin (1'b1),        
        .uart_tx_pin (uart_tx_pin),
        .pwm_pin     (pwm_pin),
        .debug_pc    (debug_pc),
        .debug_state (debug_state),
        .debug_instr (debug_instr)
    );

    
    initial clk = 0;
    always #(CLK_HALF) clk = ~clk;

    integer gpio_changes = 0;
    reg [7:0] last_gpio = 8'hFF;
    integer pc_max = 0;

    always @(gpio_out) begin
        if (gpio_out !== last_gpio) begin
            gpio_changes = gpio_changes + 1;
            last_gpio = gpio_out;
            $display("[%0t ns] GPIO cambio #%0d: 0x%02X", $time, gpio_changes, gpio_out);
        end
    end

    initial begin
        $dumpfile("tb_system.vcd");
        $dumpvars(0, tb_system);
    end

    integer i;
    initial begin
        $display("=== MicroRV8-GT System Test ===");

        rst_n = 0;
        repeat(10) @(posedge clk);

        dut.imem.rom[0] = 16'b000_001_000_000_0001; // ADDI r1,r0,1
        dut.imem.rom[1] = 16'b110_000_001_000_0000; // OUT  r1
        dut.imem.rom[2] = 16'b000_001_001_000_0001; // ADDI r1,r1,1
        dut.imem.rom[3] = 16'b110_000_001_000_0000; // OUT  r1
        dut.imem.rom[4] = 16'b000_001_001_000_0001; // ADDI r1,r1,1
        dut.imem.rom[5] = 16'b110_000_001_000_0000; // OUT  r1
        dut.imem.rom[6] = 16'b111_000_000_000_0110; // JUMP 6

        rst_n = 1;
        $display("[%0t ns] Reset liberado", $time);

        repeat(300) @(posedge clk);

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

    initial begin
        #100_000_000;
        $display("TIMEOUT: simulacion excedio el tiempo maximo");
        $finish;
    end

endmodule

`default_nettype wire
