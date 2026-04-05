; todos_encendidos.asm
; Pone GPIO = 0x3F (63) para que los 6 LEDs enciendan
; LEDs activos en bajo: led_n = ~gpio_out, entonces gpio=0x3F -> led_n=0 -> todos ON

    ADDI r1, r0, -1     ; r1 = 255 (0xFF)
main:
    OUT  r1             ; GPIO = 255, led_n = ~255 = 0 -> todos encendidos
    JUMP main