; ============================================================================
; counter.asm - MicroRV8-GT
; ============================================================================
; Contador de 0-255 en GPIO con delay visible.
; Cargar en FPGA y observar los LEDs contando en binario.
;
; Uso: python3 assembler.py counter.asm -o counter.hex
; ============================================================================

    ADDI r1, r0, 0          ; r1 = 0 (contador)
    ADDI r3, r0, 15         ; r3 = 15 (limite de delay)

main_loop:
    ADDI r1, r1, 1          ; r1++
    OUT  r1                 ; GPIO = r1 (ver en LEDs)

    ; Delay interno
    ADDI r2, r0, 0          ; r2 = 0
delay_loop:
    ADDI r2, r2, 1          ; r2++
    SUB  r4, r2, r3         ; r4 = r2 - limite
    BEQ  r4, r0, delay_loop ; si r4 == 0, seguir en delay

    JUMP main_loop          ; volver a incrementar
