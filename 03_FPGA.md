# MicroRV8-GT - Síntesis y Programación FPGA

Guía para sintetizar el diseño en la Tang Nano 9K y programarlo.

---

## Tang Nano 9K - Especificaciones relevantes

| Característica | Valor |
|---|---|
| FPGA | Gowin GW1NR-9C |
| LUTs | 8640 |
| Block RAM | 468 Kbits |
| Clock onboard | 27 MHz |
| LEDs | 6 (activos en bajo) |
| Botones | 2 (S1 = reset, S2 libre) |
| UART USB | Integrado en placa (CH340 o similar) |

El MicroRV8-GT ocupa aproximadamente 800-1200 LUTs dependiendo del programa
en ROM y las opciones de síntesis.

---

## Flujo en Gowin EDA

### 1. Crear proyecto

Abrir Gowin EDA y seleccionar `New Project`.

Configuración:
- Project name: `microrv8gt`
- Device: `GW1NR-9C QFN88 C6/I5`
- Project series: `GW1NR`

### 2. Agregar archivos fuente

Agregar en orden (el orden importa para evitar errores de módulo no definido):

```
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
```

Agregar el archivo de restricciones:

```
tang_nano_9k.cst
```

### 3. Cargar el programa en la ROM

Antes de sintetizar, decidir qué programa se quiere en la ROM por defecto.

**Opción A: Programa hardcodeado en instruction_memory.v**

El archivo ya incluye el contador por defecto. Para cambiar el programa:

```
python3 assembler.py mi_programa.asm -o mi_programa.hex
```

Editar `instruction_memory.v` y reemplazar el bloque `initial` con:

```verilog
initial begin
    $readmemh("mi_programa.hex", rom);
end
```

Asegurarse de que el archivo `.hex` esté en el directorio del proyecto de Gowin.

**Opción B: Cargar en caliente via UART**

El `uart_loader` integrado permite cargar programas sin resintetizar.
Ver sección "Cargar programas via UART" más adelante.

### 4. Configurar top level

En Gowin EDA, verificar que `tang_nano_top` esté marcado como módulo top.
(Clic derecho en el archivo -> Set as Top Module)

### 5. Sintetizar

Hacer clic en `Synthesize` en el panel de flujo.

Verificar en el reporte:
- Sin errores críticos
- Uso de LUTs menor a 8640
- Uso de BRAM disponible (la ROM de instrucciones usa 1 BRAM de 18Kbits)

### 6. Place & Route

Hacer clic en `Place & Route`.

Si hay errores de timing, son normales a 27 MHz para este diseño.
El diseño está optimizado para funcionar sin problemas a 27 MHz.

### 7. Generar bitstream

`Generate Bitstream` produce el archivo `.fs` para programar la FPGA.

### 8. Programar

Conectar la Tang Nano 9K por USB y hacer clic en `Program Device`.

En el programador de Gowin:
- Cable: USB Cable
- Device: GW1NR-9C
- Modo: SRAM (temporal, se borra al desconectar) o Flash (permanente)

Para pruebas usar SRAM. Para despliegue final usar Flash.

---

## Verificar que funciona

Con el programa de contador por defecto:

1. Los 6 LEDs de la placa deben contar en binario.
2. El conteo va de 0 a 63 (6 bits visibles) y reinicia.
3. La velocidad del conteo depende del delay configurado en el programa.

Si los LEDs no cambian:
- Verificar que el botón S1 no esté presionado (es reset activo bajo).
- Verificar los pines en el `.cst`.
- Revisar el reporte de síntesis por advertencias en los módulos de memoria.

---

## Cargar programas via UART

El `uart_loader` permite reprogramar el CPU sin resintetizar la FPGA.
Mientras la FPGA tiene poder y la bitstream cargada, se puede cambiar
el programa infinitas veces.

### Flujo completo

```
programa.asm  ->  assembler.py --binary  ->  programa.bin
                                                   |
                                            uart_flash.py --port COM3  ->  FPGA
```

### Paso 1: Ensamblar y generar binario

```
python3 assembler.py fibonacci.asm --binary -o fibonacci.bin
```

Esto genera `fibonacci.bin` con el header de protocolo `0xAA 0x55 count_hi count_lo`
seguido de las instrucciones en big-endian.

### Paso 2: Identificar el puerto serie

En Windows, el puerto aparece en el Administrador de dispositivos como
"USB Serial Device (COMx)". Verificar:

```
python3 uart_flash.py --list
```

Salida de ejemplo:

```
Puertos disponibles:
  COM3            USB Serial Device (COM3)
```

### Paso 3: Cargar el programa

```
python3 uart_flash.py fibonacci.bin --port COM3
```

Salida:

```
Programa: fibonacci.bin
Instrucciones: 12
Bytes a enviar: 28
Puerto: COM3 @ 115200 baud
Enviando...
Listo. La FPGA deberia estar ejecutando el nuevo programa.
```

Durante la carga, los LEDs se apagan (CPU en reset por `loader_loading = 1`).
Al terminar, los LEDs deben mostrar la nueva secuencia.

### Protocolo uart_loader (referencia)

```
Byte 0: 0xAA  (sync 1)
Byte 1: 0x55  (sync 2)
Byte 2: count[8]   (bit alto del conteo, siempre 0 para programas < 256 instrucciones)
Byte 3: count[7:0] (cantidad de instrucciones)
Byte 4+5: instrucción 0 (big-endian)
Byte 6+7: instrucción 1 (big-endian)
...
```

Si se envían bytes incorrectos el loader regresa al estado de espera de sync.
Enviar `0xAA 0x55` al inicio de cualquier transmisión para garantizar sincronización.

---

## Mapa de memoria (referencia para programas)

```
Dirección  Acceso  Descripción
0x00-0x7F  R/W     RAM de 128 bytes (datos, stack)
0x80       W       GPIO_OUT - escribir en pines de salida
0x81       R       GPIO_IN  - leer pines de entrada
0x82       W       GPIO_DIR - 0=input, 1=output por pin
0x83       W       UART_TX  - byte a transmitir
0x84       R       UART_STAT- bit0 = tx_busy
0x85       W       PWM_DUTY - duty cycle 0-255
0x86       W       PWM_CTRL - bit0=enable, bit1=invert
0x87       W       PWM_PRE  - prescaler (default=105 para ~1kHz a 27MHz)
```

---

## Pinout de la Tang Nano 9K

```
Pin FPGA  Señal             Descripción
--------  ------            -----------
52        sys_clk           27 MHz oscilador
4         sys_rst_n         Botón S1 (reset activo bajo)
10        led_n[0]          LED 0 (activo bajo)
11        led_n[1]          LED 1
13        led_n[2]          LED 2
14        led_n[3]          LED 3
15        led_n[4]          LED 4
16        led_n[5]          LED 5
17        uart_rx           RX del conversor USB-UART
18        uart_tx           TX del conversor USB-UART
25        pwm_out           Salida PWM (pin libre)
```

---

## Depuración en FPGA

Si el sistema no funciona como se espera en FPGA pero sí en simulación,
los puntos más comunes a revisar:

**Problema de timing BRAM:** La instruction_memory es síncrona (un ciclo de latencia).
El CPU lee la instrucción en el ciclo siguiente al que presenta el PC. Esto es correcto
en el diseño actual porque el estado `S_FETCH` captura `instruction_in` que ya es la
salida registrada de la BRAM.

**Reset:** Verificar que `sys_rst_n` se libera correctamente. La placa tiene
pull-up interno pero se puede agregar un capacitor de 100nF en el pin de reset
para estabilizar el power-on reset.

**UART baud rate:** Verificar que el terminal serie usa 115200 8N1.
El divisor se calcula como `CLK_FREQ / BAUD_RATE = 27_000_000 / 115200 = 234`.
Si el divisor es incorrecto, la comunicación será inestable.

**GPIO:** Los LEDs de la Tang Nano 9K son activos en bajo. El top level ya invierte
la señal (`led_n = ~gpio_out_full[5:0]`). Si se conectan LEDs externos, tener en
cuenta la corriente máxima de los pines IO (8 mA por defecto en Gowin).
