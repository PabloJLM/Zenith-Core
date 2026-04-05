; ============================================================================
; fibonacci.asm - MicroRV8-GT
; ============================================================================
; Calcula secuencia de Fibonacci y saca cada valor por GPIO.
; Se reinicia cuando supera 255 (overflow en 8 bits).
;
; Uso: python3 assembler.py fibonacci.asm -o fibonacci.hex
; ============================================================================

    ADDI r1, r0, 1          ; r1 = fib(n-1) = 1
    ADDI r2, r0, 1          ; r2 = fib(n-2) = 1
    ADDI r4, r0, 15         ; r4 = delay max

fib_loop:
    ADD  r3, r1, r2         ; r3 = fib(n) = fib(n-1) + fib(n-2)
    OUT  r3                 ; GPIO = fib(n)

    ; Delay
    ADDI r5, r0, 0
delay:
    ADDI r5, r5, 1
    SUB  r6, r5, r4
    BEQ  r6, r0, delay

    ; Verificar overflow: si r3 < r2, hubo overflow (resultado menor que entrada)
    SLT  r7, r3, r2         ; r7 = 1 si r3 < r2 (overflow)
    BEQ  r7, r0, advance    ; si no overflow, continuar
    JUMP fib_loop           ; si overflow, reiniciar con r1,r2 actuales
    ; (en la proxima iteracion r3 va a ser correcto o pequeño)

advance:
    ADD  r1, r2, r0         ; r1 = r2
    ADD  r2, r3, r0         ; r2 = r3
    JUMP fib_loop
