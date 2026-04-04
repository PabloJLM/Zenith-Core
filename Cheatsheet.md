
## Cheatsheet

### Verilog

```verilog
// Módulo básico
module nombre (input wire a, output wire y);
    assign y = a;
endmodule

// Lógica combinacional con case
always @(*) begin
    case (sel)
        2'b00: y = a;
        default: y = 0;
    endcase
end

// Lógica secuencial
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) reg <= 0;
    else        reg <= siguiente_valor;
end

// Instanciar módulo
nombre_modulo instancia (.puerto(señal), ...);
```

### cocotb

```python
# Test básico
@cocotb.test()
async def test_algo(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    dut.rst_n.value = 0
    await Timer(20, units="ns")
    dut.rst_n.value = 1

    dut.entrada.value = 42
    await RisingEdge(dut.clk)

    assert dut.salida.value.integer == 42

# Leer señal
valor = dut.señal.value.integer

# Escribir señal
dut.señal.value = 0xFF

# Esperar
await Timer(10, units="ns")      # tiempo absoluto
await RisingEdge(dut.clk)        # flanco de clock

# Lanzar coroutine en paralelo
cocotb.start_soon(mi_coroutine(dut))
```

### sim_gui

```
1. Abrir sim_gui.py
2. Seleccionar directorio del proyecto
3. Modo cocotb
4. Seleccionar test .py → Top Module se llena solo
5. Clic en Todo
6. Leer log: PASS=N FAIL=0 = éxito
```
