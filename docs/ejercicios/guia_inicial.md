# Guía desde cero — Verilog, cocotb y sim_gui

Todo lo que necesitas saber para escribir módulos en Verilog, probarlos con cocotb, y correr las simulaciones desde la GUI del proyecto. Sin Make. Sin línea de comandos obligatoria.

---

## Parte 1 — Qué es Verilog y para qué sirve

**Verilog** es un lenguaje de descripcion de hardware, utilizado para diseñar y simular componentes y circuitos electronicos como compuertas, modulos, procesadores, etc..
Indicando cómo se conectan y comportan sus partes internas.

### Dos tipos de cosas en Verilog

**Lógica combinacional:** la salida depende solo de las entradas actuales. Sin memoria, sin clock. Ejemplos: una suma, un comparador, un mux.

**Lógica secuencial:** la salida depende de las entradas actuales *y del estado anterior*. Necesita un clock. Ejemplos: un contador, un registro, una FSM.

---

## Parte 2 — Estructura de un módulo Verilog

### El módulo más simple posible

```verilog
module nombre_del_modulo (
    input  wire a,      // entrada de 1 bit
    input  wire b,
    output wire y       // salida de 1 bit
);

    // lógica aquí
    assign y = a & b;   // AND

endmodule
```

Cada archivo `.v` contiene uno o más módulos. El nombre del módulo y el nombre del archivo normalmente coinciden.

### Tipos de señal

```verilog
wire        // cable, valor continuo, no almacena nada
reg         // registro, guarda un valor entre flancos de clock

// Vectores (buses):
wire [7:0]  dato;    // 8 bits, índice 7 (más significativo) a 0 (menos)
reg  [3:0]  cuenta;  // 4 bits

// El bit individual se accede así:
dato[0]     // bit menos significativo
dato[7]     // bit más significativo
dato[3:1]   // bits 3, 2, 1 (slice)
```

### Puertos de entrada y salida

```verilog
module ejemplo (
    input  wire        clk,       // 1 bit
    input  wire        rst_n,     // 1 bit, reset activo bajo
    input  wire [7:0]  dato_in,   // 8 bits de entrada
    output wire [7:0]  dato_out,  // 8 bits de salida (combinacional)
    output reg  [7:0]  resultado  // 8 bits de salida (registrado)
);
```

Regla práctica:
- `output wire` cuando el valor viene de un `assign`
- `output reg` cuando el valor se asigna dentro de un `always`

---

## Parte 3 — Lógica combinacional

### assign — el cable con lógica

```verilog
// Operaciones bit a bit
assign y = a & b;       // AND
assign y = a | b;       // OR
assign y = a ^ b;       // XOR
assign y = ~a;          // NOT

// Aritmética
assign suma = a + b;    // suma (ojo: puede desbordarse)
assign mayor = (a > b); // comparador, resultado 1 bit

// Concatenar bits
assign bus = {a, b, c};         // juntar señales
assign {carry, suma} = a + b;   // separar resultado
```

### always @(*) — lógica combinacional con case o if

Cuando la lógica es más compleja que una línea, usar `always @(*)`:

```verilog
reg [7:0] resultado;   // debe ser reg dentro de always

always @(*) begin      // @(*) = "cuando cualquier entrada cambie"
    case (opcode)
        3'b000: resultado = a + b;
        3'b001: resultado = a - b;
        3'b010: resultado = a & b;
        default: resultado = 8'h00;
    endcase
end
```

**Regla importante:** en `always @(*)` siempre cubrir todos los casos con `default`. Si no, Verilog infiere un latch (memoria no intencional).

### Ejemplo completo: mux de 4 entradas

```verilog
`default_nettype none
// Multiplexor 4:1 de 8 bits
module mux4 (
    input  wire [1:0]  sel,      // selector: 00, 01, 10, 11
    input  wire [7:0]  a, b, c, d,
    output reg  [7:0]  y
);
    always @(*) begin
        case (sel)
            2'b00: y = a;
            2'b01: y = b;
            2'b10: y = c;
            2'b11: y = d;
            default: y = 8'h00;
        endcase
    end
endmodule
`default_nettype wire
```

---

## Parte 4 — Lógica secuencial

La lógica secuencial cambia su estado en el **flanco positivo del clock** (o en el flanco negativo del reset).

### Plantilla base

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // reset: llevar todo a valores iniciales seguros
        registro <= 8'h00;
    end else begin
        // lógica normal: qué pasa en cada flanco de clock
        registro <= registro + 1;
    end
end
```

Puntos clave:
- `posedge clk` → flanco positivo (subida de 0 a 1)
- `negedge rst_n` → flanco negativo del reset (activo bajo: reset cuando vale 0)
- `<=` (non-blocking): asignación que ocurre al final del ciclo. Usar siempre dentro de `always @(posedge clk)`.
- `=` (blocking): asignación inmediata. Usar en `always @(*)`.

### Ejemplo: contador de 8 bits con reset

```verilog
`default_nettype none
module contador (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,    // solo cuenta cuando enable=1
    output reg  [7:0] count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 8'h00;          // reset
        else if (enable)
            count <= count + 8'h01;  // incrementar
        // si enable=0, count mantiene su valor (no hace nada)
    end
endmodule
`default_nettype wire
```

### Ejemplo: registro de desplazamiento (shift register)

```verilog
`default_nettype none
module shift_reg (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       data_in,   // entrada serie (1 bit)
    output wire [7:0] data_out   // salida paralela (8 bits)
);
    reg [7:0] registro;
    assign data_out = registro;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            registro <= 8'h00;
        else
            // desplazar a la izquierda, entrar por el bit 0
            registro <= {registro[6:0], data_in};
    end
endmodule
`default_nettype wire
```

---

## Parte 5 — Máquinas de estado (FSM)

Una FSM es la forma estándar de implementar control secuencial. El CPU del proyecto es una FSM de 5 estados.

### Plantilla de FSM

```verilog
`default_nettype none
module fsm_ejemplo (
    input  wire clk,
    input  wire rst_n,
    input  wire señal_entrada,
    output reg  señal_salida
);
    // Definir estados con localparams
    localparam S_IDLE    = 2'd0;
    localparam S_PROCESO = 2'd1;
    localparam S_ESPERA  = 2'd2;
    localparam S_LISTO   = 2'd3;

    reg [1:0] estado;   // registro de estado actual

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            estado        <= S_IDLE;
            señal_salida  <= 1'b0;
        end else begin
            // valor por defecto para señales de pulso
            señal_salida <= 1'b0;

            case (estado)
                S_IDLE: begin
                    if (señal_entrada)
                        estado <= S_PROCESO;
                end

                S_PROCESO: begin
                    // hacer algo
                    estado <= S_ESPERA;
                end

                S_ESPERA: begin
                    if (!señal_entrada)
                        estado <= S_LISTO;
                end

                S_LISTO: begin
                    señal_salida <= 1'b1;  // pulso de 1 ciclo
                    estado       <= S_IDLE;
                end

                default: estado <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
```

### Convenciones del proyecto

- Todos los resets son **activos en bajo** (`rst_n`, el `_n` indica negado).
- Los estados se definen con `localparam`, no con `parameter` ni defines.
- Siempre hay un caso `default` en el case de estados.
- Las señales de pulso (que duran 1 ciclo) se ponen a cero como *default* al inicio del `else`.

---

## Parte 6 — Instanciar módulos

Un módulo puede usar otro módulo adentro. A esto se le llama instanciación.

```verilog
// Instanciar el módulo 'contador' dentro de otro módulo
contador mi_contador (
    .clk    (clk),          // .puerto_del_modulo(señal_local)
    .rst_n  (rst_n),
    .enable (btn_presionado),
    .count  (valor_actual)
);
```

Regla: siempre usar conexión por nombre (`.puerto(señal)`), nunca por posición.

### Ejemplo: sistema con dos módulos

```verilog
module sistema (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led_out
);
    // señal interna que conecta los dos módulos
    wire [7:0] valor_contador;

    // instancia del contador
    contador cnt (
        .clk    (clk),
        .rst_n  (rst_n),
        .enable (1'b1),       // siempre habilitado
        .count  (valor_contador)
    );

    // los LEDs muestran el valor del contador
    assign led_out = valor_contador;
endmodule
```

---

## Parte 7 — Errores comunes en Verilog

### Multiple drivers

```verilog
// MAL: dos bloques always escriben el mismo registro
always @(posedge clk) begin
    resultado <= a + b;
end
always @(posedge clk) begin
    resultado <= a - b;  // ERROR: multiple drivers
end

// BIEN: un solo bloque con lógica interna
always @(posedge clk) begin
    if (modo == 0)
        resultado <= a + b;
    else
        resultado <= a - b;
end
```

### Latch no intencional

```verilog
// MAL: falta el default → Verilog infiere latch
always @(*) begin
    case (sel)
        2'b00: y = a;
        2'b01: y = b;
        // ¿qué pasa cuando sel=10 o 11?  → latch
    endcase
end

// BIEN: siempre cubrir todos los casos
always @(*) begin
    case (sel)
        2'b00: y = a;
        2'b01: y = b;
        default: y = 8'h00;
    endcase
end
```

### Mezclar `=` y `<=`

```verilog
// MAL: mezclar en el mismo bloque secuencial
always @(posedge clk) begin
    tmp = a + b;    // blocking → puede causar carreras
    reg <= tmp;
end

// BIEN en secuencial: solo non-blocking <=
always @(posedge clk) begin
    tmp_r <= a + b;
    reg   <= tmp_r;  // un ciclo de retardo, pero predecible
end
```

---

## Parte 8 — Qué es cocotb y cómo funciona

### El concepto

cocotb te permite escribir los tests de tu hardware en Python. En lugar de escribir otro archivo `.v` de testbench, escribes un archivo `.py`.

```
Sin cocotb:   DUT.v  +  testbench.v  →  iverilog → vvp → waveforms
Con cocotb:   DUT.v  +  test.py      →  iverilog → vvp (con hook Python) → resultados
```

El simulador sigue siendo iverilog. Lo que cocotb agrega es un puente (VPI hook) que le da control al código Python sobre el simulador: puede leer señales, escribir señales, avanzar el tiempo.

### Por qué cocotb sobre testbench en Verilog

| Testbench en Verilog | Test en cocotb |
|----------------------|----------------|
| Leer resultados es manual | `assert` directo en Python |
| Bucles y lógica son verbosos | Python puro: `for`, `if`, listas |
| Difícil generar datos aleatorios | `random`, `hypothesis`, lo que quieras |
| Un solo test monolítico | Múltiples tests aislados, fáciles de leer |
| No hay reportes automáticos | Reporta PASS/FAIL por test |

---

## Parte 9 — Estructura de un test cocotb

### El archivo base

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

@cocotb.test()
async def nombre_descriptivo(dut):
    # dut = Design Under Test
    # dut.nombre_señal accede a cualquier puerto del módulo Verilog
    pass
```

`async def` porque los tests son coroutines: pueden suspenderse para esperar eventos del simulador sin bloquear.

### Acceder a señales

```python
# Escribir (asignar valor a una entrada del DUT)
dut.clk.value   = 0
dut.rst_n.value = 1
dut.dato.value  = 0xAB     # hexadecimal
dut.bus.value   = 0b10110  # binario

# Leer (leer salida del DUT)
valor = dut.resultado.value          # objeto LogicArray
entero = dut.resultado.value.integer # convertir a int Python
bit = int(dut.flag.value)            # para señales de 1 bit
```

### Esperar tiempo

```python
# Esperar N nanosegundos (módulos combinacionales)
await Timer(10, units="ns")

# Esperar un flanco de clock (módulos secuenciales)
await RisingEdge(dut.clk)   # flanco positivo
await FallingEdge(dut.clk)  # flanco negativo

# Esperar N flancos
for _ in range(5):
    await RisingEdge(dut.clk)
```

### Generar el clock

El clock no existe en el DUT: hay que generarlo desde Python.

```python
# Crear clock de 10 ns de período (50 MHz)
cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
```

`start_soon` lanza la coroutine del clock en paralelo. El test principal continúa corriendo.

### Reset

```python
async def hacer_reset(dut):
    dut.rst_n.value = 0      # activar reset (activo bajo)
    await Timer(20, units="ns")
    dut.rst_n.value = 1      # liberar reset
    await RisingEdge(dut.clk)  # esperar primer flanco limpio
```

### Verificar con assert

```python
resultado = dut.salida.value.integer
assert resultado == 42, f"Esperado 42, obtenido {resultado}"
```

Si el assert falla, el test se marca como FAIL con el mensaje de error. Los demás tests siguen corriendo.

---

## Parte 10 — Tu primer test completo

### El módulo a probar: `contador.v`

```verilog
`default_nettype none
module contador (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    output reg  [7:0] count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 8'h00;
        else if (enable)
            count <= count + 8'h01;
    end
endmodule
`default_nettype wire
```

### El test: `test_contador.py`

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset(dut):
    """Aplica y libera el reset."""
    dut.rst_n.value  = 0
    dut.enable.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value  = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_cuenta_basica(dut):
    """El contador debe incrementarse en 1 por ciclo cuando enable=1."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    dut.enable.value = 1

    # Dejar correr 5 ciclos y verificar que cuenta 1, 2, 3, 4, 5
    for esperado in range(1, 6):
        await RisingEdge(dut.clk)
        obtenido = dut.count.value.integer
        assert obtenido == esperado, \
            f"Ciclo {esperado}: esperado {esperado}, obtenido {obtenido}"

    cocotb.log.info("test_cuenta_basica PASS")


@cocotb.test()
async def test_reset_para_el_contador(dut):
    """El reset debe llevar el contador a 0 en cualquier momento."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # Avanzar hasta 50
    dut.enable.value = 1
    for _ in range(50):
        await RisingEdge(dut.clk)

    assert dut.count.value.integer == 50, "Debería ser 50 antes del reset"

    # Aplicar reset
    dut.rst_n.value = 0
    await Timer(5, units="ns")
    assert dut.count.value.integer == 0, "Reset debería llevar count a 0"

    dut.rst_n.value = 1
    cocotb.log.info("test_reset_para_el_contador PASS")


@cocotb.test()
async def test_enable_pausa(dut):
    """Cuando enable=0 el contador no avanza."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # Contar hasta 3
    dut.enable.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)
    assert dut.count.value.integer == 3

    # Pausar por 10 ciclos
    dut.enable.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk)
    assert dut.count.value.integer == 3, \
        "El contador no debe avanzar con enable=0"

    # Reanudar
    dut.enable.value = 1
    await RisingEdge(dut.clk)
    assert dut.count.value.integer == 4

    cocotb.log.info("test_enable_pausa PASS")


@cocotb.test()
async def test_overflow(dut):
    """En 255 el contador debe volver a 0 (overflow de 8 bits)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    # Avanzar hasta 255
    dut.enable.value = 1
    for _ in range(255):
        await RisingEdge(dut.clk)
    assert dut.count.value.integer == 255

    # Un ciclo más → overflow
    await RisingEdge(dut.clk)
    assert dut.count.value.integer == 0, \
        f"Overflow: esperado 0, obtenido {dut.count.value.integer}"

    cocotb.log.info("test_overflow PASS")
```

### Correrlo desde sim_gui

1. Abrir `sim_gui.py`
2. Seleccionar el directorio donde están `contador.v` y `test_contador.py`
3. Cambiar a modo **cocotb**
4. Seleccionar `test_contador.py`
5. En **Top Module** escribir: `contador`
6. Clic en **Todo**

Salida esperada en el log:
```
[COCOTB]
  DUT:  contador
  Test: test_contador.py

Compilando 'contador'...
Ejecutando 'test_contador'...
  0.00ns  running test_contador.test_cuenta_basica (1/4)
 50.00ns  test_cuenta_basica PASS
  ...
** TESTS=4 PASS=4 FAIL=0 SKIP=0 **
```

---

## Parte 11 — Patrones de test avanzados

### Función auxiliar para operaciones repetitivas

```python
async def escribir_y_leer(dut, entrada, ciclos_espera=1):
    """Escribe una entrada, espera N ciclos, retorna la salida."""
    dut.dato_in.value = entrada
    for _ in range(ciclos_espera):
        await RisingEdge(dut.clk)
    return dut.dato_out.value.integer
```

### Monitorear cambios en una señal

```python
historial = []

# Coroutine que corre en paralelo y captura cambios
async def monitor_salida(dut, n_ciclos):
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
    cocotb.start_soon(monitor_salida(dut, 100))  # lanzar monitor en paralelo

    dut.enable.value = 1
    for _ in range(100):
        await RisingEdge(dut.clk)

    # historial tiene todos los valores distintos que tomó la señal
    assert historial[0] == 1
    assert historial[4] == 5
```

### Test con valores aleatorios

```python
import random

@cocotb.test()
async def test_aleatorio(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    for _ in range(50):
        a = random.randint(0, 255)
        b = random.randint(0, 255)

        dut.a.value = a
        dut.b.value = b
        dut.op.value = 0b000   # ADD
        await Timer(1, units="ns")

        esperado = (a + b) & 0xFF   # sumar y truncar a 8 bits
        obtenido = dut.result.value.integer
        assert obtenido == esperado, \
            f"{a} + {b} = {esperado}, DUT dijo {obtenido}"
```

### Esperar una condición (polling)

```python
async def esperar_hasta(dut, señal, valor, timeout_ciclos=1000):
    """Espera hasta que señal == valor, o falla si pasa timeout."""
    for ciclo in range(timeout_ciclos):
        if int(dut.__getattr__(señal).value) == valor:
            return ciclo   # retorna en cuántos ciclos ocurrió
        await RisingEdge(dut.clk)
    raise TimeoutError(f"'{señal}' no llegó a {valor} en {timeout_ciclos} ciclos")

@cocotb.test()
async def test_con_timeout(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    dut.start.value = 1
    ciclos = await esperar_hasta(dut, "done", 1, timeout_ciclos=100)
    cocotb.log.info(f"done se activó en {ciclos} ciclos")
```

### Loggear con niveles

```python
cocotb.log.debug("Detalle interno (no aparece a menos que level=DEBUG)")
cocotb.log.info("Mensaje informativo normal")
cocotb.log.warning("Algo inesperado pero no falla el test")
cocotb.log.error("Error grave")
```

---

## Parte 12 — Testear módulos del proyecto MicroRV8-GT

### ALU — módulo combinacional puro

La ALU no tiene clock. El patrón es: asignar entradas → esperar 1 ns → leer salida.

```python
import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def test_alu_todas_las_operaciones(dut):
    """Tabla de verdad de la ALU."""
    casos = [
        # (a,    b,    op,    resultado_esperado, zero, carry)
        (10,   3,  0b000, 13,  False, False),   # ADD
        (10,   3,  0b001,  7,  False, False),   # SUB
        ( 5,   5,  0b001,  0,  True,  False),   # SUB → zero
        (200, 100, 0b000, 44,  False, True),    # ADD con carry
        (0xFF, 0x0F, 0b010, 0x0F, False, False), # AND
        (0xF0, 0x0F, 0b011, 0xFF, False, False), # OR
    ]

    for a, b, op, esp, zero_esp, carry_esp in casos:
        dut.a.value  = a
        dut.b.value  = b
        dut.op.value = op
        await Timer(1, units="ns")

        assert dut.result.value.integer == esp, \
            f"op={op:03b} {a}+{b}: esperado {esp}, obtenido {dut.result.value.integer}"
        assert bool(dut.zero.value)  == zero_esp
        assert bool(dut.carry.value) == carry_esp
```

### RegFile — módulo secuencial simple

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def test_regfile_completo(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Reset
    dut.rst_n.value = 0
    dut.rd_we.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Escribir en todos los registros (r1-r7)
    for reg in range(1, 8):
        dut.rd_addr.value = reg
        dut.rd_data.value = reg * 10   # r1=10, r2=20, ..., r7=70
        dut.rd_we.value   = 1
        await RisingEdge(dut.clk)
    dut.rd_we.value = 0

    # Leer y verificar los dos puertos simultáneamente
    for reg in range(1, 8):
        dut.rs1_addr.value = reg
        dut.rs2_addr.value = (reg % 7) + 1  # registro diferente
        await Timer(1, units="ns")

        v1 = dut.rs1_data.value.integer
        v2 = dut.rs2_data.value.integer
        assert v1 == reg * 10, f"r{reg}: esperado {reg*10}, obtenido {v1}"

    # r0 siempre es 0
    dut.rs1_addr.value = 0
    await Timer(1, units="ns")
    assert dut.rs1_data.value.integer == 0, "r0 debe ser siempre 0"
```

### CPU Core — módulo con múltiples estados

El CPU toma 5 ciclos por instrucción. El test provee instrucciones según el PC.

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Programa: ADDI r1, r0, 7  →  OUT r1  →  JUMP 0
PROGRAMA = {
    0: 0b000_001_000_000_0111,  # ADDI r1, r0, 7
    1: 0b110_000_001_000_0000,  # OUT r1  (gpio=7)
    2: 0b111_000_000_000_0000,  # JUMP 0
}

@cocotb.test()
async def test_cpu_ejecuta_programa(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Reset
    dut.rst_n.value      = 0
    dut.mem_rdata.value  = 0
    await Timer(20, units="ns")
    dut.rst_n.value = 1

    # Correr 60 ciclos (3 instrucciones x 5 ciclos x 4 vueltas)
    for _ in range(60):
        pc = dut.pc_out.value.integer
        dut.instruction_in.value = PROGRAMA.get(pc, 0x0000)
        await RisingEdge(dut.clk)

    # GPIO debe ser 7 (el valor que OUT r1 escribe)
    gpio = dut.gpio_out.value.integer
    assert gpio == 7, f"gpio_out esperado 7, obtenido {gpio}"
    cocotb.log.info(f"CPU ejecuto programa correctamente. GPIO={gpio}")
```

---

## Parte 13 — Usar sim_gui paso a paso

### Primera vez que lo abres

```bash
python3 sim_gui.py
```

La ventana tiene estas secciones de arriba a abajo:

```
[ Directorio del proyecto          ] [...]
[ Modo: (o) Verilog  (o) cocotb        ]
[ Archivo .py / Top Module             ]
[ Estado: iverilog OK | GTKWave OK | cocotb OK ]
[ Compilar | Simular | GTKWave | Todo | Limpiar ]
[ Log --------------------------------         ]
```

### Flujo para testear un módulo nuevo

**Paso 1:** Seleccionar el directorio del proyecto (donde están los `.v`).

**Paso 2:** Cambiar a modo **cocotb**.

**Paso 3:** Clic en `...` junto a *Archivo .py* → seleccionar el test.

**Paso 4:** El campo *Top Module* se llena automáticamente si el archivo se llama `test_<modulo>.py`. Si no, escribirlo a mano (debe coincidir exactamente con el nombre del módulo en el `.v`).

**Paso 5:** Clic en **Todo**.

### Qué hace el botón "Todo" en modo cocotb

Internamente llama a la API Python de cocotb:

```
1. runner.build() →
     iverilog -g2012 -s cocotb_iverilog_dump -o sim.vvp <archivos.v>

2. runner.test() →
     vvp -M <libs_cocotb> -m libcocotbvpi_icarus sim.vvp
     → cocotb importa tu test.py y corre cada función @cocotb.test()
```

No hay Makefile. No hay comandos que recordar.

### Leer el log

```
[COCOTB]
  DUT:  alu_8bit
  Test: /ruta/test_alu.py

Compilando 'alu_8bit' con 1 archivo(s) fuente...
Ejecutando 'test_alu'...
     0.00ns INFO  running test_alu.test_add (1/6)
     1.00ns INFO  PASS: 5+3=8
     1.00ns INFO  test_alu.test_add passed
     ...
** TESTS=6 PASS=6 FAIL=0 SKIP=0 **

OK: todos los tests pasaron.
```

Si hay un fallo:

```
     1.00ns ERROR  test_alu.test_add failed
                   AssertionError: 5+3 esperado 8, obtenido 0
                   File "test_alu.py", line 12, in test_add
```

El log muestra el archivo y la línea exacta del assert que falló.

### Modo Verilog (para GTKWave)

Si quieres ver waveforms con GTKWave, usar el modo **Testbench Verilog**:

1. Seleccionar el modo Verilog.
2. Seleccionar el testbench `.v` (que debe tener `$dumpfile` y `$dumpvars`).
3. Clic en **Compilar** → **Simular** → **GTKWave**.

Los archivos `tb_system.v` y `tb_cpu.v` del proyecto ya tienen las líneas de dump incluidas.

### GTKWave en Windows

Si el botón GTKWave no hace nada, significa que no se encontró el ejecutable. Solución:

1. Descargar desde `https://sourceforge.net/projects/gtkwave/files/`
2. Buscar `gtkwave64-x.x.x-bin-win64.zip`
3. Extraer en `C:\gtkwave64\`
4. Editar `sim_gui.py`, línea `GTKWAVE_PATH`:

```python
GTKWAVE_PATH = r"C:\gtkwave64\bin\gtkwave.exe"
```

---

## Parte 14 — Escribir un módulo Verilog desde cero

Ejemplo guiado: construir un detector de flanco (edge detector).

### Especificación

Módulo que detecta cuando una señal pasa de 0 a 1 (flanco positivo). Debe producir un pulso de 1 ciclo en la salida cuando ocurre el flanco.

### Paso 1: definir la interfaz

```verilog
module edge_detector (
    input  wire clk,
    input  wire rst_n,
    input  wire señal,    // señal a monitorear
    output wire pulso     // 1 ciclo cuando señal sube de 0 a 1
);
```

### Paso 2: pensar la lógica

Para detectar un flanco positivo necesito recordar el valor anterior de la señal:
- Si `señal_anterior == 0` y `señal_actual == 1` → flanco detectado.

Eso se traduce en:
- Un registro que guarda el valor de `señal` del ciclo anterior.
- Una lógica combinacional que compara el actual con el anterior.

### Paso 3: implementar

```verilog
`default_nettype none
module edge_detector (
    input  wire clk,
    input  wire rst_n,
    input  wire señal,
    output wire pulso
);
    reg señal_r;   // valor de 'señal' en el ciclo anterior

    // Guardar el valor anterior de señal
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            señal_r <= 1'b0;
        else
            señal_r <= señal;
    end

    // Flanco: señal_r era 0 Y señal actual es 1
    assign pulso = (~señal_r) & señal;

endmodule
`default_nettype wire
```

### Paso 4: escribir el test

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def test_detecta_flanco(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.señal.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Señal en 0 → pulso debe ser 0
    await Timer(1, units="ns")
    assert int(dut.pulso.value) == 0, "Sin flanco: pulso debe ser 0"

    # Subir señal → debe detectarse el flanco en el próximo ciclo
    dut.señal.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.pulso.value) == 1, "Flanco positivo: pulso debe ser 1"

    # Siguiente ciclo: señal sigue en 1, ya no es flanco
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.pulso.value) == 0, "Sin flanco: pulso debe volver a 0"

    # Bajar señal y subir otra vez → nuevo flanco
    dut.señal.value = 0
    await RisingEdge(dut.clk)
    dut.señal.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.pulso.value) == 1, "Segundo flanco: pulso debe ser 1"

    cocotb.log.info("test_detecta_flanco PASS")

@cocotb.test()
async def test_no_detecta_flanco_negativo(dut):
    """Bajar la señal de 1 a 0 no debe generar pulso."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.señal.value = 1   # empezar en 1
    await Timer(20, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Bajar señal
    dut.señal.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.pulso.value) == 0, "Flanco negativo no debe generar pulso"

    cocotb.log.info("test_no_detecta_flanco_negativo PASS")
```

### Paso 5: correr en sim_gui

- Top Module: `edge_detector`
- Archivo: `test_edge_detector.py`
- Clic en **Todo**

---