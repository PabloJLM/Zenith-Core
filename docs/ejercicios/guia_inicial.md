# Guía desde cero — Verilog, cocotb y simulación

Todo lo que necesitas para escribir módulos en Verilog, probarlos con cocotb, y correr simulaciones desde la GUI o la terminal.

---

## Parte 1 — Qué es Verilog y para qué sirve

Verilog es un lenguaje de descripción de hardware para diseñar y simular componentes electrónicos como compuertas, módulos y procesadores, indicando cómo se conectan y comportan sus partes internas.

### Dos tipos de lógica

**Combinacional:** la salida depende solo de las entradas actuales. Sin memoria, sin clock. Ejemplos: suma, comparador, mux.

**Secuencial:** la salida depende de las entradas actuales y del estado anterior. Necesita clock. Ejemplos: contador, registro, FSM.

---

## Parte 2 — Estructura de un módulo Verilog

```verilog
module nombre_del_modulo (
    input  wire a,
    input  wire b,
    output wire y
);
    assign y = a & b;
endmodule
```

### Tipos de señal

```verilog
wire        // cable, valor continuo
reg         // registro, guarda valor entre flancos

wire [7:0]  dato;    // 8 bits
reg  [3:0]  cuenta;  // 4 bits

dato[0]     // bit menos significativo
dato[7]     // bit más significativo
dato[3:1]   // slice de bits
```

### Puertos

```verilog
module ejemplo (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  dato_in,
    output wire [7:0]  dato_out,   // viene de assign
    output reg  [7:0]  resultado   // viene de always
);
```

---

## Parte 3 — Lógica combinacional

### assign

```verilog
assign y = a & b;
assign y = a | b;
assign y = a ^ b;
assign y = ~a;
assign suma = a + b;
assign mayor = (a > b);
assign bus = {a, b, c};
assign {carry, suma} = a + b;
```

### always @(*) con case

```verilog
reg [7:0] resultado;

always @(*) begin
    case (opcode)
        3'b000: resultado = a + b;
        3'b001: resultado = a - b;
        3'b010: resultado = a & b;
        default: resultado = 8'h00;   // siempre poner default
    endcase
end
```

---

## Parte 4 — Lógica secuencial

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        registro <= 8'h00;
    end else begin
        registro <= registro + 1;
    end
end
```

Usar siempre `<=` (non-blocking) dentro de `always @(posedge clk)`.

### Contador con enable

```verilog
`default_nettype none
module contador (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    output reg  [7:0] count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         count <= 8'h00;
        else if (enable)    count <= count + 8'h01;
    end
endmodule
`default_nettype wire
```

---

## Parte 5 — Máquinas de estado (FSM)

```verilog
`default_nettype none
module fsm_ejemplo (
    input  wire clk,
    input  wire rst_n,
    input  wire señal_entrada,
    output reg  señal_salida
);
    localparam S_IDLE    = 2'd0;
    localparam S_PROCESO = 2'd1;
    localparam S_ESPERA  = 2'd2;
    localparam S_LISTO   = 2'd3;

    reg [1:0] estado;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            estado       <= S_IDLE;
            señal_salida <= 1'b0;
        end else begin
            señal_salida <= 1'b0;

            case (estado)
                S_IDLE:    if (señal_entrada) estado <= S_PROCESO;
                S_PROCESO: estado <= S_ESPERA;
                S_ESPERA:  if (!señal_entrada) estado <= S_LISTO;
                S_LISTO: begin
                    señal_salida <= 1'b1;
                    estado       <= S_IDLE;
                end
                default: estado <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
```

Convenciones del proyecto: resets activos en bajo (`rst_n`), estados con `localparam`, siempre `default` en el case de estados.

---

## Parte 6 — Instanciar módulos

```verilog
contador mi_contador (
    .clk    (clk),
    .rst_n  (rst_n),
    .enable (btn_presionado),
    .count  (valor_actual)
);
```

Siempre usar conexión por nombre (`.puerto(señal)`), nunca por posición.

---

## Parte 7 — Errores comunes en Verilog

**Multiple drivers:** dos `always` escribiendo el mismo registro. Solución: consolidar en un solo `always` con lógica interna.

**Latch no intencional:** falta `default` en `always @(*)`. Siempre cubrir todos los casos.

**Mezclar `=` y `<=`:** en bloques secuenciales usar solo `<=`.

---

## Parte 8 — Qué es cocotb

cocotb permite escribir tests del hardware en Python. El simulador sigue siendo iverilog; cocotb agrega un puente VPI que le da control al código Python sobre las señales.

```
DUT.v  +  test.py  →  iverilog → vvp (con hook Python) → resultados PASS/FAIL
```

---

## Parte 9 — Estructura de un test cocotb

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def nombre_descriptivo(dut):
    pass
```

### Señales

```python
dut.clk.value   = 0
dut.dato.value  = 0xAB

valor   = dut.resultado.value.integer
bit     = int(dut.flag.value)
```

### Esperar tiempo

```python
await Timer(10, units="ns")
await RisingEdge(dut.clk)
for _ in range(5):
    await RisingEdge(dut.clk)
```

### Clock y reset

```python
cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

async def hacer_reset(dut):
    dut.rst_n.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
```

### Verificar

```python
resultado = dut.salida.value.integer
assert resultado == 42, f"Esperado 42, obtenido {resultado}"
```

---

## Parte 10 — Tu primer test completo

### contador.v

```verilog
`default_nettype none
module contador (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    output reg  [7:0] count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      count <= 8'h00;
        else if (enable) count <= count + 8'h01;
    end
endmodule
`default_nettype wire
```

### test_contador.py

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset(dut):
    dut.rst_n.value  = 0
    dut.enable.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value  = 1
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_cuenta_basica(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    dut.enable.value = 1

    for esperado in range(1, 6):
        await RisingEdge(dut.clk)
        obtenido = dut.count.value.integer
        assert obtenido == esperado, f"Ciclo {esperado}: obtenido {obtenido}"

@cocotb.test()
async def test_overflow(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    dut.enable.value = 1

    for _ in range(255):
        await RisingEdge(dut.clk)
    assert dut.count.value.integer == 255

    await RisingEdge(dut.clk)
    assert dut.count.value.integer == 0, "Overflow: debe volver a 0"
```

---

## Parte 11 — Correr desde sim_gui.py

1. Abrir `sim_gui.py`
2. Seleccionar el directorio del proyecto
3. Cambiar a modo **cocotb**
4. Seleccionar el archivo `.py` del test
5. Escribir el **Top Module** (nombre exacto del módulo Verilog)
6. Clic en **Todo**

Salida esperada:

```
** TESTS=4 PASS=4 FAIL=0 SKIP=0 **
```

Si hay un fallo el log muestra el archivo y la línea exacta del `assert`.

---

## Parte 12 — Flujo de simulación completo

### Con iverilog directo (Testbench Verilog)

```bash
iverilog -g2012 -o output.vvp \
    alu.v regfile.v cpu_core.v \
    instruction_memory.v data_memory.v \
    gpio.v uart.v pwm.v uart_loader.v \
    microrv8_system.v \
    sim/tb_system.v

vvp output.vvp
gtkwave tb_system.vcd
```

Para compilar con un programa personalizado:

```bash
python3 tools/assembler.py fibonacci.asm -o fibonacci.hex

iverilog -g2012 -DPROGRAM_HEX='"fibonacci.hex"' \
    -o output.vvp \
    alu.v regfile.v cpu_core.v instruction_memory.v data_memory.v \
    gpio.v uart.v pwm.v uart_loader.v microrv8_system.v \
    sim/tb_system.v

vvp output.vvp
```

### Con sim_gui.py (Modo Verilog)

1. Seleccionar modo **Testbench Verilog**
2. Seleccionar `sim/tb_system.v` o `sim/tb_cpu.v`
3. Clic **Compilar** → **Simular** → **GTKWave**

### Señales útiles para GTKWave

```
tb_system.dut.cpu.state[2:0]      estado FSM (0=FETCH 1=WAIT 2=DEC 3=EXEC 4=MEM 5=WB)
tb_system.dut.cpu.pc[8:0]         program counter
tb_system.dut.cpu.ir[15:0]        instruction register
tb_system.dut.cpu.rf.regs[1][7:0] registro r1
tb_system.dut.gpio_out[7:0]       salida GPIO
```

Clic derecho en `state[2:0]` → Data Format → Decimal para ver el número de estado.

### Tiempos de referencia

Cada instrucción toma 6 ciclos. A 27 MHz: **4.5 millones de instrucciones por segundo**.

En simulación `tb_system.v` usa `CLK_FREQ = 1_000_000` para que el UART no requiera miles de ciclos.

---

## Parte 13 — Patrones avanzados de test

### Monitor de señal

```python
historial = []

async def monitor(dut, n_ciclos):
    prev = -1
    for _ in range(n_ciclos):
        await RisingEdge(dut.clk)
        actual = dut.salida.value.integer
        if actual != prev:
            historial.append(actual)
            prev = actual

@cocotb.test()
async def test_con_monitor(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)
    cocotb.start_soon(monitor(dut, 100))
    dut.enable.value = 1
    for _ in range(100):
        await RisingEdge(dut.clk)
    assert historial[0] == 1
```

### Test con valores aleatorios

```python
import random

@cocotb.test()
async def test_aleatorio(dut):
    for _ in range(50):
        a = random.randint(0, 255)
        b = random.randint(0, 255)
        dut.a.value = a
        dut.b.value = b
        dut.op.value = 0b000
        await Timer(1, units="ns")
        esperado = (a + b) & 0xFF
        assert dut.result.value.integer == esperado, f"{a}+{b}: {dut.result.value.integer}"
```

### Esperar condición con timeout

```python
async def esperar_hasta(dut, señal, valor, timeout=1000):
    for ciclo in range(timeout):
        if int(getattr(dut, señal).value) == valor:
            return ciclo
        await RisingEdge(dut.clk)
    raise TimeoutError(f"'{señal}' no llegó a {valor} en {timeout} ciclos")
```
