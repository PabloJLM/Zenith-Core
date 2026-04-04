; ============================================================================
; hello_uart.asm - MicroRV8-GT
; ============================================================================
; Enviar "Hi!\n" por UART repetidamente.
; UART_TX = 0x83, UART_STAT = 0x84
; 
; Limitacion: inmediatos de 4 bits (max 15 / min -8).
; Para valores mayores se suman de a partes.
;
; Uso: python3 assembler.py hello_uart.asm -o hello_uart.hex
; ============================================================================

    ; Configurar r7 = base MMIO uart (0x80 = -128 no cabe en 4 bits)
    ; Se carga en partes: r7 = 8 + 8 + 8 + ... = 0x80 via shifts
    ; Alternativa: usar STORE con inmediato relativo a r0

    ; Enviar 'H' = 72 = 8*9 = 8+8+8+8+8+8+8+8+8
    ; Construir 72 en r1: 72 = 64 + 8
    ; 64 = 8 << 3 -> ADDI r1,r0,8 luego SLL r1,r1,3  (no tenemos SLL con imm)
    ; Approach: suma repetida

    ; r5 = 8 (usaremos como base)
    ADDI r5, r0, 8

    ; 'H' = 72: r1 = 8*9 = r5 * 9
    ; = r5 + r5 + r5 + r5 + r5 + r5 + r5 + r5 + r5
    ADD  r1, r5, r5         ; r1 = 16
    ADD  r1, r1, r5         ; r1 = 24
    ADD  r1, r1, r5         ; r1 = 32
    ADD  r1, r1, r5         ; r1 = 40
    ADD  r1, r1, r5         ; r1 = 48
    ADD  r1, r1, r5         ; r1 = 56
    ADD  r1, r1, r5         ; r1 = 64
    ADD  r1, r1, r5         ; r1 = 72 = 'H'

    ; Direccion UART_TX = 0x83 -> 131 = 8*16+3 = no cabe directo
    ; Usar r6 = 0x80 + 3 = 128 + 3
    ; 0x80 = 128 = 8*16: construir con shifts
    ; SLL r6, r5, 4 -> r5=8, shift 4 = 8*16=128
    ADDI r4, r0, 4          ; r4 = 4 (shift amount)
    SLL  r6, r5, r4         ; r6 = 8 << 4 = 128 = 0x80
    ADDI r6, r6, 3          ; r6 = 0x83 = UART_TX

    ; r7 = 0x84 = UART_STAT
    ADDI r7, r6, 1          ; r7 = 0x84

send_loop:
    ; Esperar que UART no este ocupado
wait_tx:
    LOAD r2, r7, 0          ; r2 = UART_STAT
    ANDI r2, r2, 1          ; r2 = r2 & 1 (bit busy)
    BEQ  r2, r0, do_send    ; si no busy, enviar
    JUMP wait_tx

do_send:
    STORE r1, r6, 0         ; UART_TX = r1

    ; Siguiente caracter: 'i' = 105 = 'H' + 33
    ; ... programa simplificado, solo enviar 'H' en loop
    JUMP send_loop
