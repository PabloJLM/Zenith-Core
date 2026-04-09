# Documentación 

Primer microcontrolador de 8 bits basado en RISC-V diseñado en Guatemala.
Arquitectura: subset RISC-V de 16 bits, 8 registros, datos de 8 bits, periféricos MMIO.

---

## Índice

**Sistema**
1. Arquitectura general
2. Mapa de memoria

**ISA y programación**
3. Registros
4. Formato de instrucción
5. Tabla de instrucciones
6. Guía de programación en assembly

**Módulos RTL**
7. `alu.v`
8. `regfile.v`
9. `cpu_core.v`
10. `instruction_memory.v`
11. `data_memory.v`
12. `gpio.v`
13. `uart.v`
14. `pwm.v`
15. `uart_loader.v`
16. `microrv8_system.v`
17. `tang_nano_top.v`
18. `tang_nano_9k.cst`

**Herramientas**
19. `assembler.py`
20. `sim_gui.py`
21. `uart_flash.py`

**Referencia**
22. Árbol de dependencias
23. Señales de debug
24. Flujo de síntesis en Gowin EDA
25. Extensiones futuras

---

## 1. Arquitectura general

### Diagrama de bloques
![fs2](../imgs/Microxd.png)

### Números clave

```
Clock (Tang Nano 9K)    27 MHz
Instrucciones/segundo   5,400,000  (5 ciclos por instrucción)
Registros               8 (r0-r7, r0 hardwired zero)
Ancho de datos          8 bits
Ancho de instrucción    16 bits
Memoria de programa     512 instrucciones (1 KB)
Memoria de datos        128 bytes RAM + 128 bytes MMIO
Uso LUTs FPGA           ~800-1200 de 8640 disponibles
Uso BRAM FPGA           1 bloque de 9K (instruction_memory)
```

---

## 2. Mapa de memoria

```
Dirección   Acceso   Periférico     Descripción
──────────  ───────  ────────────   ─────────────────────────────────────────────
0x00-0x1F   R/W      RAM            Zona de stack sugerida (32 bytes)
0x20-0x7F   R/W      RAM            Variables de usuario (96 bytes)

0x80        W        GPIO_OUT       Escribir en pines de salida
0x81        R        GPIO_IN        Leer pines de entrada
0x82        W        GPIO_DIR       Dirección bit a bit: 0=input, 1=output

0x83        W        UART_TX        Byte a transmitir (ignorado si tx_busy=1)
0x84        R        UART_STAT      bit0 = tx_busy

0x85        W        PWM_DUTY       Duty cycle 0-255
0x86        W        PWM_CTRL       bit0=enable, bit1=invert polaridad
0x87        W        PWM_PRE        Prescaler 1-255 (default=105 → ~1kHz@27MHz)

0x88-0xFF   —        Reservado      Para extensiones futuras
```

### Acceder al mapa de memoria desde assembly

Las instrucciones LOAD/STORE usan `rs1 + imm4` como dirección. El imm4 tiene 4 bits con signo (rango -8 a +7), así que las direcciones MMIO (≥ 0x80) hay que construirlas en un registro primero:

```asm
; Construir 0x80 en r6 (operación inicial, hacer una sola vez)
ADDI r5, r0, 8          ; r5 = 8
ADDI r4, r0, 4          ; r4 = 4  (shift amount)
SLL  r6, r5, r4         ; r6 = 8 << 4 = 128 = 0x80

; Acceder a los periféricos usando r6 como base
STORE r1, r6, 0         ; GPIO_OUT   (0x80 + 0 = 0x80)
LOAD  r2, r6, 1         ; GPIO_IN    (0x80 + 1 = 0x81)
STORE r1, r6, 3         ; UART_TX    (0x80 + 3 = 0x83)
LOAD  r3, r6, 4         ; UART_STAT  (0x80 + 4 = 0x84)
STORE r1, r6, 5         ; PWM_DUTY   (0x80 + 5 = 0x85)
```

---

## 3. Registros

```
Registro   ABI Name   Descripción y convención de uso
────────   ────────   ────────────────────────────────────────────────────────
r0         zero       Hardwired 0. Leer siempre da 0. Escribir no tiene efecto.
r1         t0         Contador principal / argumento 1 / primer temporal
r2         t1         Variable secundaria / contador de delay loops
r3         t2         Tercer temporal o constante de comparación
r4         t3         Resultado de comparaciones (SLT, SLTI, flags)
r5         t4         Constante auxiliar (ej: 8 para construir valores MMIO)
r6         s0         Base de dirección MMIO (guarda 0x80 y se mantiene)
r7         ra         Return address — JAL escribe aquí automáticamente
```

### Por qué r0 es hardwired zero

En RISC-V clásico, `x0` siempre es cero. Esto simplifica el ISA: no se necesita instrucción `MOV`, basta con `ADD rd, rs, x0`. No se necesita `CLEAR`, basta con `ADD rd, x0, x0`. El comparador de BEQ se hace con `SUB` y se compara contra `r0`. Se elimina el caso especial de registros sin fuente de cero.

---

## 4. Formato de instrucción (16 bits)

Todas las instrucciones tienen exactamente 16 bits. Los campos varían según el tipo.

```
Tipo I  (ALU inmediato)   opcode=000
  [15:13] opcode  [12:10] rd  [9:7] rs1  [6:4] funct3  [3:0] imm4
  rd = rs1 OP sign_ext(imm4)

Tipo R  (ALU registro)    opcode=001
  [15:13] opcode  [12:10] rd  [9:7] rs1  [6:4] rs2  [3:1] funct3  [0] 0
  rd = rs1 OP rs2

Tipo L  (LOAD)            opcode=010
  [15:13] opcode  [12:10] rd  [9:7] rs1  [6:4] 000  [3:0] imm4
  rd = MEM[rs1 + sign_ext(imm4)]

Tipo S  (STORE)           opcode=011
  [15:13] opcode  [12:10] rs2  [9:7] rs1  [6:4] 000  [3:0] imm4
  MEM[rs1 + sign_ext(imm4)] = rs2

Tipo B  (BEQ)             opcode=100
  [15:13] opcode  [12:10] rs1  [9:7] rs2  [6:4] 000  [3:0] imm4
  if rs1==rs2: PC += sign_ext(imm4)

Tipo J  (JUMP / JAL)      opcode=111 / 101
  [15:13] opcode  [12:10] rd  [9:0] target10
  PC = target10        (JUMP)
  rd = PC+1; PC = target10  (JAL)

Tipo O  (OUT GPIO)        opcode=110
  [15:13] opcode  [12:10] 000  [9:7] rs1  [6:0] 0
  gpio_out = rs1
```

### Extensión de signo del inmediato

```
imm4     Decimal   8 bits extendido
0000      0         0x00
0001      1         0x01
0111      7         0x07
1000     -8         0xF8
1111     -1         0xFF

Rango útil: -8 a +7
```

### Cálculo del offset para BEQ

```
offset = dirección_destino - (PC_de_la_instrucción_BEQ + 1)

Ejemplo: BEQ en addr 7, quiero saltar a addr 5
  offset = 5 - (7 + 1) = -3  →  imm4 = 1101 (0xD en hex)

Rango: -8 a +7 instrucciones relativas
Para saltos más largos: usar JUMP (destino absoluto de 9 bits)
```

---

## 5. Tabla de instrucciones

### Códigos funct3 para ALU

```
funct3   Operación   Tipo I mnemónico   Tipo R mnemónico
──────   ─────────   ────────────────   ────────────────
000      ADD         ADDI               ADD
001      SUB         SUBI               SUB
010      AND         ANDI               AND
011      OR          ORI                OR
100      XOR         XORI               XOR
101      SLL         SLLI               SLL
110      SRL         SRLI               SRL
111      SLT         SLTI               SLT
```

### Instrucciones completas

```
Mnemónico  Tipo   Opcode  funct3  Sintaxis assembly         Operación
─────────  ─────  ──────  ──────  ───────────────────────   ──────────────────────────────
ADDI       I      000     000     ADDI rd, rs1, imm         rd = rs1 + sign_ext(imm)
SUBI       I      000     001     SUBI rd, rs1, imm         rd = rs1 - sign_ext(imm)
ANDI       I      000     010     ANDI rd, rs1, imm         rd = rs1 & sign_ext(imm)
ORI        I      000     011     ORI  rd, rs1, imm         rd = rs1 | sign_ext(imm)
XORI       I      000     100     XORI rd, rs1, imm         rd = rs1 ^ sign_ext(imm)
SLLI       I      000     101     SLLI rd, rs1, imm         rd = rs1 << imm
SRLI       I      000     110     SRLI rd, rs1, imm         rd = rs1 >> imm
SLTI       I      000     111     SLTI rd, rs1, imm         rd = (rs1 < imm) ? 1 : 0

ADD        R      001     000     ADD  rd, rs1, rs2         rd = rs1 + rs2
SUB        R      001     001     SUB  rd, rs1, rs2         rd = rs1 - rs2
AND        R      001     010     AND  rd, rs1, rs2         rd = rs1 & rs2
OR         R      001     011     OR   rd, rs1, rs2         rd = rs1 | rs2
XOR        R      001     100     XOR  rd, rs1, rs2         rd = rs1 ^ rs2
SLL        R      001     101     SLL  rd, rs1, rs2         rd = rs1 << rs2[2:0]
SRL        R      001     110     SRL  rd, rs1, rs2         rd = rs1 >> rs2[2:0]
SLT        R      001     111     SLT  rd, rs1, rs2         rd = (rs1 < rs2) ? 1 : 0

LOAD       L      010     —       LOAD rd, rs1, imm         rd = MEM[rs1 + imm]
STORE      S      011     —       STORE rs2, rs1, imm       MEM[rs1 + imm] = rs2

BEQ        B      100     —       BEQ  rs1, rs2, label      if rs1==rs2: PC += imm
JUMP       J      111     —       JUMP label                PC = target (9 bits, absoluto)
JAL        J      101     —       JAL  rd, label            rd = PC+1; PC = target

OUT        O      110     —       OUT  rs1                  gpio_out = rs1

NOP        P      —       —       NOP                       ADDI r0, r0, 0  (sin efecto)
MOV        P      —       —       MOV  rd, rs               ADD rd, rs, r0
```

### Limitaciones del ISA actual

```
BEQ offset       Solo -8 a +7 instrucciones relativas. Saltos más largos: usar JUMP.
JUMP/JAL         Destino absoluto en 9 bits (0-511). No existe JALR (salto a registro).
Retorno          JAL guarda PC+1 en rd, pero JUMP necesita destino fijo. El retorno
                 dinámico (a cualquier caller) no es posible sin tabla de saltos.
Branches         Solo BEQ. No existe BNE, BLT, BGE. Workarounds con SLT + BEQ.
Inmediato > 7    Hay que construirlo con SLL y sumas.
Interrupciones   El timer IRQ existe en hardware pero no está conectado al CPU.
```

---

## 6. Guía de programación en assembly

### Estructura básica de un programa

```asm
; Comentarios con punto y coma
; Los labels terminan con dos puntos

    ; Inicialización (sin label, se ejecuta solo una vez)
    ADDI r1, r0, 0          ; r1 = 0  (contador)

main:
    ADDI r1, r1, 1          ; r1++
    OUT  r1                 ; gpio_out = r1  (ver en LEDs)
    JUMP main               ; loop infinito
```

### Construir valores mayores que 7

```asm
; Construir 0x80 = 128 en r6
ADDI r5, r0, 8              ; r5 = 8
ADDI r4, r0, 4              ; r4 = 4
SLL  r6, r5, r4             ; r6 = 8 << 4 = 128 = 0x80

; Derivar otras direcciones MMIO desde r6
ADDI r3, r6, 3              ; r3 = 0x83  (UART_TX)
ADDI r4, r6, 6              ; r4 = 0x86  (PWM_CTRL)

; Construir 65 = 'A' en r1
ADDI r5, r0, 8
ADDI r4, r0, 3
SLL  r1, r5, r4             ; r1 = 64
ADDI r1, r1, 1              ; r1 = 65

; Construir -1 = 255 en r1
ADDI r1, r0, -1             ; 0xFF en complemento a 2 de 8 bits
```

### Delay con contador

```asm
    ADDI r2, r0, 15         ; r2 = número de iteraciones
delay_loop:
    ADDI r2, r2, -1         ; r2--
    BEQ  r2, r0, delay_done ; si r2 == 0, salir
    JUMP delay_loop
delay_done:
```

### GPIO

```asm
    ; Configurar todos los pines como salida
    ADDI r1, r0, -1         ; r1 = 0xFF
    STORE r1, r6, 2         ; GPIO_DIR = 0xFF  (0x80+2)

    ; Escribir al GPIO
    ADDI r1, r0, 5
    STORE r1, r6, 0         ; GPIO_OUT = 5  (0x80+0)

    ; Leer del GPIO
    LOAD r2, r6, 1          ; r2 = GPIO_IN  (0x80+1)
```

### UART

```asm
    ; r1 = byte a enviar
uart_esperar:
    LOAD  r4, r6, 4         ; r4 = UART_STAT  (0x80+4)
    ANDI  r4, r4, 1         ; r4 = bit busy
    BEQ   r4, r0, uart_ok   ; si busy==0, enviar
    JUMP  uart_esperar
uart_ok:
    STORE r1, r6, 3         ; UART_TX = r1  (0x80+3)
```

### PWM

```asm
    ; Habilitar PWM
    ADDI r1, r0, 1
    STORE r1, r6, 6         ; PWM_CTRL = 1  (0x80+6, enable)

    ; Duty cycle 50%: construir 128 = 0x80
    ADDI r5, r0, 8
    ADDI r4, r0, 4
    SLL  r1, r5, r4         ; r1 = 128
    STORE r1, r6, 5         ; PWM_DUTY = 128  (0x80+5)
```

### Detección de condiciones sin BNE

```asm
    ; if r1 != r2: hacer algo
    SUB  r4, r1, r2         ; r4 = r1 - r2
    BEQ  r4, r0, son_iguales
    ; aquí r1 != r2
son_iguales:

    ; if r1 > r2: hacer algo
    SLT  r4, r2, r1         ; r4 = (r2 < r1) = (r1 > r2) ? 1 : 0
    BEQ  r4, r0, no_mayor   ; si r4==0, no es mayor
    ; aquí r1 > r2
no_mayor:
```

### Subrutinas con JAL

```asm
main:
    ADDI r1, r0, 5
    JAL  r7, duplicar       ; r7 = addr retorno, saltar
    ; r1 = 10 aquí
    JUMP main

duplicar:
    ADD r1, r1, r1          ; r1 = r1 * 2
    JUMP main               ; retornar (dirección hardcodeada)
    ; Limitación: si hay múltiples callers, necesitar tabla de saltos
```

---

## 7. `alu.v` — Unidad Aritmético-Lógica

### Función

Realiza las 8 operaciones aritméticas y lógicas del ISA. Completamente combinacional: sin registros internos, el resultado está disponible en el mismo ciclo en que llegan las entradas.

### Interfaz

```verilog
module alu_8bit (
    input  wire [7:0] a,        // Operando A (de rs1 del regfile)
    input  wire [7:0] b,        // Operando B (de rs2 o inmediato)
    input  wire [2:0] op,       // Código de operación (funct3)
    output reg  [7:0] result,   // Resultado de 8 bits
    output wire       zero,     // 1 si result == 0
    output wire       carry,    // 1 si hubo carry sin signo
    output wire       negative  // 1 si bit 7 del resultado es 1
);
```

### Implementación del carry

Para capturar el acarreo sin perderlo se usa un resultado interno de 9 bits:

```verilog
reg [8:0] result_ext;
// Para ADD: result_ext = {1'b0, a} + {1'b0, b}
// carry    = result_ext[8]
// result   = result_ext[7:0]
```

### Notas de diseño

`SLT` compara sin signo. `a=0xFF, b=0x01` → `SLT = 0` porque 255 > 1 sin signo. Para comparación con signo habría que inspeccionar el flag `negative` de SUB.

Los flags `carry` y `negative` están disponibles como salidas del módulo pero el CPU actual solo usa `zero` (para BEQ). Están preparados para extensiones con BLT, BGE, etc.

---

## 8. `regfile.v` — Banco de Registros

### Función

Almacena los 8 registros de propósito general. Dos puertos de lectura simultánea combinacionales (sin latencia de clock) y un puerto de escritura síncrona.

### Interfaz

```verilog
module regfile (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] rs1_addr,
    output wire [7:0] rs1_data,
    input  wire [2:0] rs2_addr,
    output wire [7:0] rs2_data,
    input  wire [2:0] rd_addr,
    input  wire [7:0] rd_data,
    input  wire       rd_we
);
```

### Comportamiento

Lectura combinacional: las salidas cambian inmediatamente al cambiar las direcciones.

```verilog
assign rs1_data = (rs1_addr == 3'd0) ? 8'h00 : regs[rs1_addr];
assign rs2_data = (rs2_addr == 3'd0) ? 8'h00 : regs[rs2_addr];
```

Escritura síncrona, ignorando r0:

```verilog
if (rd_we && rd_addr != 3'd0)
    regs[rd_addr] <= rd_data;
```

En reset activo bajo, todos los registros vuelven a 0.

---

## 9. `cpu_core.v` — Núcleo del CPU

### Función

Orquesta el ALU, el register file y los buses de instrucciones y datos. Implementa el ciclo fetch-decode-execute mediante una FSM de 5 estados.

### Interfaz

```verilog
module cpu_core (
    input  wire        clk,
    input  wire        rst_n,

    output wire [8:0]  pc_out,          // PC → instruction_memory
    input  wire [15:0] instruction_in,  // instrucción desde imem (combinacional)

    output reg  [7:0]  mem_addr,        // dirección de datos
    output reg  [7:0]  mem_wdata,       // dato para STORE
    input  wire [7:0]  mem_rdata,       // dato de LOAD
    output reg         mem_we,          // write enable (1 ciclo)
    output reg         mem_re,          // read enable  (1 ciclo)

    output reg  [7:0]  gpio_out,        // instrucción OUT

    output wire [7:0]  debug_pc,
    output wire [7:0]  debug_state,
    output wire [15:0] debug_instr
);
```

### FSM de 5 estados

Cada instrucción toma exactamente 5 ciclos de clock.

```
Estado        Código   Duración   Qué ocurre
────────────  ──────   ────────   ──────────────────────────────────────────────
S_FETCH       3'd0     1 ciclo    IR ← instruction_in  (ya válido, imem combina.)
S_DECODE      3'd1     1 ciclo    Lee rs1/rs2 del regfile, configura alu_a/b/op
S_EXECUTE     3'd2     1 ciclo    ALU opera, captura resultado (alu_res, alu_z)
S_MEMORY      3'd3     1 ciclo    Accede a RAM o actualiza gpio_out (instruc. OUT)
S_WRITEBACK   3'd4     1 ciclo    Escribe rd_wdata en regfile, actualiza PC
```

### Decodificación de campos del IR

```verilog
wire [2:0] opcode = ir[15:13];
wire [2:0] f_rd   = ir[12:10];   // destino / rs1 en BEQ / rs2 en STORE
wire [2:0] f_rs1  = ir[9:7];     // fuente A
wire [2:0] f_rs2  = ir[6:4];     // fuente B (R) o funct3 (I)
wire [2:0] f_fn3r = ir[3:1];     // funct3 para R-type
wire [3:0] f_imm4 = ir[3:0];
wire [7:0] imm_se = {{4{f_imm4[3]}}, f_imm4};   // sign-extend a 8 bits
```

### Mux de puertos del register file

El regfile tiene dos puertos de lectura. El CPU los redirige según el tipo de instrucción:

```
Instrucción   Puerto A (ra_addr)    Puerto B (rb_addr)
───────────   ──────────────────    ──────────────────
I / R / L     f_rs1                 f_rs2
STORE         f_rs1 (base)          f_rd  (dato a escribir)
BEQ           f_rd  (primer op)     f_rs1 (segundo op)
```

### Comportamiento por estado y opcode

**S_DECODE — configurar ALU:**

| Opcode | alu_a   | alu_b   | alu_op         |
|--------|---------|---------|----------------|
| 000 I  | rs1     | imm_se  | f_rs2 (funct3) |
| 001 R  | rs1     | rs2     | f_fn3r (funct3)|
| 010 L  | rs1     | imm_se  | ADD (dirección)|
| 011 S  | rs1     | imm_se  | ADD (dirección)|
| 100 B  | rs1*    | rs2*    | SUB (comparar) |
| 110 O  | rs1     | 0       | ADD (guardar)  |

*BEQ: rs1 llega via f_rd, rs2 via f_rs1 (mux del regfile).

**S_MEMORY:**

| Opcode | Acción |
|--------|--------|
| 010 L  | `mem_addr = alu_res; mem_re = 1` |
| 011 S  | `mem_addr = alu_res; mem_wdata = store_dat; mem_we = 1` |
| 110 O  | `gpio_out = alu_a` (rs1 capturado en DECODE) |

**S_WRITEBACK:**

| Opcode | Escribe en rd       | PC siguiente              |
|--------|---------------------|---------------------------|
| 000 I  | alu_res             | PC + 1                    |
| 001 R  | alu_res             | PC + 1                    |
| 010 L  | mem_rdata           | PC + 1                    |
| 011 S  | —                   | PC + 1                    |
| 100 B  | —                   | PC + imm si zero / PC + 1 |
| 101 J  | pc_lat[7:0] + 1     | ir[8:0] (target)          |
| 110 O  | —                   | PC + 1                    |
| 111 J  | —                   | ir[8:0] (target)          |

---

## 10. `instruction_memory.v` — Memoria de Instrucciones

### Función

ROM de 512 × 16 bits. Puerto de lectura combinacional para el CPU y puerto de escritura síncrona para el `uart_loader`.

### Interfaz

```verilog
module instruction_memory (
    input  wire        clk,
    input  wire [8:0]  addr,       // PC del CPU → lectura combinacional
    output wire [15:0] data_out,   // instrucción
    input  wire [8:0]  wr_addr,    // escritura desde loader
    input  wire [15:0] wr_data,
    input  wire        wr_en
);
```

### Por qué la lectura es combinacional

Si fuera síncrona, el CPU necesitaría un ciclo extra de espera por instrucción, complicando la FSM. Al ser combinacional, la instrucción está disponible en el mismo ciclo en que el PC es válido. En síntesis Gowin, 512 × 16 = 8 Kbits caben en un bloque BRAM de 9K.

### Cargar programas

```bash
# En simulación con archivo externo
iverilog -g2012 -DPROGRAM_HEX='"prog.hex"' -o sim.vvp *.v testbench.v

# En caliente a la FPGA (sin resintetizar)
python3 assembler.py prog.asm --binary -o prog.bin
python3 uart_flash.py prog.bin --port COM3
```

---

## 11. `data_memory.v` — Memoria de Datos y Decodificador MMIO

### Función

RAM de 128 bytes para variables de usuario. Detecta si el acceso va a RAM (0x00-0x7F) o a periféricos MMIO (0x80-0xFF) y genera las señales correspondientes.

### Interfaz

```verilog
module data_memory (
    input  wire        clk, rst_n,
    input  wire [7:0]  addr,
    input  wire [7:0]  data_in,
    input  wire        we, re,
    output reg  [7:0]  data_out,
    output reg  [7:0]  mmio_addr,
    output reg  [7:0]  mmio_data_wr,
    input  wire [7:0]  mmio_data_rd,   // respuesta del periférico (muxeada en system)
    output reg         mmio_we,
    output reg         mmio_re
);
```

### Decodificación

```verilog
wire is_mmio = addr[7];   // bit 7 = 1 → 0x80-0xFF → MMIO
```

Cuando `addr >= 0x80`, activa `mmio_we` o `mmio_re` en lugar de acceder a la RAM interna. En `microrv8_system.v`, un mux selecciona cuál periférico responde en `mmio_data_rd`.

### Nota sobre latencia en lectura MMIO

Una lectura MMIO (LOAD desde ≥ 0x80) tiene un ciclo de latencia extra: el periférico presenta `mmio_data_rd` en el ciclo siguiente al que recibe `mmio_re`. El CPU actual no espera ese ciclo extra. En la práctica: STORE a periféricos funciona perfectamente, LOAD desde MMIO puede llegar un ciclo tarde.

---

## 12. `gpio.v` — GPIO 8 bits

### Función

Ocho pines configurables individualmente como entrada o salida. Acceso vía bus MMIO.

### Interfaz

```verilog
module gpio_8bit (
    input  wire        clk, rst_n,
    input  wire [7:0]  mmio_addr,
    input  wire [7:0]  mmio_data_in,
    output reg  [7:0]  mmio_data_out,
    input  wire        mmio_we, mmio_re,
    input  wire [7:0]  gpio_in,
    output reg  [7:0]  gpio_out,
    output reg  [7:0]  gpio_dir
);
```

### Registros

| Dirección | Acceso | Nombre   | Descripción |
|-----------|--------|----------|-------------|
| 0x80      | W      | GPIO_OUT | Valor de los pines de salida |
| 0x81      | R      | GPIO_IN  | Valor actual de los pines físicos |
| 0x82      | W      | GPIO_DIR | 0=input, 1=output por pin |

`GPIO_OUT` se actualiza sincrónicamente. `GPIO_IN` se lee combinacionalmente desde los pines físicos. `GPIO_DIR` configura los buffers tristate; la lógica tristate real está en el top level de FPGA.

### GPIO combinado en el sistema

```verilog
// microrv8_system.v
assign gpio_out = gpio_out_mmio | cpu_gpio_direct;
```

`gpio_out_mmio` viene de STORE a 0x80. `cpu_gpio_direct` viene de la instrucción OUT. Solo una actúa a la vez, el OR no genera conflictos.

---

## 13. `uart.v` — UART TX + RX + Wrapper MMIO

El archivo contiene tres módulos.

### `uart_tx` — Transmisor

Formato 8N1, LSB primero. Baud rate configurable por parámetro.

```verilog
module uart_tx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk, rst_n,
    input  wire [7:0] data_in,
    input  wire       tx_start,   // pulso 1 ciclo para iniciar
    output reg        tx_busy,
    output reg        tx          // idle = 1
);
```

`BAUD_DIV = CLK_FREQ / BAUD_RATE`. Tang Nano 9K a 27 MHz con 115200 baud: `BAUD_DIV = 234 ciclos/bit`.

FSM: `IDLE → START_BIT → DATA (8 bits) → STOP_BIT → IDLE`.

### `uart_rx` — Receptor

Detecta flanco de bajada del start bit. Muestrea cada bit en el centro de su período (`HALF_DIV` ciclos). Incluye sincronizador de 2 flip-flops en la entrada `rx`.

```verilog
module uart_rx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk, rst_n,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid   // pulso 1 ciclo al completar byte
);
```

### `uart_mmio` — Wrapper MMIO

| Dirección | Acceso | Descripción |
|-----------|--------|-------------|
| 0x83      | W      | UART_TX: escribir inicia transmisión |
| 0x84      | R      | UART_STAT: bit0 = tx_busy |

Escritura a 0x83 mientras `tx_busy = 1` se ignora silenciosamente. El programa debe verificar UART_STAT antes de cada envío.

---

## 14. `pwm.v` — PWM 8 bits

### Función

Genera señal PWM con resolución de 8 bits y frecuencia ajustable vía prescaler.

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

### Registros y cálculo de frecuencia

| Dirección | Nombre   | Rango | Descripción |
|-----------|----------|-------|-------------|
| 0x85      | PWM_DUTY | 0-255 | 0=0%, 255=100% |
| 0x86      | PWM_CTRL | 0-3   | bit0=enable, bit1=invert |
| 0x87      | PWM_PRE  | 1-255 | Prescaler de frecuencia |

```
f_PWM = CLK_FREQ / (PRESCALER × 256)

A 27 MHz:
  PRE=1   →  ~105 kHz
  PRE=27  →  ~3.9 kHz
  PRE=105 →  ~1 kHz  (valor por defecto)
```

Implementación: dos contadores anidados. El prescaler cuenta hasta `PRE-1` y en cada desborde el contador PWM de 8 bits avanza. Cuando `pwm_cnt < duty`, salida = 1; si no, salida = 0. El contador PWM hace wrap automático en 255.

---

## 15. `uart_loader.v` — Cargador de Programas vía UART

### Función

Permite reprogramar el CPU sin resintetizar la FPGA. Mientras carga, mantiene el CPU en reset. Al terminar, el CPU arranca con el nuevo programa.

### Interfaz

```verilog
module uart_loader #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire        clk, rst_n,
    input  wire        rx,
    output reg  [8:0]  wr_addr,
    output reg  [15:0] wr_data,
    output reg         wr_en,
    output reg         loading,    // 1 = CPU en reset
    output reg         load_done   // pulso al terminar
);
```

### Protocolo

```
Byte 0    0xAA              sync byte 1
Byte 1    0x55              sync byte 2
Byte 2    count[8]          bit 8 del conteo (0 si < 256 instrucciones)
Byte 3    count[7:0]        cantidad de instrucciones
Bytes 4+  instrucciones     big-endian, 2 bytes por instrucción
```

Si llegan bytes incorrectos, el loader vuelve a esperar `0xAA 0x55`. La transmisión completa puede reenviarse en cualquier momento.

### Integración en el sistema

```verilog
wire cpu_rst_n = rst_n & ~loader_loading;
```

Los periféricos solo usan `rst_n`; no se resetean durante la carga.

---

## 16. `microrv8_system.v` — Sistema Completo

### Función

Top level que instancia todos los módulos, define el mapa MMIO, y gestiona el reset del CPU.

### Parámetros

```verilog
module microrv8_system #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)
```

Se propagan a `uart_tx`, `uart_rx`, `uart_mmio`, `uart_loader` y `pwm_8bit`.

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

### Mux de lectura MMIO

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

### Reset jerárquico

```verilog
wire cpu_rst_n = rst_n & ~loader_loading;
```

El CPU se resetea con el botón S1 o cuando el loader está activo. Los periféricos solo usan `rst_n`.

---

## 17. `tang_nano_top.v` — Wrapper Tang Nano 9K

Adapta `microrv8_system` a los pines físicos de la Tang Nano 9K.

Clock: 27 MHz del oscilador interno. Reset: botón S1 activo bajo con pull-up.

LEDs activos en bajo:

```verilog
assign led_n = ~gpio_out_full[5:0];
// bit 0 → LED 0 (más cercano al USB)
// bit 5 → LED 5 (más alejado)
```

Los puertos de debug están conectados internamente pero no van a pines externos. Para usarlos: agregar entradas en el módulo y en el `.cst`, o usar Gowin Analyzer Oscilloscope.

---

## 18. `tang_nano_9k.cst` — Restricciones de Pines

### Sintaxis

```
IO_LOC  "nombre_señal_en_top" número_pin;
IO_PORT "nombre_señal_en_top" PULL_MODE=UP DRIVE=8;

PULL_MODE:  NONE | UP (~100kΩ) | DOWN | KEEPER
DRIVE:      4 | 8 | 12 | 16  (mA)
```

### Pines del proyecto

```
Pin   Señal        Pull      Drive   Descripción
────  ───────────  ────────  ─────   ─────────────────────────────
52    sys_clk      NONE      —       27 MHz
4     sys_rst_n    UP        —       Botón S1 (activo bajo)
10    led_n[0]     NONE      8       LED 0
11    led_n[1]     NONE      8       LED 1
13    led_n[2]     NONE      8       LED 2
14    led_n[3]     NONE      8       LED 3
15    led_n[4]     NONE      8       LED 4
16    led_n[5]     NONE      8       LED 5
17    uart_rx      UP        —       RX desde USB-UART
18    uart_tx      UP        8       TX hacia USB-UART
25    pwm_out      NONE      8       Salida PWM libre
```

Modificar pines: editar el `.cst` o usar `Tools → FloorPlanner → IO Constraint` en Gowin EDA.

---

## 19. `assembler.py` — Ensamblador de Dos Pasadas

### Función

Convierte código assembly MicroRV8-GT a código máquina. Salida en `.hex` para `$readmemh` o en `.bin` con header para `uart_loader`.

### Uso desde línea de comandos

```bash
python3 assembler.py programa.asm                      # genera program.hex
python3 assembler.py programa.asm -o salida.hex        # nombre de salida
python3 assembler.py programa.asm --binary -o prog.bin # también .bin
python3 assembler.py programa.asm --no-listing         # sin tabla
```

### Dos pasadas

**Primera pasada:** recorre líneas, elimina comentarios (`;`), detecta labels (`:`) y registra su dirección en un diccionario.

**Segunda pasada:** para cada instrucción construye la palabra de 16 bits. BEQ calcula el offset relativo `target - (addr + 1)`. JUMP/JAL usa los 9 bits bajos del target directamente.

### Uso como librería

```python
from assembler import Assembler

asm = Assembler()
asm.assemble("ADDI r1, r0, 5\nOUT r1\nJUMP 0")
asm.write_hex("prog.hex")
asm.write_bin("prog.bin")
asm.listing()
```

### Límites

```
Inmediato           -8 a +7
JUMP/JAL target     0 a 511  (9 bits)
BEQ offset          -8 a +7  (relativo a la instrucción siguiente)
Programa            máximo 512 instrucciones
```

---

## 20. `sim_gui.py` — GUI de Simulación

### Función

Interfaz gráfica con dos modos: testbench Verilog (iverilog + vvp + GTKWave) y cocotb (Python directo, sin Make).

### Uso

```bash
python3 sim_gui.py
```

### Modo 1 — Testbench Verilog

Compila todos los `.v` del proyecto más el testbench seleccionado, corre la simulación, abre GTKWave con el `.vcd` generado. Los archivos `tb_system.v` y `tb_cpu.v` ya incluyen `$dumpfile` y `$dumpvars`.

### Modo 2 — cocotb

No necesita Makefile. Seleccionar el archivo `.py` del test, escribir el nombre del módulo top (debe coincidir exactamente con el nombre en el `.v`), clic en **Todo**. La GUI llama internamente a `cocotb_tools.runner`.

### GTKWave en Windows

```python
# En sim_gui.py, primera línea configurable:
GTKWAVE_PATH = r"C:\gtkwave64\bin\gtkwave.exe"
```

Descargar de `https://sourceforge.net/projects/gtkwave/files/` → extraer → configurar la ruta.

---

## 21. `uart_flash.py` — Herramienta de Carga vía UART

### Función

Envía un programa a la FPGA vía puerto serie usando el protocolo de `uart_loader`. No requiere resintetizar.

### Dependencia

```bash
pip install pyserial
```

### Uso

```bash
python3 uart_flash.py --list                          # listar puertos
python3 uart_flash.py prog.bin --port COM3            # cargar en Windows
python3 uart_flash.py prog.bin --port /dev/ttyUSB0    # cargar en Linux
```

### Flujo completo

```bash
# 1. Escribir y ensamblar
python3 assembler.py mi_prog.asm --binary -o mi_prog.bin

# 2. Cargar sin resintetizar
python3 uart_flash.py mi_prog.bin --port COM3
```

### Troubleshooting

```
Puerto no encontrado
  Windows: Administrador de dispositivos → Puertos COM y LPT
  Linux:   sudo usermod -a -G dialout $USER  (cerrar sesión y reabrir)

No responde
  Verificar baud rate: 115200 en FPGA y en uart_flash.py
  El bitstream debe incluir uart_loader
  Presionar S1 antes de cargar para resetear

Header inválido
  Regenerar: python3 assembler.py prog.asm --binary -o prog.bin
```

---

## 22. Árbol de dependencias

```
tang_nano_top.v
└── microrv8_system.v
    ├── cpu_core.v
    │   ├── alu.v
    │   └── regfile.v
    ├── instruction_memory.v
    ├── data_memory.v
    ├── gpio.v
    ├── uart.v               ← contiene uart_tx, uart_rx, uart_mmio
    ├── pwm.v
    └── uart_loader.v
        └── uart_rx          ← módulo dentro de uart.v
```

Orden de compilación para iverilog:

```bash
iverilog -g2012 -o sim.vvp \
    alu.v regfile.v cpu_core.v \
    instruction_memory.v data_memory.v \
    gpio.v uart.v pwm.v uart_loader.v \
    microrv8_system.v \
    testbench.v
```

---

## 23. Señales de debug

```
Señal           Bits    Descripción
─────────────   ─────   ────────────────────────────────────────────────
debug_pc        [7:0]   PC actual (8 bits bajos; >0xFF cuando bit 8 es 1)
debug_state     [7:0]   Estado FSM en bits [2:0]: 0=FETCH 1=DEC 2=EXE 3=MEM 4=WB
debug_instr     [15:0]  Instrucción en el IR en este momento
```

Para observar en FPGA sin modificar el pinout: usar **Gowin Analyzer Oscilloscope** (`Tools → Gowin Analyzer Oscilloscope` en Gowin EDA). Para conectar a pines externos: agregar en `tang_nano_top.v` y en el `.cst`.

---

## 24. Flujo de síntesis en Gowin EDA

### Crear proyecto

```
File → New Project
  Device:  GW1NR-9C
  Package: QFN88
  Speed:   C6/I5
```

### Agregar fuentes

Clic derecho en `Design` → `Add Files`:

```
alu.v  regfile.v  cpu_core.v
instruction_memory.v  data_memory.v
gpio.v  uart.v  pwm.v  uart_loader.v
microrv8_system.v  tang_nano_top.v
tang_nano_9k.cst
```

Clic derecho en `tang_nano_top.v` → `Set as Top Module`.

### Cargar programa

Editar `instruction_memory.v` (bloque `initial`) o descomentar `$readmemh`. El `.hex` debe estar en el directorio del proyecto Gowin.

### Flujo de síntesis

```
Synthesize → Place & Route → Generate Bitstream → Program Device
```

### Interpretar el reporte de síntesis

```
Logic Elements:  < 8640   (el diseño usa ~800-1200)
BRAM:            1/26     (instruction_memory = 8 Kbits)
Timing Slack:    > 0 ns   (slack positivo = timing cumplido)
```

Errores comunes:

```
multiple drivers    Un wire manejado por dos always → revisar data_memory.v
latch inferred      Falta default en lógica combinacional → agregar default al case
undeclared id       Falta un archivo fuente → verificar lista en Design
```

### Programar la FPGA

```
Tools → Programmer
  Cable: USB Cable
  Query/Detect
  Modo SRAM:  temporal, se borra al desconectar. Para pruebas.
  Modo Flash: permanente. Para despliegue.
```

---
