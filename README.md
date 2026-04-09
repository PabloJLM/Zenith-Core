# Micro

Primer microcontrolador de 8 bits basado en RISC-V diseñado en Guatemala.
ISA de 16 bits propia, 8 registros, periféricos MMIO, sintetizable en **Tang Nano 9K.**

---

## Inicio rápido

```
python3 sim_gui.py
```

Abre la GUI. Desde ahí puedes compilar, simular y cargar programas sin tocar la terminal.

Para editar y flashear programas desde un IDE:

```
python3 JoJoP_IDE.py
```

---

## Estructura del repo

```
Micro/
  sim_gui.py              Simulador con GUI
  JoJoP_IDE.py            IDE para escribir y flashear programas

  rtl/                    Módulos Verilog del diseño
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

  sim/                    Testbenches
    tb_cpu.v
    tb_system.v

  tools/                  Scripts Python
    assembler.py
    uart_flash.py

  programs/               Programas de ejemplo
    todos_encendidos.asm / .bin
    solo_out.asm / .bin
    blink_min.bin
    default_via_uart.bin
    hello_uart.asm
    pwm_demo.asm

  docs/
    documentacion.md      Referencia completa: ISA, módulos RTL, herramientas
    Instalacion.md        Instalación de todas las herramientas
    FPGA.md               Síntesis y programación en Gowin EDA
    ejercicios/
      guia_inicial.md     Verilog y cocotb desde cero + flujo de simulación
      LABS_COCOTB.md      11 laboratorios de simulación
      HT_FPGA.md          Hoja de trabajo FPGA y assembly
```

---

## Dependencias

| Herramienta | Para qué | Instalar |
|---|---|---|
| Python 3.8+ | assembler, sim_gui, uart_flash | python.org |
| PyQt5 | JoJoP_IDE | `pip install PyQt5` |
| Icarus Verilog | simulación | bleyer.org/icarus (Win) / `apt install iverilog` |
| GTKWave | ver waveforms | sourceforge.net/projects/gtkwave (Win) / `apt install gtkwave` |
| cocotb | tests en Python | `pip install cocotb` |
| pyserial | cargar programas a FPGA | `pip install pyserial` |
| Gowin EDA | síntesis para Tang Nano 9K | gowinsemi.com |

Ver `docs/Instalacion.md` para instrucciones detalladas de cada herramienta.

---

## Flujos principales

### Escribir y flashear un programa

```bash
python3 JoJoP_IDE.py
# Escribir el .asm, compilar a .bin, seleccionar puerto, Flash
```

### Ensamblar desde terminal

```bash
python3 tools/assembler.py programs/counter.asm -o programs/counter.hex
python3 tools/assembler.py mi_prog.asm --binary -o mi_prog.bin
python3 tools/uart_flash.py mi_prog.bin --port COM3
```

### Simular

```bash
python3 sim_gui.py
# Modo cocotb: seleccionar test .py, escribir top module, clic Todo
# Modo Verilog: seleccionar tb_system.v, Compilar > Simular > GTKWave
```

### Sintetizar para Tang Nano 9K

1. Abrir Gowin EDA, crear proyecto con device `GW1NR-9C QFN88 C6/I5`
2. Agregar todos los `.v` de `rtl/` y el `.cst`
3. Set as Top Module: `tang_nano_top`
4. Synthesize → Place & Route → Generate Bitstream → Program Device

Ver `docs/FPGA.md` para el flujo completo.

---

## ISA resumida

8 registros (r0-r7). r0 siempre es 0. Instrucciones de 16 bits. 6 ciclos por instrucción.

```
ADDI rd, rs1, imm    rd = rs1 + imm       (imm: -8 a 7)
ADD  rd, rs1, rs2    rd = rs1 + rs2
SUB  rd, rs1, rs2    rd = rs1 - rs2
AND / OR / XOR       operaciones lógicas
SLL / SRL            shifts
SLT  rd, rs1, rs2    rd = (rs1 < rs2) ? 1 : 0
LOAD  rd, rs1, imm   rd = MEM[rs1 + imm]
STORE rs2, rs1, imm  MEM[rs1 + imm] = rs2
BEQ  rs1, rs2, lbl   salto si rs1 == rs2
JUMP label           salto absoluto (0 a 511)
JAL  rd, label       rd = PC+1; salto
OUT  rs1             gpio_out = rs1
```

Mapa MMIO: `0x80` GPIO_OUT, `0x81` GPIO_IN, `0x82` GPIO_DIR, `0x83` UART_TX, `0x84` UART_STAT, `0x85-0x87` PWM.

Ver `docs/documentacion.md` para la referencia completa.

---

## Hardware

Tang Nano 9K — FPGA Gowin GW1NR-9C, 8640 LUTs, 27 MHz.
El diseño usa aproximadamente 1000 LUTs y 1 bloque BRAM de 9K.

LEDs muestran los 6 bits bajos de GPIO (activos en bajo).
UART en pins 17 (RX) y 18 (TX) a 115200 baud 8N1.
PWM en pin 25.
Reset en botón S1.
