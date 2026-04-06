# MicroRV8-GT — Tips & Tricks de Assembly

El CPU corre a 27 MHz, 6 ciclos por instrucción (BRAM síncrona).
Eso da **4.5 millones de instrucciones por segundo**.

---

## Delays calibrados

El loop de delay estándar ocupa exactamente 10 instrucciones.
El tiempo total depende de un solo número: `outer`.

```asm
; Delay configurable — cambia solo el 7 de la primera línea
    ADDI r4, r0, 7      ; <-- outer: controla el tiempo total

da_outer:
    ADDI r3, r0, 0
da_mid:
    ADDI r3, r3, -1
    ADDI r2, r0, 0
da_inner:
    ADDI r2, r2, -1
    BEQ  r2, r0, da_midc
    JUMP da_inner
da_midc:
    BEQ  r3, r0, da_outc
    JUMP da_mid
da_outc:
    ADDI r4, r4, -1
    BEQ  r4, r0, da_done
    JUMP da_outer
da_done:
```

### Tabla de tiempos

```
outer   tiempo        uso sugerido
─────   ──────────    ──────────────────────────────
  1      ~24 ms       animaciones rápidas
  4      ~97 ms       ~100ms
  7     ~170 ms       default del contador (visible claro)
 20     ~488 ms       ~500ms
 40     ~976 ms       ~1 segundo
```

### Construir valores de outer mayores que 7

El inmediato tiene rango -8 a +7. Para outer > 7, sumar en partes:

```asm
; outer = 20  (~500ms)
ADDI r4, r0, 7
ADDI r4, r4, 7
ADDI r4, r4, 6      ; r4 = 20

; outer = 40  (~1 segundo)
ADDI r4, r0, 7
ADDI r4, r4, 7
ADDI r4, r4, 7
ADDI r4, r4, 7
ADDI r4, r4, 7
ADDI r4, r4, 5      ; r4 = 40
```

### Dos delays en el mismo programa

Cada bloque de delay necesita **labels únicos**. Usar prefijos distintos:

```asm
; Primer delay con prefix da_
    ADDI r4, r0, 7
da_outer: ...
da_done:

; Segundo delay con prefix db_
    ADDI r4, r0, 20
    ADDI r4, r4, 0
db_outer: ...
db_done:
```

---

## Reglas del ensamblador

### Inmediato: rango -8 a +7

```asm
ADDI r1, r0,  7     ; máximo positivo
ADDI r1, r0, -8     ; máximo negativo
ADDI r1, r0, -1     ; r1 = 255 (0xFF)
```

Para valores fuera de ese rango construir con ADDI o SLL:

```asm
; 0x80 = 128
ADDI r5, r0, 8
ADDI r4, r0, 4
SLL  r6, r5, r4     ; r6 = 8 << 4 = 128

; 'A' = 65
ADDI r5, r0, 8
ADDI r4, r0, 3
SLL  r1, r5, r4     ; r1 = 64
ADDI r1, r1, 1      ; r1 = 65
```

### BEQ: offset limitado a -8..+7

El patrón que siempre funciona: **BEQ salta +1 sobre un JUMP, el JUMP hace los saltos largos.**

```asm
; CORRECTO
loop:
    ADDI r1, r1, -1
    BEQ  r1, r0, done   ; offset +1
    JUMP loop
done:

; ERROR — si done está a más de 7 instrucciones el ensamblador avisa:
; "Inmediato X fuera de rango [-8..15]"
```

### JUMP: destino absoluto 0-511

JUMP puede saltar a cualquier parte. No tiene límite de distancia.

### Labels se pueden usar antes de definirlos

El ensamblador hace dos pasadas. Puedes referenciar un label que aparece más abajo en el código.

---

## Patrones comunes

### Cargar constante

```asm
ADDI r1, r0, 5      ; r1 = 5
```

### Mover entre registros

```asm
ADD r2, r1, r0      ; r2 = r1
MOV r2, r1          ; pseudoinstrucción equivalente
```

### Toggle (blink)

```asm
    ADDI r1, r0, 7
main:
    OUT  r1
    XORI r1, r1, -1     ; alterna entre 7 y 248
    ; delay aquí
    JUMP main
```

### Comparaciones que no existen nativamente

```asm
; if r1 != r2
SUB  r4, r1, r2
BEQ  r4, r0, son_iguales
; aquí r1 != r2
son_iguales:

; if r1 > r2
SLT  r4, r2, r1     ; r4 = (r2 < r1)
BEQ  r4, r0, no_mayor
; aquí r1 > r2
no_mayor:
```

### Base MMIO (hacer una sola vez al inicio)

```asm
    ADDI r5, r0, 8
    ADDI r4, r0, 4
    SLL  r6, r5, r4     ; r6 = 0x80
```

### Periféricos con r6 = 0x80

```asm
STORE r1, r6, 0     ; GPIO_OUT  0x80
LOAD  r2, r6, 1     ; GPIO_IN   0x81
STORE r1, r6, 2     ; GPIO_DIR  0x82
STORE r1, r6, 3     ; UART_TX   0x83
LOAD  r3, r6, 4     ; UART_STAT 0x84
STORE r1, r6, 5     ; PWM_DUTY  0x85
STORE r1, r6, 6     ; PWM_CTRL  0x86
STORE r1, r6, 7     ; PWM_PRE   0x87
```

### Enviar byte por UART

```asm
uart_wait:
    LOAD  r3, r6, 4     ; UART_STAT
    ANDI  r3, r3, 1     ; bit0 = busy
    BEQ   r3, r0, uart_ok
    JUMP  uart_wait
uart_ok:
    STORE r1, r6, 3     ; UART_TX = r1
```

---

## LEDs activos en bajo

Los LEDs se encienden cuando el GPIO es 0, no cuando es 1.

```
OUT r1 con r1=0x00  ->  todos los LEDs encendidos
OUT r1 con r1=0xFF  ->  todos los LEDs apagados
OUT r1 con r1=0x01  ->  LED0 apagado, LEDs 1-5 encendidos
```

---

## Esqueleto de programa completo

```asm
; nombre.asm - MicroRV8-GT
; Descripcion del programa

    ; Inicializacion
    ADDI r1, r0, 0

main:
    OUT  r1

    ; logica del programa aqui
    ADDI r1, r1, 1

    ; Delay ~170ms
    ADDI r4, r0, 7
da_outer:
    ADDI r3, r0, 0
da_mid:
    ADDI r3, r3, -1
    ADDI r2, r0, 0
da_inner:
    ADDI r2, r2, -1
    BEQ  r2, r0, da_midc
    JUMP da_inner
da_midc:
    BEQ  r3, r0, da_outc
    JUMP da_mid
da_outc:
    ADDI r4, r4, -1
    BEQ  r4, r0, da_done
    JUMP da_outer
da_done:
    JUMP main
```

---

## Flujo de trabajo

```powershell
# Ensamblar
python tools/assembler.py programs/mi_prog.asm --binary -o programs/mi_prog.bin

# Cargar a la FPGA sin resintetizar
python tools/uart_flash.py programs/mi_prog.bin --port COM17
```

---

## Errores comunes

**"Inmediato fuera de rango"** — Un BEQ intenta saltar más de 7 instrucciones. Solución: usar `BEQ r, r0, +1` seguido de `JUMP destino`.

**LEDs fijos aunque hay loops** — El delay corre a millones de iteraciones por segundo y el ojo no distingue. Aumentar `outer`.

**Labels duplicados** — Si copias el bloque de delay sin cambiar los nombres, el ensamblador falla. Cambiar el prefijo (`da_` → `db_`).

**LEDs al revés de lo esperado** — Los LEDs son activos en bajo. `OUT` con r1=7 enciende los LEDs 3, 4 y 5, no el 0, 1 y 2.
