# MicroRV8-GT - Instalación de Herramientas

Primer microcontrolador de 8 bits basado en RISC-V diseñado en Guatemala.

---

## Herramientas necesarias

| Herramienta | Propósito | Plataforma |
|---|---|---|
| Python 3.8+ | Assembler, scripts de soporte | Windows / Linux / macOS |
| Icarus Verilog | Simulación RTL | Windows / Linux / macOS |
| GTKWave | Visualización de waveforms | Windows / Linux / macOS |
| Gowin EDA | Síntesis para Tang Nano 9K | Windows / Linux |
| pyserial | Carga de programas via UART | Python (pip) |

---

## Python

Verificar instalación:

```
python3 --version
```

Instalar dependencias del proyecto:

```
pip install pyserial
```

---

## Icarus Verilog

### Windows

Descargar el instalador desde:

```
https://bleyer.org/icarus/
```

Buscar el archivo `iverilog-v12-x86_64-setup.exe` (o la versión más reciente).
Ejecutar el instalador y marcar la opción "Add to PATH".

Verificar:

```
iverilog -V
vvp -V
```

### Linux (Ubuntu / Debian)

```
sudo apt update
sudo apt install iverilog
```

### macOS

```
brew install icarus-verilog
```

---

## GTKWave

GTKWave es el visualizador de waveforms. La instalación puede ser complicada en Windows.
Seguir exactamente estos pasos.

### Windows

1. Ir a la página de descargas en SourceForge:

```
https://sourceforge.net/projects/gtkwave/files/
```

2. Buscar la carpeta `gtkwave-3.3.x-bin-win64` (la versión más reciente disponible).

3. Descargar el archivo `.zip`, por ejemplo:

```
gtkwave64-3.3.117-bin-win64.zip
```

4. Extraer el contenido. Quedará una carpeta con esta estructura:

```
gtkwave64\
  bin\
    gtkwave.exe    <- este es el ejecutable
    libgtk-...dll
    ...
```

5. Agregar la carpeta `bin\` al PATH del sistema:
   - Abrir "Variables de entorno del sistema"
   - En "Path" agregar: `C:\gtkwave64\bin` (ajustar según donde se extrajo)

6. Verificar en una terminal nueva:

```
gtkwave --version
```

Si no se quiere modificar el PATH, editar la variable `GTKWAVE_PATH` en `sim_gui.py`:

```python
GTKWAVE_PATH = r"C:\gtkwave64\bin\gtkwave.exe"
```

### Linux

```
sudo apt install gtkwave
```

### macOS

```
brew install --cask gtkwave
```

---

## Gowin EDA (para Tang Nano 9K)

Solo necesario si se va a sintetizar para FPGA.

1. Registrarse en el sitio de Gowin (registro gratuito):

```
https://www.gowinsemi.com/en/support/download_eda/
```

2. Descargar `Gowin EDA Education` (versión gratuita, soporta todos los FPGAs de Gowin).

3. Instalar y activar la licencia gratuita según las instrucciones del instalador.

4. En Gowin EDA, crear un proyecto nuevo:
   - Device: `GW1NR-9C`
   - Package: `QFN88`
   - Speed: `C6/I5`

---

## Verificación del entorno

Ejecutar desde la carpeta del proyecto:

```
python3 assembler.py counter.asm
iverilog -g2012 -o test.vvp alu.v regfile.v cpu_core.v instruction_memory.v data_memory.v gpio.v uart.v pwm.v uart_loader.v microrv8_system.v tb_system.v
vvp test.vvp
```

Si los tres comandos terminan sin errores, el entorno está listo.

---

## Estructura de archivos del proyecto

```
microrv8/
  alu.v                  Unidad aritmética-lógica
  regfile.v              Banco de registros (8 x 8 bits)
  cpu_core.v             Núcleo CPU (FSM de 5 estados)
  instruction_memory.v   ROM de programa (512 x 16 bits)
  data_memory.v          RAM de datos + decodificador MMIO
  gpio.v                 GPIO 8 bits bidireccional
  uart.v                 UART TX + RX + wrapper MMIO
  pwm.v                  PWM 8 bits con prescaler
  uart_loader.v          Cargador de programas via UART
  microrv8_system.v      Top level del sistema
  tang_nano_top.v        Wrapper para Tang Nano 9K
  tang_nano_9k.cst       Restricciones de pines

  assembler.py           Ensamblador de dos pasadas
  sim_gui.py             GUI para simulación
  uart_flash.py          Carga de programas a FPGA

  tb_system.v            Testbench del sistema completo
  tb_cpu.v               Testbench del CPU core

  counter.asm            Contador en GPIO
  fibonacci.asm          Secuencia Fibonacci
  hello_uart.asm         Envio de datos por UART
  pwm_demo.asm           Efecto respiración en LED
```
