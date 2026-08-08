.global emitir_elf

.equ AT_FDCWD, -100

.section .bss
    .align 4
    opcode_buffer: .skip 8192

.section .data
    .align 4
    archivo_salida: .string "salida.out"
    elf_header:
        .byte 0x7F, 0x45, 0x4C, 0x46
        .byte 0x02, 0x01, 0x01, 0x00
        .skip 8
        .short 2
        .short 183
        .word 1
        .quad 0x400078
        .quad 64
        .quad 0
        .word 0
        .short 64
        .short 56
        .short 1
        .short 0, 0, 0
    program_header:
        .word 1
        .word 5
        .quad 0
        .quad 0x400000
        .quad 0x400000
        .quad 0
        .quad 0
        .quad 0x10000

.section .text

// MOVZ xRd, #imm16
// w0 = imm16, w1 = Rd
emitir_movz_xN:
    and     w0, w0, #0xFFFF
    and     w1, w1, #0x1F
    movz    w2, #0
    movk    w2, #0xD280, lsl #16
    orr     w2, w2, w1
    lsl     w0, w0, #5
    orr     w2, w2, w0
    str     w2, [x20], #4
    ret

emitir_elf:
    stp     x19, x20, [sp, #-32]!
    stp     x30, xzr, [sp, #16]

    ldr     x19, =opcode_buffer
    mov     x20, x19

    // ── Secuencia mínima hardcodeada ──────────────────────
    // movz x0, #42
    mov     w0, #42
    mov     w1, #0
    bl      emitir_movz_xN

    // movz x8, #93          (SYS_exit)
    mov     w0, #93
    mov     w1, #8
    bl      emitir_movz_xN

    // svc #0
    movz    w0, #0x0001
    movk    w0, #0xD400, lsl #16
    str     w0, [x20], #4

    // ── Tamaño del código ─────────────────────────────────
    sub     x25, x20, x19           // = 12 bytes

    // Actualizar program_header
    mov     x5, #120
    add     x5, x5, x25
    ldr     x6, =program_header
    str     x5, [x6, #32]           // p_filesz
    str     x5, [x6, #40]           // p_memsz

    // openat
    mov     x0, AT_FDCWD
    ldr     x1, =archivo_salida
    mov     x2, #577
    mov     x3, #493
    mov     x8, #56
    svc     #0
    mov     x22, x0

    // write ELF header
    mov     x0, x22
    ldr     x1, =elf_header
    mov     x2, #64
    mov     x8, #64
    svc     #0

    // write program header
    mov     x0, x22
    ldr     x1, =program_header
    mov     x2, #56
    mov     x8, #64
    svc     #0

    // write code
    mov     x0, x22
    mov     x1, x19
    mov     x2, x25
    mov     x8, #64
    svc     #0

    // close
    mov     x0, x22
    mov     x8, #57
    svc     #0

    ldp     x30, xzr, [sp, #16]
    ldp     x19, x20, [sp], #32
    ret
