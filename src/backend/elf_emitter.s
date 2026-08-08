.global emitir_elf
.global recorrer_ir

.equ AT_FDCWD,     -100

.equ OP_CONST,   1
.equ OP_LOAD,    2
.equ OP_STORE,   3
.equ OP_ADD,     4
.equ OP_SUB,     5

.section .bss
    .align 4
    opcode_buffer: .skip 8192
    last_reg:      .skip 8

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

// MOVZ Xd, #imm16
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

// MOV Xd, Xm  ==  ORR Xd, XZR, Xm
// Encoding: 0xAA0003E0 | Rd | (Rm << 16)
emitir_mov_reg:
    and     w0, w0, #0x1F          // Rd
    and     w1, w1, #0x1F          // Rm
    movz    w3, #0x03E0
    movk    w3, #0xAA00, lsl #16   // 0xAA0003E0
    orr     w3, w3, w0             // Rd
    lsl     w1, w1, #16
    orr     w3, w3, w1             // Rm
    str     w3, [x20], #4
    ret

// ADD Xd, Xn, Xm
emitir_add_reg:
    and     w0, w0, #0x1F
    and     w1, w1, #0x1F
    and     w2, w2, #0x1F
    movz    w3, #0
    movk    w3, #0x8B00, lsl #16
    orr     w3, w3, w0
    lsl     w1, w1, #5
    orr     w3, w3, w1
    lsl     w2, w2, #16
    orr     w3, w3, w2
    str     w3, [x20], #4
    ret

// SUB Xd, Xn, Xm
emitir_sub_reg:
    and     w0, w0, #0x1F
    and     w1, w1, #0x1F
    and     w2, w2, #0x1F
    movz    w3, #0
    movk    w3, #0xCB00, lsl #16
    orr     w3, w3, w0
    lsl     w1, w1, #5
    orr     w3, w3, w1
    lsl     w2, w2, #16
    orr     w3, w3, w2
    str     w3, [x20], #4
    ret

recorrer_ir:
    stp     x29, x30, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]

    ldr     x0, =last_reg
    str     xzr, [x0]

    ldr     x21, =ir_buffer_ptr
    ldr     x21, [x21]
    cbz     x21, ir_fin

    bl      ir_count
    mov     x22, x0
    cbz     x22, ir_fin

    mov     x23, #0

ir_loop:
    cmp     x23, x22
    b.ge    ir_fin

    mov     x0, x23
    lsl     x0, x0, #3
    add     x0, x21, x0

    ldrb    w1, [x0]
    ldrb    w2, [x0, #1]
    ldrb    w3, [x0, #2]
    ldrb    w4, [x0, #3]
    ldrsw   x5, [x0, #4]

    cmp     w1, #OP_CONST
    b.eq    do_const
    cmp     w1, #OP_LOAD
    b.eq    do_load
    cmp     w1, #OP_STORE
    b.eq    do_store
    cmp     w1, #OP_ADD
    b.eq    do_add
    cmp     w1, #OP_SUB
    b.eq    do_sub
    b       ir_next

do_const:
    and     w1, w2, #0x7
    mov     w0, w5
    bl      emitir_movz_xN
    and     x1, x2, #7
    ldr     x0, =last_reg
    str     x1, [x0]
    b       ir_next

do_load:
    and     w26, w5, #0x7
    and     w25, w2, #0x7
    cmp     w25, w26
    b.eq    1f
    mov     w0, w25
    mov     w1, w26
    bl      emitir_mov_reg
1:  ldr     x0, =last_reg
    str     x25, [x0]
    b       ir_next

do_store:
    and     w25, w3, #0x7
    and     w26, w5, #0x7
    cmp     w26, w25
    b.eq    1f
    mov     w0, w26
    mov     w1, w25
    bl      emitir_mov_reg
1:  ldr     x0, =last_reg
    str     x26, [x0]
    b       ir_next

do_add:
    and     w0, w2, #0x7
    and     w1, w3, #0x7
    and     w2, w4, #0x7
    bl      emitir_add_reg
    mov     x0, x23
    lsl     x0, x0, #3
    add     x0, x21, x0
    ldrb    w1, [x0, #1]
    and     x1, x1, #7
    ldr     x0, =last_reg
    str     x1, [x0]
    b       ir_next

do_sub:
    and     w0, w2, #0x7
    and     w1, w3, #0x7
    and     w2, w4, #0x7
    bl      emitir_sub_reg
    mov     x0, x23
    lsl     x0, x0, #3
    add     x0, x21, x0
    ldrb    w1, [x0, #1]
    and     x1, x1, #7
    ldr     x0, =last_reg
    str     x1, [x0]
    b       ir_next

ir_next:
    add     x23, x23, #1
    b       ir_loop

ir_fin:
    ldr     x0, =last_reg
    ldr     x1, [x0]
    mov     w0, #0
    mov     w1, w1
    bl      emitir_mov_reg

    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

emitir_elf:
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x30, xzr, [sp, #32]

    ldr     x19, =opcode_buffer
    mov     x20, x19

    bl      recorrer_ir

    mov     w0, #93
    mov     w1, #8
    bl      emitir_movz_xN

    movz    w0, #0x0001
    movk    w0, #0xD400, lsl #16
    str     w0, [x20], #4

    sub     x25, x20, x19

    mov     x5, #120
    add     x5, x5, x25
    ldr     x6, =program_header
    str     x5, [x6, #32]
    str     x5, [x6, #40]

    mov     x0, AT_FDCWD
    ldr     x1, =archivo_salida
    mov     x2, #577
    mov     x3, #493
    mov     x8, #56
    svc     #0
    mov     x22, x0

    mov     x0, x22
    ldr     x1, =elf_header
    mov     x2, #64
    mov     x8, #64
    svc     #0

    mov     x0, x22
    ldr     x1, =program_header
    mov     x2, #56
    mov     x8, #64
    svc     #0

    mov     x0, x22
    mov     x1, x19
    mov     x2, x25
    mov     x8, #64
    svc     #0

    mov     x0, x22
    mov     x8, #57
    svc     #0

    ldp     x30, xzr, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #48
    ret
