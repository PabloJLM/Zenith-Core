# Micro

Primer microcontrolador de 8 bits basado en RISC-V diseñado en Guatemala.
ISA de 16 bits propia, 8 registros, periféricos MMIO, sintetizable en **Tang Nano 9K.**

---

## Inicio rápido

```
python3 sim_gui.py
```

Eso abre la GUI. Desde ahí puedes compilar, simular y cargar programas sin tocar la terminal.

---

## Estructura del repo

```
Micro/
  sim_gui.py          Abrir esto para simular
  organizar.py        Script que ordena el directorio

  rtl/                Módulos Verilog del diseño
    alu.v
    regfile.v
    cpu_core.v
    instruction_memory.v
    data_memory.v
    gpio.v
    uart.v
    pwm.v
    uart_loader.v
    microrv8_system.v
    tang_nano_top.v
    tang_nano_9k.cst

  sim/                Testbenches y waveforms
    tb_cpu.v
    tb_system.v

  tools/              Scripts Python
    assembler.py
    uart_flash.py

  programs/           Programas de ejemplo
    counter.asm / .hex
    fibonacci.asm / .hex
    hello_uart.asm / .hex
    pwm_demo.asm / .hex

  docs/               Documentación completa
    documentacion.md      Referencia de módulos, ISA y herramientas
    guia_inicial.md       Verilog y cocotb desde cero
    LABS_COCOTB.md        Laboratorios de simulación
    HT_FPGA.md            Hoja de trabajo para FPGA y Gowin

  imgs/               Capturas de pantalla de Gowin EDA
```

---

## Dependencias

| Herramienta | Para qué | Instalar |
|---|---|---|
| Python 3.8+ | assembler, sim_gui, uart_flash | python.org |
| Icarus Verilog | simulación | bleyer.org/icarus (Win) / `apt install iverilog` |
| GTKWave | ver waveforms | sourceforge.net/projects/gtkwave (Win) / `apt install gtkwave` |
| cocotb | tests en Python | `pip install cocotb` |
| pyserial | cargar programas a FPGA | `pip install pyserial` |
| Gowin EDA | síntesis para Tang Nano 9K | gowinsemi.com (registro gratuito) |

Ver `docs/documentacion.md` sección Instalación para instrucciones detalladas de cada una, incluyendo GTKWave en Windows que tiene pasos específicos.

---

## Flujos principales

### Simular un módulo

1. Abrir `sim_gui.py`
2. Modo **cocotb**, seleccionar el test `.py`, escribir el top module
3. Clic **Todo**

O con testbench Verilog:

1. Modo **Testbench Verilog**, seleccionar `sim/tb_system.v`
2. Clic **Compilar** → **Simular** → **GTKWave**

### Escribir y ensamblar un programa

```bash
python3 tools/assembler.py programs/counter.asm -o programs/counter.hex
```

### Cargar programa a la FPGA sin resintetizar

```bash
python3 tools/assembler.py mi_prog.asm --binary -o mi_prog.bin
python3 tools/uart_flash.py mi_prog.bin --port COM3
```

### Sintetizar para Tang Nano 9K

1. Abrir Gowin EDA, crear proyecto con device `GW1NR-9C QFN88 C6/I5`
2. Agregar todos los `.v` de `rtl/` y el `.cst`
3. Set as Top Module: `tang_nano_top`
4. Synthesize → Place & Route → Generate Bitstream → Program Device

Ver `docs/HT_FPGA.md` para el flujo completo con capturas.

---

## ISA resumida

8 registros (r0-r7). r0 siempre es 0. Instrucciones de 16 bits. 5 ciclos por instrucción.

```
ADDI rd, rs1, imm    rd = rs1 + imm       (imm: -8 a 7)
ADD  rd, rs1, rs2    rd = rs1 + rs2
SUB  rd, rs1, rs2    rd = rs1 - rs2
AND / OR / XOR       operaciones lógicas
SLL / SRL            shifts
SLT  rd, rs1, rs2    rd = (rs1 < rs2) ? 1 : 0
LOAD  rd, rs1, imm   rd = MEM[rs1 + imm]
STORE rs2, rs1, imm  MEM[rs1 + imm] = rs2
BEQ  rs1, rs2, lbl   salto si rs1 == rs2  (offset: -8 a 7)
JUMP label           salto absoluto       (0 a 511)
JAL  rd, label       rd = PC+1; salto
OUT  rs1             gpio_out = rs1
```

Mapa de memoria: `0x80` GPIO_OUT, `0x81` GPIO_IN, `0x82` GPIO_DIR, `0x83` UART_TX, `0x84` UART_STAT, `0x85-0x87` PWM.

---

## MMIO — CPU con los periféricos

MMIO significa Memory-Mapped I/O. 
Es la técnica por la que GPIO, UART y PWM aparecen en el mapa de memoria del CPU como si fueran RAM normal. 
El CPU usa las mismas instrucciones LOAD y STORE para todo  (no sabe ni le importa) si está leyendo un dato guardado o preguntándole el estado a un periférico.

### Por qué funciona así

La alternativa sería tener instrucciones dedicadas para cada periférico, como `IN` y `OUT` en x86. Eso obliga a extender el ISA cada vez que se agrega hardware nuevo. Con MMIO basta con asignar una dirección libre y el CPU ya sabe hablar con el periférico nuevo porque ya sabe hacer STORE y LOAD.

### Cómo lo implementa el Micro

Cuando el CPU ejecuta STORE o LOAD, genera una dirección de 8 bits. El módulo `data_memory.v` inspecciona el bit 7:

```
addr < 0x80  →  RAM física de 128 bytes, lectura/escritura normal
addr >= 0x80 →  MMIO: se activa mmio_we o mmio_re en lugar de tocar la RAM
```

En `microrv8_system.v` hay un mux que decide qué periférico recibe la señal según la dirección exacta:

```
0x80-0x82  →  gpio.v
0x83-0x84  →  uart.v
0x85-0x87  →  pwm.v
```

Cuando el CPU hace `STORE r1, r6, 3` con `r6 = 0x80`, la cadena es:

```
CPU genera addr=0x83, data=r1
  → data_memory ve bit7=1, activa mmio_we
    → microrv8_system ve addr=0x83, enruta a uart_mmio
      → uart_mmio carga el byte y arranca la transmisión serie
```

El CPU nunca supo que estaba hablando con un UART.

### Mapa de memoria completo

```
Dirección   Acceso   Periférico   Descripción
─────────   ───────  ──────────   ──────────────────────────────────────────
0x00-0x7F   R/W      RAM          128 bytes de propósito general
0x80        W        GPIO         Escribir en pines de salida
0x81        R        GPIO         Leer pines de entrada
0x82        W        GPIO         Dirección pin a pin (0=input, 1=output)
0x83        W        UART         Byte a transmitir (ignorado si tx_busy=1)
0x84        R        UART         Estado: bit0 = tx_busy
0x85        W        PWM          Duty cycle 0-255
0x86        W        PWM          Control: bit0=enable, bit1=invert
0x87        W        PWM          Prescaler de frecuencia
0x88-0xFF   —        Reservado    Para periféricos futuros
```

### Ejemplo en assembly

```asm
; Preparar base MMIO en r6 (hacer esto una vez al inicio del programa)
ADDI r5, r0, 8
ADDI r4, r0, 4
SLL  r6, r5, r4      ; r6 = 8 << 4 = 0x80

; Escribir al GPIO
ADDI r1, r0, 7
STORE r1, r6, 0      ; GPIO_OUT = 7   (0x80 + 0)

; Leer del GPIO
LOAD  r2, r6, 1      ; r2 = GPIO_IN   (0x80 + 1)

; Esperar que UART esté libre y enviar un byte
uart_wait:
LOAD  r3, r6, 4      ; r3 = UART_STAT (0x80 + 4)
ANDI  r3, r3, 1      ; r3 = bit tx_busy
BEQ   r3, r0, uart_ok
JUMP  uart_wait
uart_ok:
STORE r1, r6, 3      ; UART_TX = r1   (0x80 + 3)

; Habilitar PWM al 50%
ADDI r1, r0, 1
STORE r1, r6, 6      ; PWM_CTRL = 1   (enable)
SLL  r1, r5, r4      ; r1 = 128       (50% duty)
STORE r1, r6, 5      ; PWM_DUTY = 128 (0x80 + 5)
```

### Agregar un periférico nuevo

1. Crear el módulo `mi_periferico.v` con la interfaz MMIO estándar (`mmio_addr`, `mmio_data_in`, `mmio_we`, etc.).
2. Instanciarlo en `microrv8_system.v`.
3. Asignarle direcciones libres (por ejemplo `0x88-0x89`) en el mux de lectura.
4. Nada más. El CPU no necesita cambios.

---

## Documentación

| Archivo | Contenido |
|---|---|
| `docs/documentacion.md` | Referencia completa: ISA, módulos RTL, herramientas Python |
| `docs/ejercicios/guia_inicial.md` | Tutorial Verilog y cocotb desde cero |
| `docs/ejercicios/LABS_COCOTB.md` | 11 laboratorios guiados y no guiados |
| `docs/ejercicios/HT_FPGA.md` | Gowin EDA, pinout, ejercicios de assembly |

---

## Hardware

Tang Nano 9K — FPGA Gowin GW1NR-9C, 8640 LUTs, 27 MHz.
El diseño usa aproximadamente 1000 LUTs y 1 bloque BRAM de 9K.

LEDs muestran los 6 bits bajos de GPIO 
UART en pins 17 (RX) y 18 (TX) a 115200 baud 8N1 (creo)
PWM en pin 25. (el unico que me dejo xd)
Reset en botón S1. 
