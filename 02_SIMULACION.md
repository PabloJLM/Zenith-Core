# MicroRV8-GT - Simulación

Guía para simular el sistema con Icarus Verilog y visualizar waveforms en GTKWave.

---

## Flujo de simulación

```
programa.asm  ->  assembler.py  ->  program.hex
                                         |
                                instruction_memory.v ($readmemh)
                                         |
tb_system.v  +  todos los .v  ->  iverilog  ->  output.vvp
                                                     |
                                               vvp output.vvp  ->  tb_system.vcd
                                                                        |
                                                                   gtkwave tb_system.vcd
```

---

## Opción A: GUI (recomendado para comenzar)

Ejecutar la interfaz gráfica:

```
python3 sim_gui.py
```

La GUI permite:
1. Seleccionar el directorio del proyecto (detecta los archivos automáticamente).
2. Seleccionar el testbench (`tb_system.v` o `tb_cpu.v`).
3. Compilar, simular y abrir GTKWave con un clic cada uno.

El botón "Todo en uno" ejecuta los tres pasos secuencialmente.

---

## Opción B: Línea de comandos

### Compilar todos los módulos más el testbench del sistema

```
iverilog -g2012 -o output.vvp \
    alu.v regfile.v cpu_core.v \
    instruction_memory.v data_memory.v \
    gpio.v uart.v pwm.v uart_loader.v \
    microrv8_system.v \
    tb_system.v
```

### Compilar solo el CPU (testbench unitario)

```
iverilog -g2012 -o tb_cpu.vvp \
    alu.v regfile.v cpu_core.v \
    tb_cpu.v
```

### Ejecutar la simulación

```
vvp output.vvp
```

Salida esperada para el testbench del sistema:

```
=== MicroRV8-GT System Test ===
[10 ns] Reset liberado
[xxx ns] GPIO cambio #1: 0x01
[xxx ns] GPIO cambio #2: 0x02
[xxx ns] GPIO cambio #3: 0x03
...
=== Resultados ===
Cambios de GPIO detectados: 5
PASS: GPIO cambia correctamente (contador funcionando)
PASS: CPU avanza el PC
=== Fin de simulacion ===
```

### Abrir GTKWave

```
gtkwave tb_system.vcd
```

---

## Cargar un programa personalizado en simulación

### Paso 1: Ensamblar

```
python3 assembler.py fibonacci.asm -o fibonacci.hex
```

Salida del assembler:

```
Generado: fibonacci.hex (12 instrucciones)

====================================================================
MicroRV8-GT - Listado de Ensamblado
====================================================================
Dir    Hex     Binario            Instruccion
--------------------------------------------------------------------
0x000  0x0401  000_001_000_000_0001  ADDI r1, r0, 1
0x001  0x0801  000_010_000_000_0001  ADDI r2, r0, 1
...
```

### Paso 2: Compilar con el programa

Editar `instruction_memory.v` para descomentar `$readmemh`:

```verilog
initial begin
    $readmemh("fibonacci.hex", rom);
end
```

O compilar con la macro `PROGRAM_HEX`:

```
iverilog -g2012 -DPROGRAM_HEX='"fibonacci.hex"' \
    -o output.vvp \
    alu.v regfile.v cpu_core.v instruction_memory.v data_memory.v \
    gpio.v uart.v pwm.v uart_loader.v microrv8_system.v tb_system.v
```

### Paso 3: Simular

```
vvp output.vvp
```

---

## GTKWave - Señales recomendadas para agregar

Al abrir el `.vcd` en GTKWave, agregar las siguientes señales para depuración:

**CPU Core:**
- `tb_system.dut.cpu.clk`
- `tb_system.dut.cpu.rst_n`
- `tb_system.dut.cpu.state[2:0]`
- `tb_system.dut.cpu.pc[8:0]`
- `tb_system.dut.cpu.ir[15:0]`

**Registros:**
- `tb_system.dut.cpu.rf.regs[1][7:0]`
- `tb_system.dut.cpu.rf.regs[2][7:0]`
- `tb_system.dut.cpu.rf.regs[3][7:0]`

**Bus de datos:**
- `tb_system.dut.cpu.mem_addr[7:0]`
- `tb_system.dut.cpu.mem_we`
- `tb_system.dut.cpu.mem_re`

**GPIO:**
- `tb_system.dut.gpio_out[7:0]`

**Para ver los estados del FSM de forma legible en GTKWave:**
Hacer clic derecho en `state[2:0]` -> Data Format -> Decimal.

---

## Testbench del CPU unitario

El testbench `tb_cpu.v` ejecuta instrucciones individuales con ROM propia.
Útil para verificar instrucciones específicas sin el sistema completo.

```
iverilog -g2012 -o tb_cpu.vvp alu.v regfile.v cpu_core.v tb_cpu.v
vvp tb_cpu.vvp
gtkwave tb_cpu.vcd
```

---

## Tiempos de ejecución en simulación

Cada instrucción toma exactamente 5 ciclos de clock (un ciclo por estado FSM).

Con el programa de contador y delay de 15 iteraciones:
- Instrucciones por vuelta: ~9
- Ciclos por vuelta: 9 * 5 = 45 (aproximado, el delay agrega ciclos extra)
- Para ver 10 cambios de GPIO: simular al menos 5000 ciclos.

El testbench usa `CLK_FREQ = 1_000_000` para que el UART no requiera miles de ciclos.
Si se cambia el clock del sistema, ajustar este parámetro en `tb_system.v`.

---

## Cocotb (simulación avanzada)

Si se prefiere usar cocotb en lugar del testbench en Verilog:

### Instalación

```
pip install cocotb
pip install cocotb-bus
```

Verificar que `iverilog` esté en PATH (cocotb usa Icarus como simulador por defecto).

### Makefile mínimo para cocotb

Crear `Makefile` en el directorio del proyecto:

```makefile
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/alu.v $(PWD)/regfile.v $(PWD)/cpu_core.v \
                  $(PWD)/instruction_memory.v $(PWD)/data_memory.v \
                  $(PWD)/gpio.v $(PWD)/uart.v $(PWD)/pwm.v \
                  $(PWD)/uart_loader.v $(PWD)/microrv8_system.v
TOPLEVEL = microrv8_system
MODULE = test_system

include $(shell cocotb-config --makefiles)/Makefile.sim
```

Crear `test_system.py`:

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def test_counter(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.gpio_in.value = 0
    dut.uart_rx_pin.value = 1
    await Timer(100, units="ns")

    dut.rst_n.value = 1
    await Timer(50_000, units="ns")

    assert dut.gpio_out.value > 0, "GPIO debe cambiar"
```

Ejecutar:

```
make SIM=icarus
```
