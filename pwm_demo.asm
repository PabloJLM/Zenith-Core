; ============================================================================
; pwm_demo.asm - MicroRV8-GT
; ============================================================================
; Efecto "respiracion" en LED via PWM.
; Sube duty 0->255, baja 255->0, repite.
;
; MMIO: 0x85=PWM_DUTY  0x86=PWM_CTRL
; Nota: BEQ tiene offset de 4 bits con signo (rango [-8, 7]).
;       Saltos fuera de ese rango usan JUMP (destino absoluto 9 bits).
;
; Uso: python3 assembler.py pwm_demo.asm -o pwm_demo.hex
; ============================================================================

    ; Construir 0x80 en r6 via shift: 8 << 4 = 128 = 0x80
    ADDI r5, r0, 8
    ADDI r4, r0, 4
    SLL  r6, r5, r4         ; r6 = 0x80

    ; r3 = PWM_DUTY = 0x85
    ADDI r3, r6, 5

    ; r7 = PWM_CTRL = 0x86
    ADDI r7, r6, 6

    ; Habilitar PWM
    ADDI r1, r0, 1
    STORE r1, r7, 0

    ; r1 = duty, empieza en 0
    ADDI r1, r0, 0

fade_in:
    STORE r1, r3, 0
    ADDI  r1, r1, 1
    ADDI  r2, r0, 15
dly_in:
    ADDI  r2, r2, -1
    BEQ   r2, r0, done_in
    JUMP  dly_in
done_in:
    BEQ   r1, r0, start_out
    JUMP  fade_in

start_out:
    ADDI r1, r0, -1

fade_out:
    STORE r1, r3, 0
    ADDI  r1, r1, -1
    ADDI  r2, r0, 15
dly_out:
    ADDI  r2, r2, -1
    BEQ   r2, r0, done_out
    JUMP  dly_out
done_out:
    SLTI  r4, r1, 0
    BEQ   r4, r0, fade_out
    JUMP  fade_in
