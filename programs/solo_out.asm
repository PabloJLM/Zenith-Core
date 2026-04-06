; 3 instrucciones. Sin delay. Sin loops.
; Debe mostrar 7 (000111) en LEDs y quedarse ahi.
    ADDI r1, r0, 7
main:
    OUT  r1
    JUMP main
