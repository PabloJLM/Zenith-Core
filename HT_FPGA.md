# Hoja de Trabajo - FPGA

Primer microcontrolador de 8 bits basado en RISC-V, diseñado en Guatemala.

---

## Parte 1 — Arquitectura del sistema

### Diagrama de bloques

```
                        MicroRV8-GT System
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │   ┌─────────────┐     ┌──────────────────┐                  │
  │   │ UART Loader │────▶│ Instruction Mem  │                  │
  │   │  (uart_rx)  │     │  ROM 512x16 bits │                  │
  │   └─────────────┘     └────────┬─────────┘                  │
  │                                │ instruction[15:0]           │
  │                       ┌────────▼─────────┐                  │
  │                       │    CPU Core       │                  │
  │                       │  ┌────────────┐  │                  │
  │                       │  │  RegFile   │  │◀── rst_n         │
  │                       │  │  r0 .. r7  │  │                  │
  │                       │  └────────────┘  │                  │
  │                       │  ┌────────────┐  │                  │
  │                       │  │   ALU 8b   │  │                  │
  │                       │  └────────────┘  │                  │
  │                       │  ┌────────────┐  │                  │
  │                       │  │  FSM 5-est │  │                  │
  │                       │  └────────────┘  │                  │
  │                       └──────────────────┘                  │
  │                          │          │                        │
  │                    pc[8:0]        mem_addr/we/re             │
  │                          │          │                        │
  │                          │   ┌──────▼──────────┐            │
  │                          │   │  Data Memory    │            │
  │                          │   │  128B RAM       │            │
  │                          │   │  + MMIO decode  │            │
  │                          │   └──────┬──────────┘            │
  │                          │          │ mmio_addr/we/re        │
  │                          │    ┌─────┴──────────────────┐    │
  │                          │    │                        │    │
  │                   ┌──────┴──┐ ┌──────┐ ┌──────┐       │    │
  │                   │  GPIO   │ │ UART │ │  PWM │       │    │
  │                   │0x80-0x82│ │0x83-4│ │0x85-7│       │    │
  │                   └─────────┘ └──────┘ └──────┘       │    │
  │                       │           │         │          │    │
  └───────────────────────┼───────────┼─────────┼──────────┘    │
                      gpio_out    uart_tx    pwm_out              │
```

### Mapa de memoria de datos

```
Dirección  Ancho  Tipo   Descripción
─────────  ─────  ────   ─────────────────────────────────────
0x00-0x7F  8 bit  R/W    RAM de propósito general (128 bytes)
                          0x00-0x1F : zona de stack (32 bytes)
                          0x20-0x7F : variables de usuario

0x80       8 bit  W      GPIO_OUT   — escribir en pines de salida
0x81       8 bit  R      GPIO_IN    — leer pines de entrada
0x82       8 bit  W      GPIO_DIR   — dirección bit a bit (0=in, 1=out)

0x83       8 bit  W      UART_TX    — byte a transmitir
0x84       8 bit  R      UART_STAT  — bit0 = tx_busy

0x85       8 bit  W      PWM_DUTY   — duty cycle 0-255
0x86       8 bit  W      PWM_CTRL   — bit0=enable, bit1=invert
0x87       8 bit  W      PWM_PRE    — prescaler (default=105 → ~1kHz@27MHz)

0x88-0xFF  —      —      Reservado
```

---

## Parte 2 — ISA MicroRV8-GT (Reference Sheet)

### Registros

```
Registro  ABI Name  Descripción
────────  ────────  ────────────────────────────────────────
r0        zero      Hardwired 0. Escribir aquí no tiene efecto.
r1        t0        Temporal / argumento 1
r2        t1        Temporal / argumento 2 / contador de delay
r3        t2        Temporal / argumento 3
r4        t3        Temporal / resultado intermedio
r5        t4        Temporal de uso general
r6        s0        Saved / base de dirección MMIO
r7        ra        Return address (JAL lo escribe aquí)
```

### Formato de instrucción (16 bits)

```
Tipo I  (ALU con inmediato):
  15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
 ├────────────┤────────────┤────────────┤────────────┤────────────┤
 │   opcode   │     rd     │    rs1     │   funct3   │    imm4    │
 │   3 bits   │   3 bits   │   3 bits   │   3 bits   │   4 bits   │

Tipo R  (ALU registro-registro):
  15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
 ├────────────┤────────────┤────────────┤────────────┤──────────┤─┤
 │   opcode   │     rd     │    rs1     │    rs2     │  funct3  │0│
 │   001      │   3 bits   │   3 bits   │   3 bits   │  3 bits  │ │

Tipo L  (LOAD):
 │   010      │     rd     │    rs1     │    000     │    imm4    │

Tipo S  (STORE):
 │   011      │    rs2     │    rs1     │    000     │    imm4    │

Tipo B  (BEQ):
 │   100      │    rs1     │    rs2     │    000     │    imm4    │

Tipo J  (JUMP / JAL):
  15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
 ├────────────┤────────────┤──────────────────────────────────────┤
 │   opcode   │     rd     │            target[9:0]               │
 │ 111 / 101  │   3 bits   │              10 bits                 │

Tipo O  (OUT):
 │   110      │    000     │    rs1     │         0000000          │
```

### Tabla de instrucciones completa

```
Mnemónico  Tipo  Opcode  funct3  Operandos          Operación
─────────  ────  ──────  ──────  ─────────────────  ──────────────────────────
ADDI       I     000     000     rd, rs1, imm       rd = rs1 + sign_ext(imm)
SUBI       I     000     001     rd, rs1, imm       rd = rs1 - sign_ext(imm)
ANDI       I     000     010     rd, rs1, imm       rd = rs1 & sign_ext(imm)
ORI        I     000     011     rd, rs1, imm       rd = rs1 | sign_ext(imm)
XORI       I     000     100     rd, rs1, imm       rd = rs1 ^ sign_ext(imm)
SLLI       I     000     101     rd, rs1, imm       rd = rs1 << imm
SRLI       I     000     110     rd, rs1, imm       rd = rs1 >> imm
SLTI       I     000     111     rd, rs1, imm       rd = (rs1 < imm) ? 1 : 0

ADD        R     001     000     rd, rs1, rs2       rd = rs1 + rs2
SUB        R     001     001     rd, rs1, rs2       rd = rs1 - rs2
AND        R     001     010     rd, rs1, rs2       rd = rs1 & rs2
OR         R     001     011     rd, rs1, rs2       rd = rs1 | rs2
XOR        R     001     100     rd, rs1, rs2       rd = rs1 ^ rs2
SLL        R     001     101     rd, rs1, rs2       rd = rs1 << rs2[2:0]
SRL        R     001     110     rd, rs1, rs2       rd = rs1 >> rs2[2:0]
SLT        R     001     111     rd, rs1, rs2       rd = (rs1 < rs2) ? 1 : 0

LOAD       L     010     —       rd, rs1, imm       rd = MEM[rs1 + imm]
STORE      S     011     —       rs2, rs1, imm      MEM[rs1 + imm] = rs2

BEQ        B     100     —       rs1, rs2, label    if rs1==rs2: PC += imm
JUMP       J     111     —       label              PC = target (abs, 9 bits)
JAL        J     101     —       rd, label          rd = PC+1; PC = target

OUT        O     110     —       rs1                gpio_out = rs1

NOP        P     —       —       —                  ADDI r0, r0, 0
MOV        P     —       —       rd, rs             ADD rd, rs, r0
```

### Notas sobre inmediatos

El campo `imm4` es de 4 bits con signo extendido a 8 bits en el hardware.

```
Rango decimal:  -8 a 7   (imm4 directo)
Rango hex:      0x0 a 0x7 (positivo), 0x8 a 0xF (negativo: -8 a -1)

Ejemplos:
  ADDI r1, r0, 5    ; r1 = 5
  ADDI r1, r0, -1   ; r1 = 255 (0xFF en 8 bits, complemento a 2)
  ADDI r1, r1, -1   ; r1 = r1 - 1

Para valores > 7: construir en partes usando ADD o SLL
  ADDI r5, r0, 8    ; r5 = 8
  ADDI r4, r0, 4    ; r4 = 4
  SLL  r6, r5, r4   ; r6 = 8 << 4 = 128 = 0x80
  ADDI r6, r6, 5    ; r6 = 0x85
```

### BEQ: cálculo de offset

```
offset = dirección_destino - (PC_actual + 1)

Rango útil: -8 a 7 instrucciones desde la siguiente instrucción
Equivalente a: PC de la instrucción BEQ +/- 8

Si el destino está más lejos: usar JUMP (destino absoluto, 9 bits)
```

---

## Parte 3 — Programación en Assembly

### Estructura de un programa

```asm
; Comentarios con punto y coma
; Los labels terminan en dos puntos

    ADDI r1, r0, 0      ; inicializar variable (sin label = instrucción directa)

main:
    ADDI r1, r1, 1      ; r1++
    OUT  r1             ; mostrar en GPIO
    JUMP main           ; loop infinito
```

### Convenciones de uso de registros

```
r0 — siempre 0, no se puede escribir
r1 — primera variable de trabajo o contador
r2 — segunda variable / delay counter
r3 — tercera variable / constante máx
r4 — resultado temporal de comparaciones
r5 — constante auxiliar (ej: 8 para construir 0x80)
r6 — dirección MMIO calculada
r7 — return address (JAL lo escribe automáticamente)
```

### Patrones comunes

**Delay con contador:**
```asm
    ADDI r2, r0, 15     ; r2 = 15 (número de iteraciones)
delay:
    ADDI r2, r2, -1     ; r2--
    BEQ  r2, r0, done   ; si r2 == 0, salir del delay
    JUMP delay
done:
    ; continúa aquí
```

**Escribir a MMIO (GPIO output):**
```asm
    ; Construir dirección 0x80
    ADDI r5, r0, 8      ; r5 = 8
    ADDI r4, r0, 4      ; r4 = 4
    SLL  r6, r5, r4     ; r6 = 0x80

    ADDI r1, r0, 7      ; r1 = dato a escribir
    STORE r1, r6, 0     ; MEM[0x80] = r1 → GPIO_OUT = 7
```

**Leer desde MMIO (GPIO input):**
```asm
    ; r6 = 0x80 (ya calculado)
    ADDI r3, r6, 1      ; r3 = 0x81 = GPIO_IN
    LOAD r2, r3, 0      ; r2 = MEM[0x81] = GPIO_IN
```

**Enviar byte por UART:**
```asm
    ; r_tx  = 0x83 (UART_TX)
    ; r_st  = 0x84 (UART_STAT)
uart_wait:
    LOAD  r4, r_st, 0   ; r4 = UART_STAT
    ANDI  r4, r4, 1     ; r4 = r4 & 1 (bit busy)
    BEQ   r4, r0, uart_send
    JUMP  uart_wait
uart_send:
    STORE r1, r_tx, 0   ; UART_TX = r1 (byte a enviar)
```

**Subrutinas con JAL:**
```asm
main:
    JAL  r7, mi_funcion  ; r7 = dirección de retorno, salta a mi_funcion
    ; ... continúa aquí después del retorno

mi_funcion:
    ; ... código de la función
    JUMP main            ; retornar: JUMP dirección guardada en r7
                         ; (limitación: JUMP solo usa target fijo, no registro)
                         ; Para retorno dinámico se necesita una tabla de saltos
```

---

## Parte 4 — Uso de Gowin EDA

### Instalación y activación

1. Registrarse en `https://www.gowinsemi.com/en/support/download_eda/`
2. Descargar **Gowin EDA Education** (versión gratuita)
3. Al abrir, ir a `License Manager` → `Online License` → activar con la cuenta registrada

### Crear proyecto para Tang Nano 9K

```
File → New Project
  Name:     microrv8gt
  Location: (carpeta del proyecto)
  Type:     FPGA Design Project

Device Selection:
  Series:  GW1NR
  Device:  GW1NR-9C
  Package: QFN88
  Speed:   C6/I5
```

### Agregar archivos fuente

En el panel izquierdo, clic derecho en `Design` → `Add Files`:

Agregar en este orden (el orden importa):

```
1. alu.v
2. regfile.v
3. cpu_core.v
4. instruction_memory.v
5. data_memory.v
6. gpio.v
7. uart.v
8. pwm.v
9. uart_loader.v
10. microrv8_system.v
11. tang_nano_top.v
```

Agregar el archivo de restricciones:
```
12. tang_nano_9k.cst
```

### Definir módulo top

Clic derecho en `tang_nano_top.v` → `Set as Top Module`

Si aparece un triángulo amarillo al lado del archivo, el top está configurado correctamente.

### Cargar un programa en la ROM antes de sintetizar

Opción 1: editar el bloque `initial` en `instruction_memory.v` con el programa en binario.

Opción 2: descomentar `$readmemh` y asegurarse de que el `.hex` esté en el directorio del proyecto:

```verilog
// En instruction_memory.v, dentro del initial:
$readmemh("counter.hex", rom);
```

El archivo `.hex` debe estar en la misma carpeta que el proyecto Gowin, no en la carpeta de los fuentes si son directorios distintos.

### Flujo de síntesis y programación

```
Panel Flow:
  1. Synthesize     → convierte RTL a netlist lógica
                      revisar: Logic Elements < 8640, BRAM < 26
  2. Place & Route  → asigna celdas físicas y rutas
                      revisar: Timing Summary, peor slack > 0
  3. Generate Bitstream → genera archivo .fs
  4. Program Device → carga en la FPGA
```

### Interpretar el reporte de síntesis

```
Resource Usage Report:
  Logic Cells:    xxx/8640   (LUT4 + flip-flops)
  Register Cells: xxx/6693   (flip-flops puros)
  BRAM:           x/26       (bloques de 9Kbits)

MicroRV8-GT usa aproximadamente:
  Logic Cells:  800-1200
  BRAM:         1 (instruction_memory = 8Kbits)
```

Si hay errores de síntesis:
- `multiple drivers`: un wire está siendo manejado por dos always blocks → revisar data_memory.v
- `undeclared identifier`: falta incluir un archivo fuente → verificar la lista en Design
- `latch inferred`: un always @(*) no cubre todos los casos → agregar `default` al case

### Configurar el programador

```
Tools → Programmer

Si no detecta la placa:
  Cable: USB Cable
  Query/Detect

Modo de programación:
  SRAM: temporal, se borra al quitar alimentación. Usar para pruebas.
  Flash (FLASH/SRAM): permanente. Usar para despliegue final.

Verificar que el LED de la Tang Nano parpadea en verde al conectar.
```

---

## Parte 5 — Pinout manual en Gowin

### Método 1: Archivo .cst (recomendado)

El archivo `tang_nano_9k.cst` incluido en el proyecto ya tiene todos los pines. Si se necesita modificar:

```
# Sintaxis del .cst
IO_LOC "nombre_señal_en_top" numero_pin;
IO_PORT "nombre_señal_en_top" DRIVE=8 PULL_MODE=UP;

# Opciones de PULL_MODE: NONE, UP, DOWN, KEEPER
# Opciones de DRIVE: 4, 8, 12, 16 (mA)
```

### Método 2: FloorPlanner (visual)

```
Tools → FloorPlanner

En la pestaña "IO Constraint":
  - Aparece una tabla con todas las señales del top level
  - Columna "Location": escribir el número de pin (ej: 52)
  - Columna "Drive": seleccionar corriente (8mA para LEDs)
  - Columna "Pull Mode": UP para UART y botones, NONE para LEDs

Al guardar, Gowin genera el .cst automáticamente.
```

### Pinout completo de la Tang Nano 9K

```
Pin   Función                    Señal en el diseño
────  ─────────────────────────  ─────────────────
52    Oscilador 27 MHz           sys_clk
4     Botón S1 (activo bajo)     sys_rst_n
3     Botón S2 (activo bajo)     (libre)

10    LED 0 (activo bajo)        led_n[0]
11    LED 1 (activo bajo)        led_n[1]
13    LED 2 (activo bajo)        led_n[2]
14    LED 3 (activo bajo)        led_n[3]
15    LED 4 (activo bajo)        led_n[4]
16    LED 5 (activo bajo)        led_n[5]

17    UART RX (USB→FPGA)         uart_rx
18    UART TX (FPGA→USB)         uart_tx

25    Pin libre                  pwm_out

36    SPI MOSI (SD card)         (no conectado en este diseño)
37    SPI SCK
38    SPI CS
39    SPI MISO

49    HDMI D0+                   (no conectado)
50    HDMI D0-
```

### Verificar pines en el Package View

```
Tools → Package View (o FloorPlanner → Package)

Permite ver qué celdas IO están disponibles por banco.
Tang Nano 9K tiene 4 bancos de IO (voltaje configurable).
Los pines 10-18 pertenecen al banco 6 (3.3V).
```

---

## Parte 6 — Ejercicios prácticos

### Ejercicio 1 — Hola GPIO

**Objetivo:** hacer parpadear un LED a mano.

```asm
; Escribe 0x01 al GPIO, espera, escribe 0x00, repite

    ; Construir base MMIO
    ADDI r5, r0, 8
    ADDI r4, r0, 4
    SLL  r6, r5, r4     ; r6 = 0x80 = GPIO_OUT

    ; Configurar todos los pines como salida
    ADDI r3, r6, 2      ; r3 = 0x82 = GPIO_DIR
    ADDI r1, r0, -1     ; r1 = 0xFF
    STORE r1, r3, 0     ; GPIO_DIR = 0xFF (todos salida)

loop:
    ADDI r1, r0, 1
    STORE r1, r6, 0     ; GPIO_OUT = 0x01 (LED 0 encendido)
    ; delay aqui (ver patrón de delay)
    ADDI r1, r0, 0
    STORE r1, r6, 0     ; GPIO_OUT = 0x00 (LED apagado)
    ; delay aqui
    JUMP loop
```

Pregunta: ¿Cuántas instrucciones ejecuta el CPU por segundo a 27 MHz si cada instrucción toma 5 ciclos?

### Ejercicio 2 — Contador binario en LEDs

**Objetivo:** contar de 0 a 63 en los 6 LEDs.

Completar el programa:

```asm
    ADDI r1, r0, 0      ; r1 = contador

counter_loop:
    OUT  r1             ; ¿qué hace esta instrucción?
    ADDI r1, r1, 1      ; r1++
    ; agregar delay aquí
    JUMP counter_loop
```

Pregunta: ¿qué valor tiene r1 cuando llega a 256? ¿y a 257?

### Ejercicio 3 — Detectar botón

**Objetivo:** encender LED cuando se presiona el botón S2 (pin 3).

```asm
    ; GPIO_DIR = 0x00 (todos como entrada por defecto)
    ; GPIO_OUT = 0x00

    ; Construir direcciones MMIO (completar)
    ; r6 = 0x80
    ; r_in = 0x81

loop:
    LOAD  r2, r_in, 0   ; r2 = GPIO_IN
    ANDI  r2, r2, 1     ; r2 = bit 0 (botón S2 conectado a gpio_in[0])
    ; Si r2 == 0 (botón presionado, activo bajo):
    ;   encender LED
    ; Else:
    ;   apagar LED
    JUMP loop
```

Pista: necesitas BEQ y dos labels.

### Ejercicio 4 — Comunicación UART

**Objetivo:** enviar el carácter 'A' (65 = 0x41) por UART.

Problema: 65 no cabe en imm4 (máximo 15). Construir usando sumas:

```
65 = 8 * 8 + 1 = 64 + 1
64 = 8 << 3

ADDI r5, r0, 8      ; r5 = 8
ADDI r4, r0, 3      ; r4 = 3 (shift)
SLL  r1, r5, r4     ; r1 = 8 << 3 = 64
ADDI r1, r1, 1      ; r1 = 65 = 'A'
```

Completar: construir la dirección 0x83 (UART_TX) y enviar.

### Ejercicio 5 — PWM manual

**Objetivo:** poner el PWM al 50% de duty cycle.

```
PWM_DUTY = 128 = 0x80
¿Cómo construir 128 en un registro usando las instrucciones disponibles?
```

### Ejercicio 6 — Subrutina

**Objetivo:** escribir una subrutina que multiplique r1 * r2 usando sumas repetidas y guarde el resultado en r3.

```asm
; Llamar con: JAL r7, multiply
; Entradas: r1, r2
; Salida: r3

multiply:
    ADDI r3, r0, 0      ; r3 = 0 (acumulador)
    ; completar el loop de suma
    ; condición de salida: r2 decrementado hasta 0
    JUMP ???            ; retornar (limitación del ISA actual)
```

---

## Parte 7 — RISC-V Cheatsheet

### Principios RISC vs CISC

```
RISC (Reduced Instruction Set Computer)   CISC (Complex Instruction Set)
────────────────────────────────────────  ──────────────────────────────
Instrucciones de longitud fija            Instrucciones de longitud variable
Operaciones simples (1 ciclo ideal)       Operaciones complejas (múltiples ciclos)
Load/Store architecture                   Acceso directo a memoria desde ALU
Muchos registros                          Pocos registros, más modos de direccionamiento
Ejemplos: RISC-V, ARM, MIPS              Ejemplos: x86, x86-64
```

### RISC-V oficial vs MicroRV8-GT

```
Característica       RISC-V RV32I       MicroRV8-GT
──────────────────   ───────────────    ───────────────
Ancho de datos       32 bits            8 bits
Ancho de instrucción 32 bits            16 bits
Registros            32 (x0-x31)        8 (r0-r7)
PC                   32 bits            9 bits (512 posiciones)
Memoria datos        4 GB               256 bytes (128 RAM + 128 MMIO)
Inmediato            12 bits (con signo) 4 bits (con signo)
Branches             BEQ,BNE,BLT,BGE,  Solo BEQ
                     BLTU,BGEU
Jumps                JAL, JALR          JAL, JUMP (sin JALR)
Multiplicación       Extensión M        No implementada
```

### Términos clave

```
PC   — Program Counter. Registro que apunta a la siguiente instrucción a ejecutar.
IR   — Instruction Register. Guarda la instrucción mientras se procesa.
ALU  — Arithmetic Logic Unit. Circuito que realiza operaciones.
RF   — Register File. El banco de registros.
MMIO — Memory-Mapped I/O. Periféricos que se acceden como si fueran RAM.
ISA  — Instruction Set Architecture. El contrato entre software y hardware.
RTL  — Register Transfer Level. Descripción del hardware en Verilog/VHDL.
FSM  — Finite State Machine. La lógica de control del CPU.
HDL  — Hardware Description Language. Verilog, VHDL, etc.
FPGA — Field Programmable Gate Array. Chip reconfigurable.
BRAM — Block RAM. Memoria embebida en la FPGA.
LUT  — Look-Up Table. Celda básica de lógica en una FPGA.
```

### Ciclos del CPU (FSM)

```
Estado          Qué hace el hardware
──────────      ────────────────────────────────────────────────────────
S_FETCH (0)     Lee la instrucción: IR ← MEM_INSTR[PC]
S_DECODE (1)    Decodifica campos, lee registros, configura ALU
S_EXECUTE (2)   La ALU opera con los operandos, captura resultado
S_MEMORY (3)    Accede a datos (LOAD/STORE) o actualiza GPIO
S_WRITEBACK (4) Escribe resultado en registro destino, actualiza PC
```

Cada instrucción toma exactamente 5 ciclos. A 27 MHz:

```
Instrucciones por segundo = 27,000,000 / 5 = 5,400,000 = 5.4 MIPS
```

### Flags de la ALU

```
Flag      Condición de activación
────────  ────────────────────────────────────────────
zero      resultado == 0
carry     desbordamiento sin signo (suma produce bit 8)
negative  bit 7 del resultado == 1 (interpretación con signo)
```

BEQ usa el flag `zero` de la operación SUB:
- `SUB r_temp, rs1, rs2` produce zero=1 si y solo si rs1 == rs2.

---

## Parte 8 — Respuestas a ejercicios

### Ejercicio 1
Instrucciones por segundo = 27,000,000 / 5 = **5,400,000 instrucciones/seg**

### Ejercicio 2
Cuando r1 llega a 256 → overflow en 8 bits → r1 = **0** (wrap around). Con 257 → r1 = **1**.

### Ejercicio 3 — Solución

```asm
loop:
    LOAD  r2, r_in, 0
    ANDI  r2, r2, 1
    BEQ   r2, r0, btn_pressed
    JUMP  btn_released

btn_pressed:
    ADDI r1, r0, 1
    STORE r1, r6, 0     ; LED encendido
    JUMP loop

btn_released:
    ADDI r1, r0, 0
    STORE r1, r6, 0     ; LED apagado
    JUMP loop
```

### Ejercicio 4 — Solución

```asm
    ; Construir 'A' = 65
    ADDI r5, r0, 8
    ADDI r4, r0, 3
    SLL  r1, r5, r4     ; r1 = 64
    ADDI r1, r1, 1      ; r1 = 65

    ; Construir UART_TX = 0x83
    ADDI r4, r0, 4
    SLL  r6, r5, r4     ; r6 = 0x80
    ADDI r6, r6, 3      ; r6 = 0x83

    ; r7 = 0x84 = UART_STAT
    ADDI r7, r6, 1

wait:
    LOAD  r3, r7, 0
    ANDI  r3, r3, 1
    BEQ   r3, r0, send
    JUMP  wait
send:
    STORE r1, r6, 0
```

### Ejercicio 5 — Solución

```asm
; 128 = 0x80 = 8 << 4
ADDI r5, r0, 8
ADDI r4, r0, 4
SLL  r1, r5, r4     ; r1 = 128

; PWM_DUTY = 0x85
ADDI r3, r6, 5      ; (r6 = 0x80 ya calculado)
STORE r1, r3, 0     ; PWM_DUTY = 128 → 50%

; Habilitar PWM
ADDI r3, r6, 6      ; r3 = 0x86 = PWM_CTRL
ADDI r1, r0, 1
STORE r1, r3, 0     ; PWM_CTRL = 1 (enable)
```

### Ejercicio 6 — Solución

```asm
multiply:
    ADDI r3, r0, 0      ; r3 = 0 (acumulador)
    BEQ  r2, r0, mul_done
mul_loop:
    ADD  r3, r3, r1     ; r3 += r1
    ADDI r2, r2, -1     ; r2--
    BEQ  r2, r0, mul_done
    JUMP mul_loop
mul_done:
    ; retorno: guardar en main la dirección después del JAL
    ; y usar JUMP a esa dirección fija
    ; (limitación actual del ISA: no hay JALR)
    JUMP 0              ; placeholder — ajustar al usar
```
