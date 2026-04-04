# Laboratorios cocotb

Tareas de simulación usando cocotb 2.x + Icarus Verilog.
Las tareas guiadas tienen el código paso a paso. Las no guiadas solo tienen el objetivo y las señales relevantes.

---

## Configuración del entorno

### Instalar dependencias

```bash
pip install cocotb
```

Verificar versión (estos labs usan cocotb 2.x):

```bash
python3 -c "import cocotb; print(cocotb.__version__)"
```

Verificar que `iverilog` está en PATH:

```bash
iverilog -V
```

### Estructura de un proyecto cocotb

Cada lab tiene esta estructura mínima:

```
lab_X/
  Makefile          ← configuración del simulador
  test_modulo.py    ← tests escritos en Python
  (archivos .v del módulo a probar, copiados o con path)
```

### Opcion A — Desde sim_gui.py (recomendado, sin Make)

1. Abrir `sim_gui.py`
2. Seleccionar modo **cocotb**
3. Seleccionar el archivo `.py` del test
4. Escribir el nombre del Top Module (el modulo Verilog del DUT, ej: `alu_8bit`)
5. Clic en **Todo** o **Simular**

La GUI llama internamente al runner de cocotb sin necesidad de Makefile.

### Opcion B — Makefile (alternativa, si se prefiere terminal)

Cada lab tiene su Makefile opcional. La plantilla es:

```makefile
SIM = icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/../alu.v
TOPLEVEL = alu_8bit
MODULE = test_alu
include $(shell cocotb-config --makefiles)/Makefile.sim
```

Ejecutar:

```bash
make
```

Para limpiar:

```bash
make clean
```

### Opcion C — Runner Python directo (sin Make, desde terminal)

```python
# correr_test.py
import sys, pathlib
sys.path.insert(0, ".")
from cocotb_tools.runner import get_runner

runner = get_runner("icarus")
runner.build(
    verilog_sources=[pathlib.Path("../alu.v")],
    hdl_toplevel="alu_8bit",
    build_dir="sim_build",
    timescale=("1ns", "1ps"),
)
runner.test(
    hdl_toplevel="alu_8bit",
    test_module="test_alu",
    build_dir="sim_build",
)
```

```bash
python3 correr_test.py
```

### Estructura de un test cocotb 2.x

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

@cocotb.test()
async def nombre_del_test(dut):
    # dut = Design Under Test, acceso a señales por nombre
    dut.señal.value = valor       # escribir
    valor = dut.señal.value       # leer
    await Timer(10, units="ns")   # esperar tiempo
    await RisingEdge(dut.clk)     # esperar flanco
```

---

## Lab 1 — ALU (GUIADO)

**Módulo:** `alu.v`
**Objetivo:** verificar cada operación de la ALU y los flags zero, carry, negative.

### Configuracion

En **sim_gui.py**: modo cocotb, Top Module = `alu_8bit`, seleccionar `test_alu.py`.

Si se prefiere terminal, crear `Makefile` con `VERILOG_SOURCES=../alu.v`, `TOPLEVEL=alu_8bit`, `MODULE=test_alu`.

### test_alu.py — paso a paso

**Paso 1:** importar cocotb y definir una función auxiliar para aplicar operandos y leer resultado.

La ALU es combinacional: no tiene clock. Basta con asignar las entradas y esperar 1 ns para que los valores se propaguen.

```python
import cocotb
from cocotb.triggers import Timer

async def apply(dut, a, b, op, delay_ns=1):
    """Aplica operandos, espera propagación, retorna (result, zero, carry, negative)."""
    dut.a.value = a
    dut.b.value = b
    dut.op.value = op
    await Timer(delay_ns, units="ns")
    return (
        dut.result.value.integer,
        dut.zero.value,
        dut.carry.value,
        dut.negative.value
    )
```

**Paso 2:** test de ADD.

```python
@cocotb.test()
async def test_add(dut):
    """ADD: 5 + 3 = 8, sin carry. 200 + 100 = 300 → 44 con carry."""
    OP_ADD = 0b000

    result, zero, carry, neg = await apply(dut, 5, 3, OP_ADD)
    assert result == 8,  f"5+3 esperado 8, obtenido {result}"
    assert zero  == 0,   "5+3 no debería ser cero"
    assert carry == 0,   "5+3 no debería tener carry"
    assert neg   == 0,   "5+3 no debería ser negativo"

    # Desbordamiento sin signo: 200 + 100 = 300 = 0x12C → 8 bits bajos = 0x2C = 44
    result, zero, carry, neg = await apply(dut, 200, 100, OP_ADD)
    assert result == 44, f"200+100 truncado esperado 44, obtenido {result}"
    assert carry == 1,   "200+100 debería generar carry"

    cocotb.log.info("test_add PASS")
```

**Paso 3:** test de SUB.

```python
@cocotb.test()
async def test_sub(dut):
    """SUB: 10 - 3 = 7. 3 - 10 = underflow."""
    OP_SUB = 0b001

    result, zero, carry, neg = await apply(dut, 10, 3, OP_SUB)
    assert result == 7, f"10-3 esperado 7, obtenido {result}"
    assert zero  == 0

    # 0 - 1 = 255 en complemento a 2 de 8 bits, carry = 1 (borrow)
    result, zero, carry, neg = await apply(dut, 0, 1, OP_SUB)
    assert result == 255, f"0-1 esperado 255, obtenido {result}"
    assert neg    == 1,   "0-1 debería ser negativo"

    cocotb.log.info("test_sub PASS")
```

**Paso 4:** test del flag zero.

```python
@cocotb.test()
async def test_zero_flag(dut):
    """El flag zero debe activarse solo cuando result == 0."""
    OP_SUB = 0b001

    # 5 - 5 = 0, zero debe ser 1
    result, zero, carry, neg = await apply(dut, 5, 5, OP_SUB)
    assert result == 0, f"5-5 esperado 0, obtenido {result}"
    assert zero   == 1, "5-5 debería activar zero flag"

    # 5 - 4 = 1, zero debe ser 0
    result, zero, carry, neg = await apply(dut, 5, 4, OP_SUB)
    assert zero == 0, "5-4 no debería activar zero flag"

    cocotb.log.info("test_zero_flag PASS")
```

**Paso 5:** test de operaciones lógicas.

```python
@cocotb.test()
async def test_logical(dut):
    """AND, OR, XOR."""
    a, b = 0b10110101, 0b01101110  # 181, 110

    r_and, _, _, _ = await apply(dut, a, b, 0b010)  # AND
    r_or,  _, _, _ = await apply(dut, a, b, 0b011)  # OR
    r_xor, _, _, _ = await apply(dut, a, b, 0b100)  # XOR

    assert r_and == (a & b) & 0xFF, f"AND fallo: {r_and} != {a & b}"
    assert r_or  == (a | b) & 0xFF, f"OR  fallo: {r_or}  != {a | b}"
    assert r_xor == (a ^ b) & 0xFF, f"XOR fallo: {r_xor} != {a ^ b}"

    cocotb.log.info("test_logical PASS")
```

**Paso 6:** test de shifts.

```python
@cocotb.test()
async def test_shifts(dut):
    """SLL y SRL."""
    # SLL: 1 << 3 = 8
    r, _, _, _ = await apply(dut, 1, 3, 0b101)
    assert r == 8, f"SLL 1<<3 esperado 8, obtenido {r}"

    # SRL: 0x80 >> 3 = 0x10
    r, _, _, _ = await apply(dut, 0x80, 3, 0b110)
    assert r == 0x10, f"SRL 0x80>>3 esperado 0x10, obtenido {r}"

    # SRL no extiende signo (lógico, no aritmético)
    r, _, _, _ = await apply(dut, 0xFF, 4, 0b110)
    assert r == 0x0F, f"SRL 0xFF>>4 esperado 0x0F, obtenido {r}"

    cocotb.log.info("test_shifts PASS")
```

**Paso 7:** test de SLT (Set Less Than).

```python
@cocotb.test()
async def test_slt(dut):
    """SLT: sin signo. 3 < 5 = 1. 5 < 3 = 0. 5 < 5 = 0."""
    OP_SLT = 0b111

    r, _, _, _ = await apply(dut, 3, 5, OP_SLT)
    assert r == 1, "3 < 5 debería dar 1"

    r, _, _, _ = await apply(dut, 5, 3, OP_SLT)
    assert r == 0, "5 < 3 debería dar 0"

    r, _, _, _ = await apply(dut, 5, 5, OP_SLT)
    assert r == 0, "5 < 5 debería dar 0 (no es estrictamente menor)"

    cocotb.log.info("test_slt PASS")
```

### Ejecutar

```bash
cd lab_1_alu && make
```

Salida esperada:
```
test_add          PASS
test_sub          PASS
test_zero_flag    PASS
test_logical      PASS
test_shifts       PASS
test_slt          PASS
```

---

## Lab 2 — Register File (GUIADO)

**Módulo:** `regfile.v`
**Objetivo:** verificar escritura/lectura de registros, que r0 siempre vale 0, y el reset.

### Configuracion

En **sim_gui.py**: modo cocotb, Top Module = `regfile`, seleccionar `test_regfile.py`.

### test_regfile.py

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset(dut):
    """Aplica reset activo bajo y lo libera."""
    dut.rst_n.value = 0
    dut.rd_we.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

async def write_reg(dut, addr, data):
    """Escribe un registro en el flanco positivo."""
    dut.rd_addr.value  = addr
    dut.rd_data.value  = data
    dut.rd_we.value    = 1
    await RisingEdge(dut.clk)
    dut.rd_we.value    = 0

def read_rs1(dut, addr):
    """Lee rs1 de forma combinacional."""
    dut.rs1_addr.value = addr
    return dut.rs1_data.value.integer

def read_rs2(dut, addr):
    dut.rs2_addr.value = addr
    return dut.rs2_data.value.integer


@cocotb.test()
async def test_write_and_read(dut):
    """Escribe valores en r1-r7 y los lee de vuelta."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    test_values = {1: 0xAA, 2: 0x55, 3: 0x12, 4: 0xF0, 5: 0x0F, 6: 0xBE, 7: 0xEF}

    for reg, val in test_values.items():
        await write_reg(dut, reg, val)

    await Timer(1, units="ns")  # dejar propagar lectura combinacional

    for reg, val in test_values.items():
        got = read_rs1(dut, reg)
        assert got == val, f"r{reg}: esperado 0x{val:02X}, obtenido 0x{got:02X}"

    cocotb.log.info("test_write_and_read PASS")


@cocotb.test()
async def test_r0_always_zero(dut):
    """r0 siempre retorna 0, incluso si se intenta escribir."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # Intentar escribir a r0
    await write_reg(dut, 0, 0xFF)
    await Timer(1, units="ns")

    got = read_rs1(dut, 0)
    assert got == 0, f"r0 debe ser 0, obtenido {got}"

    got = read_rs2(dut, 0)
    assert got == 0, f"r0 (rs2) debe ser 0, obtenido {got}"

    cocotb.log.info("test_r0_always_zero PASS")


@cocotb.test()
async def test_reset_clears_all(dut):
    """Después de reset todos los registros valen 0."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # Escribir valores a todos los registros
    for r in range(1, 8):
        await write_reg(dut, r, 0xFF)

    # Aplicar reset
    dut.rst_n.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    for r in range(0, 8):
        got = read_rs1(dut, r)
        assert got == 0, f"r{r} debería ser 0 tras reset, obtenido {got}"

    cocotb.log.info("test_reset_clears_all PASS")


@cocotb.test()
async def test_dual_port_read(dut):
    """Los dos puertos de lectura son independientes."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await write_reg(dut, 1, 0xAA)
    await write_reg(dut, 2, 0x55)

    dut.rs1_addr.value = 1
    dut.rs2_addr.value = 2
    await Timer(1, units="ns")

    assert dut.rs1_data.value.integer == 0xAA
    assert dut.rs2_data.value.integer == 0x55

    cocotb.log.info("test_dual_port_read PASS")
```

---

## Lab 3 — ALU + RegFile integrados (NO GUIADO)

**Módulos:** `alu.v` + `regfile.v`
**Objetivo:** crear un testbench que simule el comportamiento de la etapa DECODE→EXECUTE del CPU sin instanciar el CPU completo.

### Qué debes implementar

Conectar el ALU y el RegFile manualmente en el test Python:

1. Escribir valores distintos en r1, r2, r3 del RegFile.
2. Leer rs1_data y rs2_data del RegFile y pasarlos como entradas al ALU.
3. Verificar que el resultado del ALU coincide con la operación esperada.
4. Probar al menos: ADD r3=r1+r2, SUB r4=r1-r2, AND, OR.

### Señales relevantes

```
RegFile:
  rs1_addr [2:0]  rs1_data [7:0]
  rs2_addr [2:0]  rs2_data [7:0]
  rd_addr  [2:0]  rd_data  [7:0]  rd_we

ALU:
  a [7:0]  b [7:0]  op [2:0]
  result [7:0]  zero  carry  negative
```

### Restricción

No puedes usar el módulo `cpu_core.v`. Los dos módulos deben instanciarse por separado en el Makefile:

```makefile
VERILOG_SOURCES = $(PWD)/../alu.v $(PWD)/../regfile.v
```

Y conectarse lógicamente en Python asignando `dut_alu.a.value = dut_rf.rs1_data.value.integer`.

### Criterio de éxito

Al menos 6 operaciones verificadas con `assert`, sin fallos.

---

## Lab 4 — GPIO (GUIADO)

**Módulo:** `gpio.v`
**Objetivo:** verificar escritura en GPIO_OUT, lectura de GPIO_IN, y configuración de GPIO_DIR.

### Configuracion

En **sim_gui.py**: modo cocotb, Top Module = `gpio_8bit`, seleccionar `test_gpio.py`.

### test_gpio.py

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

ADDR_OUT = 0x80
ADDR_IN  = 0x81
ADDR_DIR = 0x82

async def mmio_write(dut, addr, data):
    """Escribe un valor al registro MMIO del GPIO."""
    dut.mmio_addr.value    = addr
    dut.mmio_data_in.value = data
    dut.mmio_we.value      = 1
    dut.mmio_re.value      = 0
    await RisingEdge(dut.clk)
    dut.mmio_we.value      = 0

async def mmio_read(dut, addr):
    """Lee un registro MMIO del GPIO."""
    dut.mmio_addr.value = addr
    dut.mmio_we.value   = 0
    dut.mmio_re.value   = 1
    await Timer(1, units="ns")  # lectura combinacional
    val = dut.mmio_data_out.value.integer
    dut.mmio_re.value   = 0
    return val

async def reset(dut):
    dut.rst_n.value      = 0
    dut.mmio_we.value    = 0
    dut.mmio_re.value    = 0
    dut.gpio_in.value    = 0
    await Timer(20, units="ns")
    dut.rst_n.value      = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_gpio_out(dut):
    """Escribir a GPIO_OUT actualiza el pin de salida."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await mmio_write(dut, ADDR_OUT, 0xA5)
    await Timer(1, units="ns")

    got = dut.gpio_out.value.integer
    assert got == 0xA5, f"gpio_out esperado 0xA5, obtenido 0x{got:02X}"

    await mmio_write(dut, ADDR_OUT, 0x00)
    await Timer(1, units="ns")
    assert dut.gpio_out.value.integer == 0x00

    cocotb.log.info("test_gpio_out PASS")


@cocotb.test()
async def test_gpio_in(dut):
    """Leer GPIO_IN devuelve el valor de los pines físicos de entrada."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    dut.gpio_in.value = 0x3C
    val = await mmio_read(dut, ADDR_IN)
    assert val == 0x3C, f"gpio_in esperado 0x3C, obtenido 0x{val:02X}"

    dut.gpio_in.value = 0xFF
    val = await mmio_read(dut, ADDR_IN)
    assert val == 0xFF

    cocotb.log.info("test_gpio_in PASS")


@cocotb.test()
async def test_gpio_dir(dut):
    """Configurar GPIO_DIR y verificar que se almacena."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await mmio_write(dut, ADDR_DIR, 0xF0)  # pines 7-4 salida, 3-0 entrada
    await Timer(1, units="ns")

    got = dut.gpio_dir.value.integer
    assert got == 0xF0, f"gpio_dir esperado 0xF0, obtenido 0x{got:02X}"

    val = await mmio_read(dut, ADDR_DIR)
    assert val == 0xF0

    cocotb.log.info("test_gpio_dir PASS")


@cocotb.test()
async def test_reset_clears_outputs(dut):
    """Después de reset, GPIO_OUT y GPIO_DIR vuelven a 0."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await mmio_write(dut, ADDR_OUT, 0xFF)
    await mmio_write(dut, ADDR_DIR, 0xFF)

    dut.rst_n.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    assert dut.gpio_out.value.integer == 0x00, "gpio_out debe ser 0 tras reset"
    assert dut.gpio_dir.value.integer == 0x00, "gpio_dir debe ser 0 tras reset"

    cocotb.log.info("test_reset_clears_outputs PASS")
```

---

## Lab 5 — UART TX (NO GUIADO)

**Módulo:** `uart.v` (solo `uart_tx`)
**Objetivo:** verificar que `uart_tx` transmite correctamente un byte en formato 8N1.

### Qué debes implementar

Un test que:

1. Inicie la transmisión de un byte (por ejemplo `0x41` = 'A').
2. Muestree el pin `tx` cada `BAUD_DIV` ciclos de clock.
3. Verifique que los bits recibidos corresponden al protocolo 8N1:
   - Start bit: 1 bit en 0
   - 8 bits de datos (LSB primero)
   - Stop bit: 1 bit en 1
4. Reconstruya el byte y verifique que es `0x41`.
5. Verifique que `tx_busy` baja al terminar.

### Señales relevantes

```
Inputs:  clk, rst_n, data_in[7:0], tx_start
Outputs: tx_busy, tx
```

### Parámetros para simulación

Para no esperar miles de ciclos, usar un clock rápido con BAUD_DIV bajo. El módulo en `uart.v` tiene parámetros `CLK_FREQ` y `BAUD_RATE`. En Icarus, pasar parámetros via `COMPILE_ARGS` en el Makefile:

```makefile
COMPILE_ARGS += -PCLK_FREQ=100 -PBAUD_RATE=10
```

Con esto `BAUD_DIV = 100/10 = 10 ciclos por bit`. Cada frame 8N1 dura `10 * 10 = 100 ciclos`.

### Pista para muestrear bits

```python
# Esperar al centro del bit start (HALF_DIV ciclos desde el flanco de bajada)
# Luego muestrear cada BAUD_DIV ciclos para los 8 bits de datos
```

### Criterio de éxito

El byte reconstruido coincide con `data_in`. La señal `tx` vuelve a 1 (idle) al terminar.

---

## Lab 6 — PWM (NO GUIADO)

**Módulo:** `pwm.v`
**Objetivo:** verificar el duty cycle y la habilitación/deshabilitación.

### Qué debes implementar

1. Habilitar el PWM con `PWM_CTRL = 1`.
2. Configurar `PWM_DUTY = 128` (50%).
3. Medir cuántos ciclos de los 256 del período el pin `pwm_out` está en 1.
4. Verificar que es aproximadamente 128 (±2 ciclos de tolerancia).
5. Repetir con duty = 0 (siempre 0) y duty = 255 (siempre 1).
6. Verificar que con `PWM_CTRL = 0` el pin se queda en 0.

### Señales relevantes

```
MMIO:
  mmio_addr [7:0]  mmio_data_in [7:0]  mmio_we  mmio_re
  mmio_data_out [7:0]

Output:
  pwm_out
```

### Pista para medir el período

Con `PWM_PRE = 1` y clock de 100 ns, el período del PWM es `1 * 256 * 100 ns = 25600 ns`. En ese tiempo contar cuántos nanosegundos `pwm_out == 1`.

### Criterio de éxito

Duty 50% → pin en 1 durante 128/256 del período (±1%). Duty 0% → siempre 0. Duty 100% → siempre 1.

---

## Lab 7 — Data Memory (GUIADO)

**Módulo:** `data_memory.v`
**Objetivo:** verificar accesos a RAM y la separación RAM/MMIO.

### Configuracion

En **sim_gui.py**: modo cocotb, Top Module = `data_memory`, seleccionar `test_dmem.py`.

### test_dmem.py

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

async def reset(dut):
    dut.rst_n.value      = 0
    dut.we.value         = 0
    dut.re.value         = 0
    dut.mmio_data_rd.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value      = 1
    await RisingEdge(dut.clk)

async def mem_write(dut, addr, data):
    dut.addr.value    = addr
    dut.data_in.value = data
    dut.we.value      = 1
    dut.re.value      = 0
    await RisingEdge(dut.clk)
    dut.we.value      = 0

async def mem_read(dut, addr):
    dut.addr.value = addr
    dut.we.value   = 0
    dut.re.value   = 1
    await RisingEdge(dut.clk)
    dut.re.value   = 0
    await Timer(1, units="ns")
    return dut.data_out.value.integer


@cocotb.test()
async def test_ram_write_read(dut):
    """Escribir y leer posiciones de RAM (0x00-0x7F)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    test_cases = [(0x00, 0xDE), (0x10, 0xAD), (0x7F, 0xBE)]
    for addr, val in test_cases:
        await mem_write(dut, addr, val)

    for addr, val in test_cases:
        got = await mem_read(dut, addr)
        assert got == val, f"RAM[0x{addr:02X}] esperado 0x{val:02X}, obtenido 0x{got:02X}"

    cocotb.log.info("test_ram_write_read PASS")


@cocotb.test()
async def test_mmio_write_signals(dut):
    """Escribir a dirección MMIO (>=0x80) activa mmio_we y mmio_addr."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    dut.addr.value    = 0x80
    dut.data_in.value = 0x42
    dut.we.value      = 1
    dut.re.value      = 0
    await RisingEdge(dut.clk)

    # En el ciclo del flanco, mmio_we debe haberse activado
    await Timer(1, units="ns")
    assert dut.mmio_we.value     == 1,    "mmio_we debería estar activo"
    assert dut.mmio_addr.value   == 0x80, f"mmio_addr esperado 0x80"
    assert dut.mmio_data_wr.value == 0x42, f"mmio_data_wr esperado 0x42"

    dut.we.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert dut.mmio_we.value == 0, "mmio_we debe bajar cuando we=0"

    cocotb.log.info("test_mmio_write_signals PASS")


@cocotb.test()
async def test_mmio_read_passthrough(dut):
    """Leer desde MMIO retorna el valor de mmio_data_rd."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # Simular que el periférico responde con 0x7F
    dut.mmio_data_rd.value = 0x7F

    dut.addr.value = 0x84   # UART_STAT
    dut.we.value   = 0
    dut.re.value   = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")

    got = dut.data_out.value.integer
    assert got == 0x7F, f"data_out esperado 0x7F, obtenido 0x{got:02X}"

    cocotb.log.info("test_mmio_read_passthrough PASS")


@cocotb.test()
async def test_ram_does_not_affect_mmio(dut):
    """Escribir a RAM no activa mmio_we."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    await mem_write(dut, 0x20, 0xFF)  # dirección RAM
    await Timer(1, units="ns")
    assert dut.mmio_we.value == 0, "mmio_we no debe activarse en acceso a RAM"

    cocotb.log.info("test_ram_does_not_affect_mmio PASS")
```

---

## Lab 8 — CPU Core unitario (NO GUIADO)

**Módulos:** `alu.v` + `regfile.v` + `cpu_core.v`
**Objetivo:** ejecutar un programa corto instrucción por instrucción y verificar el estado del CPU después de cada una.

### Qué debes implementar

1. Crear una ROM Python (lista o diccionario) con 5-8 instrucciones codificadas.
2. En cada ciclo del clock, detectar cuándo el CPU está en estado `S_FETCH` (debug_state == 0) y presentar la instrucción correcta en `instruction_in`.
3. Ejecutar el programa completo (5 ciclos por instrucción).
4. Verificar al final:
   - El valor de `gpio_out` si el programa usa instrucción OUT.
   - El PC final si el programa termina en un JUMP.

### Instrucciones sugeridas para el programa de prueba

```python
# ADDI r1, r0, 7   → r1 = 7
# ADDI r2, r0, 3   → r2 = 3
# ADD  r3, r1, r2  → r3 = 10
# OUT  r3          → gpio_out = 10
# JUMP 0           → loop
```

Los encodings correctos están en `tb_cpu.v` como referencia.

### Señales relevantes

```
Inputs:  clk, rst_n, instruction_in[15:0], mem_rdata[7:0]
Outputs: pc_out[8:0], mem_addr[7:0], mem_we, mem_re, mem_wdata[7:0]
         gpio_out[7:0], debug_pc[7:0], debug_state[7:0], debug_instr[15:0]
```

### Pista: cómo proveer instrucciones

```python
PROG = {
    0: 0x0407,  # ADDI r1, r0, 7
    1: 0x0803,  # ADDI r2, r0, 3
    # ...
}

@cocotb.test()
async def test_program(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    # reset...

    for _ in range(50):  # N ciclos
        pc = dut.pc_out.value.integer
        dut.instruction_in.value = PROG.get(pc, 0x0000)  # NOP si no está
        await RisingEdge(dut.clk)

    assert dut.gpio_out.value.integer == 10
```

### Criterio de éxito

`gpio_out == 10` al final del programa.

---

## Lab 9 — UART Loader (NO GUIADO)

**Módulos:** `uart.v` + `uart_loader.v` + `instruction_memory.v`
**Objetivo:** simular el protocolo completo de carga de un programa via UART.

### Qué debes implementar

1. Instanciar `uart_loader` e `instruction_memory` juntos.
2. Generar los bytes del protocolo de carga en Python:
   - Header `[0xAA, 0x55]`
   - Conteo de instrucciones
   - Instrucciones en big-endian
3. Enviar cada byte simulando UART (togglear `rx` según el baud rate y el valor del byte).
4. Después de la carga, verificar:
   - `loading` bajó a 0.
   - Las instrucciones en `instruction_memory.rom` tienen los valores correctos.

### Parámetros sugeridos

Usar `CLK_FREQ` y `BAUD_RATE` con divisor pequeño para no simular millones de ciclos:

```makefile
COMPILE_ARGS += -PCLK_FREQ=100 -PBAUD_RATE=10
```

### Señales relevantes

```
uart_loader:
  rx, loading, load_done, wr_addr[8:0], wr_data[15:0], wr_en

instruction_memory:
  addr[8:0], data_out[15:0], wr_addr[8:0], wr_data[15:0], wr_en
```

### Pista para enviar un byte UART desde Python

```python
async def uart_send_byte(rx_signal, byte_val, baud_div_cycles, clk):
    """Genera la señal UART para un byte (8N1, LSB primero)."""
    bits = [0]  # start bit
    for i in range(8):
        bits.append((byte_val >> i) & 1)
    bits.append(1)  # stop bit

    for bit in bits:
        rx_signal.value = bit
        for _ in range(baud_div_cycles):
            await RisingEdge(clk)
```

### Criterio de éxito

Después de la carga, leer `instruction_memory` en las posiciones cargadas y verificar que coinciden con el programa enviado.

---

## Lab 10 — Sistema Completo (NO GUIADO)

**Módulos:** todos (`microrv8_system.v` y dependencias)
**Objetivo:** simular el sistema completo ejecutando el programa por defecto y verificar que el GPIO cuenta correctamente.

### Qué debes implementar

1. Instanciar `microrv8_system` con `CLK_FREQ` y `BAUD_RATE` reducidos.
2. Aplicar reset y liberar.
3. Correr suficientes ciclos para que el programa de contador ejecute al menos 3 iteraciones completas (incluyendo el delay).
4. Monitorear `gpio_out` con un callback `@cocotb.test` que detecte cambios.
5. Verificar que los valores de GPIO son secuenciales: 1, 2, 3, ...

### Makefile

```makefile
SIM = icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = \
    $(PWD)/../alu.v \
    $(PWD)/../regfile.v \
    $(PWD)/../cpu_core.v \
    $(PWD)/../instruction_memory.v \
    $(PWD)/../data_memory.v \
    $(PWD)/../gpio.v \
    $(PWD)/../uart.v \
    $(PWD)/../pwm.v \
    $(PWD)/../uart_loader.v \
    $(PWD)/../microrv8_system.v
TOPLEVEL = microrv8_system
MODULE = test_system
COMPILE_ARGS += -PCLK_FREQ=1000000 -PBAUD_RATE=9600
include $(shell cocotb-config --makefiles)/Makefile.sim
```

### Señales relevantes

```
Inputs:  clk, rst_n, gpio_in[7:0], uart_rx_pin
Outputs: gpio_out[7:0], gpio_dir[7:0], uart_tx_pin, pwm_pin
         debug_pc[7:0], debug_state[7:0], debug_instr[15:0]
```

### Pista: detectar cambios de GPIO

```python
gpio_values = []
prev = -1

for _ in range(N_CYCLES):
    await RisingEdge(dut.clk)
    current = dut.gpio_out.value.integer
    if current != prev:
        gpio_values.append(current)
        prev = current
```

### Criterio de éxito

La lista `gpio_values` (ignorando el primer valor 0 del reset) debe contener valores secuenciales: `[1, 2, 3, ...]` sin saltos.

---

## Lab 11 — Test paramétrico de la ALU (NO GUIADO, AVANZADO)

**Módulo:** `alu.v`
**Objetivo:** usar `@cocotb.test` con parámetros para correr cientos de casos automáticamente.

### Qué debes implementar

Usar `cocotb.parametrize` (disponible en cocotb 2.x) para generar múltiples casos de test con una sola definición.

```python
from cocotb.parametrize import parametrize

@cocotb.test()
@parametrize("a,b,op,expected", [
    (5,  3,  0b000, 8),    # ADD
    (10, 3,  0b001, 7),    # SUB
    # agregar al menos 20 casos más
])
async def test_alu_parametric(dut, a, b, op, expected):
    ...
```

### Casos a cubrir

- ADD con carry
- SUB con underflow
- AND, OR, XOR con valores de frontera (0x00, 0xFF, 0x55, 0xAA)
- SLL con shift 0 y shift 7
- SRL con shift 0 y shift 7
- SLT: a < b, a = b, a > b
- SLTI (comportamiento con bit 7 = 1, comparación sin signo)

### Criterio de éxito

Al menos 20 casos parametrizados, todos pasando.

---

## Resumen de labs

```
Lab   Módulos                      Tipo       Concepto clave
────  ───────────────────────────  ─────────  ────────────────────────────────────
1     alu.v                        Guiado     Módulo combinacional, flags
2     regfile.v                    Guiado     Módulo síncrono, reset, r0 hardwired
3     alu.v + regfile.v            No guiado  Integración de dos módulos en Python
4     gpio.v                       Guiado     Bus MMIO, lectura/escritura de registros
5     uart.v (uart_tx)             No guiado  Protocolo serie, muestreo de bits
6     pwm.v                        No guiado  Medir duty cycle en simulación
7     data_memory.v                Guiado     Decodificador de bus, RAM vs MMIO
8     cpu_core.v + alu + regfile   No guiado  CPU single-step, proveer instrucciones
9     uart_loader + imem           No guiado  Protocolo de carga completo
10    microrv8_system.v (todo)     No guiado  Sistema completo, integración final
11    alu.v                        Avanzado   Tests paramétricos automáticos
```
