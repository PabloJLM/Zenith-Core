# Documentación Técnica de Módulos

---

## Índice

1. `alu.v` — Unidad Aritmético-Lógica
2. `regfile.v` — Banco de Registros
3. `cpu_core.v` — Núcleo del CPU
4. `instruction_memory.v` — Memoria de Instrucciones
5. `data_memory.v` — Memoria de Datos y Decodificador MMIO
6. `gpio.v` — GPIO 8 bits
7. `uart.v` — UART TX + RX + Wrapper MMIO
8. `pwm.v` — PWM 8 bits
9. `uart_loader.v` — Cargador de Programas vía UART
10. `microrv8_system.v` — Sistema Completo (Top Level)
11. `tang_nano_top.v` — Wrapper Tang Nano 9K
12. `tang_nano_9k.cst` — Restricciones de Pines
13. `assembler.py` — Ensamblador de Dos Pasadas
14. `sim_gui.py` — GUI de Simulación
15. `uart_flash.py` — Herramienta de Carga vía UART

---

## 1. `alu.v` — Unidad Aritmético-Lógica

### Función

Realiza operaciones aritméticas y lógicas sobre dos operandos de 8 bits. Es un bloque puramente combinacional: no tiene registros, produce el resultado en el mismo ciclo en que recibe las entradas.

### Interfaz

```verilog
module alu_8bit (
    input  wire [7:0] a,           // Operando A (viene de rs1 del regfile)
    input  wire [7:0] b,           // Operando B (viene de rs2 o inmediato)
    input  wire [2:0] op,          // Código de operación (funct3)
    output reg  [7:0] result,      // Resultado de 8 bits
    output wire       zero,        // 1 si result == 0
    output wire       carry,       // 1 si hubo carry (desbordamiento sin signo)
    output wire       negative     // 1 si bit 7 del resultado es 1
);
```

### Tabla de operaciones

```
op [2:0]  Operación  Descripción
────────  ─────────  ─────────────────────────────
000       ADD        result = a + b
001       SUB        result = a - b
010       AND        result = a & b
011       OR         result = a | b
100       XOR        result = a ^ b
101       SLL        result = a << b[2:0]
110       SRL        result = a >> b[2:0]
111       SLT        result = (a < b) ? 1 : 0 (sin signo)
```

### Implementación del carry

Se usa un registro interno de 9 bits para capturar el bit de acarreo:

```verilog
reg [8:0] result_ext;
// Para ADD: result_ext = {1'b0, a} + {1'b0, b}
// carry = result_ext[8]
```

### Notas de diseño

- `SLT` usa comparación sin signo. Para comparación con signo habría que extender la ALU.
- El flag `negative` es simplemente `result[7]` (bit de signo en representación en complemento a 2).
- Los flags `carry` y `negative` están disponibles en el CPU pero actualmente solo `zero` es usado por `BEQ`.

---

## 2. `regfile.v` — Banco de Registros

### Función

Almacena los 8 registros de propósito general del CPU (r0-r7). Proporciona dos puertos de lectura simultánea (combinacional) y un puerto de escritura síncrona.

### Interfaz

```verilog
module regfile (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] rs1_addr,   // Dirección de lectura A
    output wire [7:0] rs1_data,   // Dato leído del puerto A
    input  wire [2:0] rs2_addr,   // Dirección de lectura B
    output wire [7:0] rs2_data,   // Dato leído del puerto B
    input  wire [2:0] rd_addr,    // Dirección de escritura
    input  wire [7:0] rd_data,    // Dato a escribir
    input  wire       rd_we       // Write enable (activo alto)
);
```

### Comportamiento

**Lectura:** combinacional (sin latencia de clock).
```verilog
assign rs1_data = (rs1_addr == 3'd0) ? 8'h00 : regs[rs1_addr];
assign rs2_data = (rs2_addr == 3'd0) ? 8'h00 : regs[rs2_addr];
```

**Escritura:** síncrona, en flanco positivo del clock.
```verilog
if (rd_we && rd_addr != 3'd0)
    regs[rd_addr] <= rd_data;
```

**r0 es hardwired zero:** leer r0 siempre devuelve 0. Escribir a r0 no tiene efecto. Esto replica el comportamiento del ISA RISC-V.

### Reset

En `negedge rst_n`, todos los registros se ponen a cero.

---

## 3. `cpu_core.v` — Núcleo del CPU

### Función

Implementa el ciclo de fetch-decode-execute de la ISA MicroRV8-GT. Conecta el ALU, el register file, y controla las interfaces con la memoria de instrucciones y datos.

### Interfaz

```verilog
module cpu_core (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction memory (combinacional)
    output wire [8:0]  pc_out,         // PC actual → instruction_memory
    input  wire [15:0] instruction_in, // Instrucción desde instruction_memory

    // Data memory
    output reg  [7:0]  mem_addr,       // Dirección de acceso a datos
    output reg  [7:0]  mem_wdata,      // Dato a escribir (STORE)
    input  wire [7:0]  mem_rdata,      // Dato leído (LOAD)
    output reg         mem_we,         // Write enable (1 ciclo)
    output reg         mem_re,         // Read enable (1 ciclo)

    // GPIO directo (instrucción OUT)
    output reg  [7:0]  gpio_out,       // Salida directa al OR con gpio_8bit

    // Debug
    output wire [7:0]  debug_pc,
    output wire [7:0]  debug_state,
    output wire [15:0] debug_instr
);
```

### FSM de 5 estados

```
Estado         Código  Duración  Descripción
─────────────  ──────  ────────  ──────────────────────────────────────────
S_FETCH        3'd0    1 ciclo   IR ← instruction_in (combinacional, ya válido)
S_DECODE       3'd1    1 ciclo   Lee registros, configura ALU (alu_a, alu_b, alu_op)
S_EXECUTE      3'd2    1 ciclo   ALU opera, captura resultado en alu_res y alu_z
S_MEMORY       3'd3    1 ciclo   Accede a datos o actualiza GPIO
S_WRITEBACK    3'd4    1 ciclo   Escribe resultado, actualiza PC
```

### Decodificación de campos del IR

```verilog
wire [2:0] opcode = ir[15:13];
wire [2:0] f_rd   = ir[12:10];   // rd o rs1 (BRANCH/STORE)
wire [2:0] f_rs1  = ir[9:7];     // rs1
wire [2:0] f_rs2  = ir[6:4];     // rs2 (R-type) o funct3 (I-type)
wire [2:0] f_fn3r = ir[3:1];     // funct3 (R-type)
wire [3:0] f_imm4 = ir[3:0];     // inmediato 4 bits
wire [7:0] imm_se = {{4{f_imm4[3]}}, f_imm4};  // extendido a 8 bits con signo
```

### Mux de puertos del register file

Según el tipo de instrucción, los puertos de lectura A y B del register file se redirigen:

```
Instrucción  ra_addr (puerto A)  rb_addr (puerto B)
───────────  ──────────────────  ──────────────────
Tipo I/R/L   f_rs1               f_rs2
STORE        f_rs1 (base)        f_rd  (dato a guardar)
BEQ          f_rd  (rs1)         f_rs1 (rs2)
```

### Comportamiento por opcode en cada estado

**S_DECODE:**

| Opcode | alu_a     | alu_b   | alu_op  | Observación                 |
|--------|-----------|---------|---------|----------------------------|
| 000    | ra_data   | imm_se  | f_rs2   | funct3 en campo rs2         |
| 001    | ra_data   | rb_data | f_fn3r  | funct3 en bits [3:1]        |
| 010    | ra_data   | imm_se  | ADD     | calcular dirección LOAD     |
| 011    | ra_data   | imm_se  | ADD     | calcular dirección STORE    |
| 100    | ra_data   | rb_data | SUB     | comparar para BEQ           |
| 110    | ra_data   | 0       | ADD     | guardar rs1 para OUT        |

**S_MEMORY:**

| Opcode | Acción                                      |
|--------|---------------------------------------------|
| 010    | mem_addr ← alu_res; mem_re ← 1             |
| 011    | mem_addr ← alu_res; mem_wdata ← store_dat; mem_we ← 1 |
| 110    | gpio_out ← alu_a (valor de rs1)             |

**S_WRITEBACK:**

| Opcode | rd_wdata      | PC siguiente                        |
|--------|---------------|-------------------------------------|
| 000    | alu_res       | pc + 1                              |
| 001    | alu_res       | pc + 1                              |
| 010    | mem_rdata     | pc + 1                              |
| 011    | —             | pc + 1                              |
| 100    | —             | pc + imm (si alu_z) / pc + 1        |
| 101    | pc_lat[7:0]+1 | ir[8:0] (9 bits de target)          |
| 110    | —             | pc + 1                              |
| 111    | —             | ir[8:0] (9 bits de target)          |

### Restricciones conocidas del ISA actual

- `BEQ` tiene rango de offset de 4 bits: máximo ±8 instrucciones relativas.
- `JUMP` y `JAL` tienen destino absoluto de 9 bits (512 posiciones). No existe JALR (retorno dinámico).
- No hay manejo de interrupciones en el CPU (el timer IRQ existe pero no está conectado).
- Un solo tipo de branch: `BEQ`. No existe `BNE`, `BLT`, etc.

---

## 4. `instruction_memory.v` — Memoria de Instrucciones

### Función

ROM/RAM de 512 palabras × 16 bits que almacena el programa del CPU. Tiene dos puertos independientes: lectura combinacional para el CPU y escritura síncrona para el `uart_loader`.

### Interfaz

```verilog
module instruction_memory (
    input  wire        clk,
    input  wire [8:0]  addr,       // Dirección CPU (combinacional)
    output wire [15:0] data_out,   // Instrucción al CPU
    input  wire [8:0]  wr_addr,    // Dirección escritura loader
    input  wire [15:0] wr_data,    // Dato a escribir
    input  wire        wr_en       // Habilitador de escritura
);
```

### Lectura combinacional

```verilog
assign data_out = rom[addr];
```

Esto permite que el CPU reciba la instrucción en el mismo ciclo en que presenta el PC (sin latencia de un ciclo de clock). En síntesis, Gowin puede inferir esto como BRAM con output registrado si el timing lo permite; de lo contrario usa LUTs distribuidas.

### Escritura síncrona (uart_loader)

```verilog
always @(posedge clk)
    if (wr_en) rom[wr_addr] <= wr_data;
```

Durante la carga, el CPU está en reset (señal `loader_loading` en el sistema), así que no hay conflicto de lectura/escritura simultánea.

### Carga del programa

**Durante síntesis (programa fijo):** editar el bloque `initial` en el archivo con las instrucciones en binario o usar `$readmemh`.

**En simulación con programa externo:**
```bash
iverilog -g2012 -DPROGRAM_HEX='"mi_programa.hex"' -o sim.vvp ...
```

**En caliente via UART:** usar `uart_flash.py` con el `.bin` generado por el assembler.

### Tamaño y uso de BRAM

512 palabras × 16 bits = 8,192 bits = 8 Kbits → cabe exactamente en un bloque BRAM de 9K de la Tang Nano 9K.

---

## 5. `data_memory.v` — Memoria de Datos y Decodificador MMIO

### Función

Implementa la memoria de datos del CPU y el decodificador que separa accesos a RAM de accesos a periféricos MMIO. Las direcciones 0x00-0x7F van a RAM física; las 0x80-0xFF se redirigen al bus MMIO.

### Interfaz

```verilog
module data_memory (
    input  wire        clk, rst_n,
    input  wire [7:0]  addr,
    input  wire [7:0]  data_in,
    input  wire        we, re,
    output reg  [7:0]  data_out,

    // Bus MMIO hacia periféricos
    output reg  [7:0]  mmio_addr,
    output reg  [7:0]  mmio_data_wr,
    input  wire [7:0]  mmio_data_rd,
    output reg         mmio_we,
    output reg         mmio_re
);
```

### Decodificación

```verilog
wire is_mmio = addr[7];   // bit 7 = 1 → MMIO (0x80-0xFF)
```

### Comportamiento de acceso

**Escritura (`we = 1`):**
- Si `!is_mmio`: `ram[addr[6:0]] ← data_in`
- Si `is_mmio`: `mmio_addr ← addr`, `mmio_data_wr ← data_in`, `mmio_we ← 1`

**Lectura (`re = 1`):**
- Si `!is_mmio`: `data_out ← ram[addr[6:0]]`
- Si `is_mmio`: `mmio_addr ← addr`, `mmio_re ← 1`, `data_out ← mmio_data_rd`

### Nota sobre latencia MMIO

La lectura MMIO tiene un ciclo de latencia adicional porque `mmio_data_rd` viene del periférico en el ciclo siguiente al que se presenta `mmio_re`. El CPU actualmente no tiene lógica adicional para esperar este ciclo extra — para LOAD desde MMIO el resultado puede llegar un ciclo tarde. Para las instrucciones de escritura (STORE) no hay problema porque el periférico registra el dato en el mismo flanco.

---

## 6. `gpio.v` — GPIO 8 bits

### Función

Módulo de entrada/salida de propósito general. Permite configurar cada pin como entrada o salida de forma independiente mediante el registro `GPIO_DIR`.

### Interfaz

```verilog
module gpio_8bit (
    input  wire        clk, rst_n,
    input  wire [7:0]  mmio_addr,
    input  wire [7:0]  mmio_data_in,
    output reg  [7:0]  mmio_data_out,
    input  wire        mmio_we, mmio_re,
    input  wire [7:0]  gpio_in,    // pines físicos de entrada
    output reg  [7:0]  gpio_out,   // pines físicos de salida
    output reg  [7:0]  gpio_dir    // control de dirección
);
```

### Mapa de registros

```
Dirección  Acceso  Registro   Descripción
─────────  ──────  ─────────  ────────────────────────────────────────
0x80       W       GPIO_OUT   Escribe valor en pines configurados como salida
0x81       R       GPIO_IN    Lee el estado actual de los pines físicos
0x82       W       GPIO_DIR   0=input, 1=output por pin (bit a bit)
```

### Comportamiento

`gpio_out` se actualiza sincrónicamente con `posedge clk` cuando se escribe a 0x80.
`gpio_in` se lee directamente desde los pines físicos (lectura combinacional).
`gpio_dir` controla los buffers tristate en el top level (no implementado en el módulo, requiere lógica en el top level de la FPGA).

### En el sistema completo

El `gpio_out` del módulo se hace OR con el `cpu_gpio_direct` (instrucción OUT) en `microrv8_system.v`:

```verilog
assign gpio_out = gpio_out_mmio | cpu_gpio_direct;
```

Esto permite usar tanto `STORE r, 0x80` como la instrucción `OUT r` para controlar el GPIO.

---

## 7. `uart.v` — UART TX + RX + Wrapper MMIO

### Módulos contenidos

El archivo `uart.v` contiene tres módulos: `uart_tx`, `uart_rx`, y `uart_mmio`.

### `uart_tx` — Transmisor

Implementa el protocolo UART 8N1 (8 bits de datos, sin paridad, 1 stop bit).

```verilog
module uart_tx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk, rst_n,
    input  wire [7:0] data_in,
    input  wire       tx_start,    // pulso de 1 ciclo para iniciar
    output reg        tx_busy,     // 1 mientras transmite
    output reg        tx           // pin serial (idle = 1)
);
```

**Divisor de baud rate:**
```
BAUD_DIV = CLK_FREQ / BAUD_RATE = 27,000,000 / 115,200 = 234 ciclos/bit
```

**Estados de la FSM:**
```
ST_IDLE  → ST_START → ST_DATA (8 bits, LSB primero) → ST_STOP → ST_IDLE
```

### `uart_rx` — Receptor

Detecta el flanco de bajada del start bit, muestrea cada bit en el centro del período de baud rate usando un divisor de medio período (`HALF_DIV`).

```verilog
module uart_rx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk, rst_n,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid   // pulso 1 ciclo cuando byte completo
);
```

El módulo incluye un sincronizador de dos flip-flops en la entrada `rx` para evitar metaestabilidad.

### `uart_mmio` — Wrapper de memoria mapeada

```
Dirección  Acceso  Descripción
─────────  ──────  ──────────────────────────────────────────
0x83       W       UART_TX: escribir aquí inicia la transmisión
0x84       R       UART_STAT: bit0 = tx_busy
```

Si se escribe a 0x83 mientras `tx_busy = 1`, la escritura se ignora. El programa debe verificar `UART_STAT` antes de enviar.

### Configuración para Tang Nano 9K

```
CLK_FREQ  = 27,000,000
BAUD_RATE = 115,200
BAUD_DIV  = 234 ciclos por bit
HALF_DIV  = 117 ciclos (para centrar el muestreo)
```

Para cambiar el baud rate, modificar el parámetro `BAUD_RATE` en la instancia de `microrv8_system`.

---

## 8. `pwm.v` — PWM 8 bits

### Función

Genera una señal PWM (Pulse Width Modulation) con resolución de 8 bits. Se usa para controlar brillo de LEDs, velocidad de motores, o cualquier actuador analógico.

### Interfaz

```verilog
module pwm_8bit (
    input  wire       clk, rst_n,
    input  wire [7:0] mmio_addr,
    input  wire [7:0] mmio_data_in,
    output reg  [7:0] mmio_data_out,
    input  wire       mmio_we, mmio_re,
    output reg        pwm_out
);
```

### Mapa de registros

```
Dirección  Acceso  Registro    Rango    Descripción
─────────  ──────  ──────────  ───────  ──────────────────────────────────
0x85       R/W     PWM_DUTY    0-255    Duty cycle: 0=0%, 255=100%
0x86       R/W     PWM_CTRL    0-3      bit0=enable, bit1=invert polaridad
0x87       R/W     PWM_PRE     1-255    Prescaler de frecuencia
```

### Cálculo de frecuencia PWM

```
f_PWM = CLK_FREQ / (PRESCALER × 256)

Ejemplos a 27 MHz:
  PRE=1   → f_PWM = 105,468 Hz  (~105 kHz)
  PRE=105 → f_PWM = 1,004 Hz    (~1 kHz)
  PRE=27  → f_PWM = 3,906 Hz    (~4 kHz)
```

### Implementación

Usa un contador de prescaler de 8 bits y un contador PWM de 8 bits:

```
Cada (PRESCALER) ciclos de clock, el contador PWM incrementa.
Cuando pwm_cnt < duty → salida alta
Cuando pwm_cnt >= duty → salida baja
El contador PWM wraps automáticamente a 0 después de 255.
```

---

## 9. `uart_loader.v` — Cargador de Programas vía UART

### Función

Permite cargar un nuevo programa en la `instruction_memory` desde una PC vía UART, sin necesidad de resintetizar la FPGA. Mientras carga, mantiene el CPU en reset.

### Interfaz

```verilog
module uart_loader #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire        clk, rst_n,
    input  wire        rx,
    output reg  [8:0]  wr_addr,    // dirección en instruction_memory
    output reg  [15:0] wr_data,    // instrucción a escribir
    output reg         wr_en,      // habilitador de escritura (1 ciclo)
    output reg         loading,    // 1 = cargando, CPU en reset
    output reg         load_done   // pulso al terminar
);
```

### Protocolo de carga

```
Byte 0: 0xAA         (sync byte 1)
Byte 1: 0x55         (sync byte 2)
Byte 2: count[8]     (bit alto del conteo de instrucciones, típicamente 0)
Byte 3: count[7:0]   (cantidad de instrucciones a cargar)
Byte 4+5: instr 0    (big-endian: byte alto, byte bajo)
Byte 6+7: instr 1
...
Byte (4+2*N-2)+(4+2*N-1): instr N-1
```

El header `0xAA 0x55` puede enviarse en cualquier momento. Si llegan bytes incorrectos, el loader regresa al estado `ST_SYNC1` y espera el próximo header válido.

### Integración en el sistema

```verilog
// En microrv8_system.v:
wire cpu_rst_n = rst_n & ~loader_loading;
// El CPU está en reset mientras loading=1
```

El loader usa `uart_rx` del archivo `uart.v`.

### Uso con `uart_flash.py`

```bash
# Ensamblar con flag --binary para generar archivo con header de protocolo:
python3 assembler.py programa.asm --binary -o programa.bin

# Cargar a la FPGA:
python3 uart_flash.py programa.bin --port COM3
```

---

## 10. `microrv8_system.v` — Sistema Completo

### Función

Top level del sistema MicroRV8-GT. Instancia todos los módulos y los conecta mediante los buses internos. Define el mapa de memoria MMIO.

### Parámetros

```verilog
module microrv8_system #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)
```

Estos parámetros se propagan a `uart_tx`, `uart_rx`, `uart_mmio`, `uart_loader`, y `pwm_8bit`.

### Interfaz externa

```verilog
(
    input  wire        clk, rst_n,
    input  wire [7:0]  gpio_in,
    output wire [7:0]  gpio_out, gpio_dir,
    input  wire        uart_rx_pin,
    output wire        uart_tx_pin,
    output wire        pwm_pin,
    output wire [7:0]  debug_pc, debug_state,
    output wire [15:0] debug_instr
)
```

### Bus MMIO interno

El módulo `data_memory` genera señales MMIO:

```
mmio_addr    [7:0]   Dirección del acceso
mmio_data_wr [7:0]   Dato hacia el periférico (escritura)
mmio_data_rd [7:0]   Dato desde el periférico (lectura, muxeado)
mmio_we              Write enable al periférico
mmio_re              Read enable al periférico
```

El mux de lectura selecciona qué periférico responde:

```verilog
always @(*) begin
    case (mmio_addr)
        8'h80, 8'h81, 8'h82: mmio_data_rd = gpio_mmio_rd;
        8'h83, 8'h84:        mmio_data_rd = uart_mmio_rd;
        8'h85, 8'h86, 8'h87: mmio_data_rd = pwm_mmio_rd;
        default:             mmio_data_rd = 8'h00;
    endcase
end
```

### Reset del CPU

```verilog
wire loader_loading;
wire cpu_rst_n = rst_n & ~loader_loading;
```

El CPU entra en reset en dos casos: cuando `rst_n = 0` (botón S1) o cuando `loader_loading = 1` (carga de programa en progreso).

### GPIO combinado

```verilog
assign gpio_out = gpio_out_mmio | cpu_gpio_direct;
```

`gpio_out_mmio` viene del módulo `gpio_8bit` (instrucción STORE 0x80).
`cpu_gpio_direct` viene del CPU directamente (instrucción OUT).
Ambas fuentes son OR porque nunca pueden activarse simultáneamente.

---

## 11. `tang_nano_top.v` — Wrapper Tang Nano 9K

### Función

Adapta `microrv8_system` a los pines físicos de la Tang Nano 9K. Configura el clock a 27 MHz y maneja la inversión de los LEDs (activos en bajo en esta placa).

### Instancia principal

```verilog
microrv8_system #(
    .CLK_FREQ  (27_000_000),
    .BAUD_RATE (115200)
) sys (...)
```

### Manejo de LEDs

Los LEDs de la Tang Nano 9K son activos en bajo:

```verilog
assign led_n = ~gpio_out_full[5:0];
```

Bit 0 de `gpio_out` → LED 0 (más cercano al USB).
Bit 5 de `gpio_out` → LED 5 (más alejado).

### Señales de debug

Los puertos `debug_pc`, `debug_state`, y `debug_instr` del sistema están conectados pero no se llevan a pines externos en este wrapper. Para debug en FPGA usar Gowin Analyzer Oscilloscope (incluido en Gowin EDA) o conectar a pines libres.

---

## 12. `tang_nano_9k.cst` — Restricciones de Pines

### Función

Archivo de constraints de Gowin que asigna señales del RTL a pines físicos del chip GW1NR-9C.

### Sintaxis

```
IO_LOC "nombre_señal" número_pin;
IO_PORT "nombre_señal" PULL_MODE=XXX DRIVE=X;
```

### Opciones de IO_PORT

```
PULL_MODE:
  NONE    — sin resistencia de pull (para señales driven externamente)
  UP      — pull-up interno (~100 kΩ)
  DOWN    — pull-down interno
  KEEPER  — mantiene el último valor cuando la señal es flotante

DRIVE (corriente de salida):
  4, 8, 12, 16  (mA)
  Usar 8 mA para LEDs y UART. Máximo 16 mA por pin.
```

### Modificar pines

Si se conectan periféricos externos a pines diferentes, editar el `.cst` directamente o usar `Tools → FloorPlanner → IO Constraint` en Gowin EDA.

---

## 13. `assembler.py` — Ensamblador de Dos Pasadas

### Función

Convierte código assembly MicroRV8-GT a código máquina en formato `.hex` (para `$readmemh` en Verilog) o `.bin` (para carga vía UART con el protocolo del `uart_loader`).

### Uso desde línea de comandos

```bash
# Compilar a .hex (formato Verilog $readmemh)
python3 assembler.py programa.asm -o programa.hex

# Compilar a .hex y .bin con listado suprimido
python3 assembler.py programa.asm -o programa.hex --binary --no-listing

# El listado se muestra por defecto
python3 assembler.py counter.asm
```

### Estructura interna

**Primera pasada (`first_pass`):**
- Recorre todas las líneas
- Elimina comentarios (`;`) y espacios en blanco
- Detecta labels (terminan en `:`) y registra su dirección
- Identifica instrucciones y las almacena con su dirección

**Segunda pasada (`second_pass`):**
- Procesa cada instrucción con su opcode y operandos
- Resuelve referencias a labels usando el diccionario de la primera pasada
- Para BEQ calcula el offset relativo: `target - (addr + 1)`
- Genera la palabra de 16 bits y la agrega a `self.code`

### Clase `Assembler`

```python
asm = Assembler()
asm.assemble(source_code_string)  # ejecuta ambas pasadas
asm.write_hex("salida.hex")       # formato $readmemh
asm.write_bin("salida.bin")       # con header uart_loader
asm.listing()                     # imprime tabla formateada
```

### Formato del archivo `.hex`

```
# Una instrucción de 16 bits por línea, en hexadecimal
0481
0c0f
0481
c080
...
```

### Formato del archivo `.bin`

```
Byte 0: 0xAA                    (sync)
Byte 1: 0x55                    (sync)
Byte 2: (count >> 8) & 0x01     (bit alto del conteo)
Byte 3: count & 0xFF            (byte bajo del conteo)
Bytes 4+: instrucciones en big-endian (2 bytes por instrucción)
```

### Límites del ensamblador

- Inmediatos: `-8` a `15` (4 bits con signo)
- Destinos JUMP/JAL: `0` a `511` (9 bits)
- Offset BEQ: `-8` a `7` (relativo a la instrucción siguiente)
- Programa máximo: 512 instrucciones

---

## 14. `sim_gui.py` — GUI de Simulación

### Función

Interfaz gráfica Tkinter para compilar y simular el proyecto con Icarus Verilog y visualizar resultados en GTKWave. Diseñada para facilitar el flujo de desarrollo sin recordar comandos de terminal.

### Uso

```bash
python3 sim_gui.py
```

### Funcionalidades

**Detección automática de herramientas:** verifica si `iverilog`, `vvp`, y `gtkwave` están en PATH al iniciar. Muestra el estado con color (verde/rojo/naranja).

**Archivos del proyecto:** la GUI busca automáticamente todos los archivos `.v` de la lista `PROJECT_FILES` en el directorio seleccionado. No es necesario agregarlos manualmente uno por uno.

**Botón "Todo en uno":** ejecuta compilar → simular → abrir GTKWave en secuencia.

**Log integrado:** muestra stdout y stderr de `iverilog` y `vvp` en un panel de texto desplazable.

### Configurar GTKWave en Windows

Si GTKWave no está en PATH, editar la variable al inicio del archivo:

```python
GTKWAVE_PATH = r"C:\gtkwave64\bin\gtkwave.exe"
```

### Personalizar archivos del proyecto

La variable `PROJECT_FILES` en el código define el orden de compilación:

```python
PROJECT_FILES = [
    "alu.v",
    "regfile.v",
    "cpu_core.v",
    # ... resto de archivos
]
```

Si se agrega un módulo nuevo, incluirlo en esta lista en el orden correcto (dependencias antes que dependientes).

---

## 15. `uart_flash.py` — Herramienta de Carga vía UART

### Función

Envía un archivo `.bin` (generado por `assembler.py --binary`) a la FPGA mediante el puerto serie, usando el protocolo del `uart_loader`.

### Dependencia

```bash
pip install pyserial
```

### Uso

```bash
# Listar puertos disponibles
python3 uart_flash.py --list

# Cargar programa
python3 uart_flash.py programa.bin --port COM3
python3 uart_flash.py programa.bin --port /dev/ttyUSB0

# Sin mensajes
python3 uart_flash.py programa.bin --port COM3 --quiet
```

### Flujo completo de recarga

```bash
# 1. Editar el programa
#    (editar programa.asm)

# 2. Ensamblar
python3 assembler.py programa.asm --binary -o programa.bin

# 3. Cargar a la FPGA (sin sintetizar de nuevo)
python3 uart_flash.py programa.bin --port COM3

# La FPGA detiene el CPU, carga el nuevo programa,
# y reanuda ejecución automáticamente.
```

### Troubleshooting

```
Error: puerto no encontrado
  → Verificar que la Tang Nano 9K está conectada
  → En Windows: revisar Administrador de dispositivos → COM/LPT
  → En Linux: verificar permisos: sudo usermod -a -G dialout $USER

Error: timeout / no responde
  → Verificar baud rate (debe ser 115200 en FPGA y en uart_flash.py)
  → Verificar que el bitstream cargado incluye uart_loader
  → Hacer reset de la FPGA con S1 antes de intentar cargar

Error: header inválido
  → El archivo .bin fue generado sin el flag --binary
  → Regenerar con: python3 assembler.py prog.asm --binary -o prog.bin
```

---

## Apéndice A — Árbol de dependencias

```
tang_nano_top.v
└── microrv8_system.v
    ├── cpu_core.v
    │   ├── alu.v
    │   └── regfile.v
    ├── instruction_memory.v
    ├── data_memory.v
    ├── gpio.v
    ├── uart.v
    │   ├── uart_tx (en uart.v)
    │   ├── uart_rx (en uart.v)
    │   └── uart_mmio (en uart.v)
    ├── pwm.v
    └── uart_loader.v
        └── uart_rx (en uart.v)
```

## Apéndice B — Señales de debug

Todas las señales de debug se propagan desde el CPU hasta el top level:

```
debug_pc    [7:0]   PC actual (8 bits bajos, el bit 8 indica >255)
debug_state [7:0]   Estado FSM actual (bits [2:0] usados: 0-4)
debug_instr [15:0]  Instrucción en el IR actualmente
```

Para observarlas en FPGA conectarlas a pines libres en `tang_nano_top.v` y agregar las entradas en el `.cst`. También pueden analizarse con el Gowin Analyzer Oscilloscope sin modificar el pinout.

## Apéndice C — Checklist de síntesis

Antes de sintetizar, verificar:

- [x] `tang_nano_top` está marcado como top module
- [x] El archivo `.hex` del programa está en el directorio del proyecto (si usa `$readmemh`)
- [x] El `.cst` está incluido en el proyecto
- [x] Todos los `.v` están en la lista de fuentes en el orden correcto
- [x] No hay señales con múltiples drivers (revisar warnings en síntesis)
- [x] El reporte de timing muestra slack positivo (o cero) en el peor caso

## Apéndice D — Extensiones futuras

El diseño actual puede extenderse con:

```
Característica            Dificultad   Archivos a modificar
────────────────────────  ──────────   ──────────────────────────────
Instrucción BNE           Baja         cpu_core.v, assembler.py
UART RX como periférico   Baja         uart.v (agregar addr 0x88-0x89)
Interrupciones (IRQ)      Media        cpu_core.v (agregar estado IRQ)
Multiplicación HW         Media        alu.v, cpu_core.v, assembler.py
Stack pointer (SP)        Media        cpu_core.v (usar r7 como SP)
Más RAM (256 bytes)       Baja         data_memory.v (cambiar ram[0:255])
Segundo UART              Baja         instanciar uart_mmio en system
Comunicación SPI          Alta         nuevo módulo spi.v
```
alch todo esta dificil
