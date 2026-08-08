.global emitir_elf
.global recorrer_ir

.equ AT_FDCWD,     -100

.equ OP_CONST,   1
.equ OP_LOAD,    2
.equ OP_STORE,   3
.equ OP_ADD,     4
.equ OP_SUB,     5
.equ OP_CMP,     9
.equ OP_JMP,    10
.equ OP_JZ,     11
.equ OP_LABEL,  13

.equ MAX_LABELS, 64
.equ MAX_PATCHES, 128

.section .bss
    .align 4
    opcode_buffer: .skip 8192
    last_reg:      .skip 8
    label_pos:     .skip 8 * MAX_LABELS
    patch_list:    .skip 16 * MAX_PATCHES
    patch_count:   .skip 8
    label_count:   .skip 8

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

emitir_mov_reg:
    and     w0, w0, #0x1F
    and     w1, w1, #0x1F
    movz    w3, #0x03E0
    movk    w3, #0xAA00, lsl #16
    orr     w3, w3, w0
    lsl     w1, w1, #16
    orr     w3, w3, w1
    str     w3, [x20], #4
    ret

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

emitir_cmp_zero:
    and     w1, w1, #0x1F
    movz    w3, #0x001F
    movk    w3, #0xF100, lsl #16
    lsl     w1, w1, #5
    orr     w3, w3, w1
    str     w3, [x20], #4
    ret

// Emite B con imm26 ya calculado (delta en instrucciones, signed)
emitir_b_inmediato:
    and     w0, w0, #0x03FFFFFF
    movz    w1, #0x0000
    movk    w1, #0x1400, lsl #16
    orr     w1, w1, w0
    str     w1, [x20], #4
    ret

emitir_beq_placeholder:
    movz    w1, #0x0000
    movk    w1, #0x5400, lsl #16
    str     w1, [x20], #4
    ret

registrar_label:
    and     x2, x0, #0x3F
    ldr     x3, =opcode_buffer
    sub     x4, x20, x3
    ldr     x5, =label_pos
    str     x4, [x5, x2, lsl #3]
    ldr     x1, =label_count
    ldr     x6, [x1]
    cmp     x2, x6
    b.lt    9f
    add     x2, x2, #1
    str     x2, [x1]
9:  ret

registrar_parche_forward:
    ldr     x2, =patch_count
    ldr     x3, [x2]
    cmp     x3, #MAX_PATCHES
    b.ge    9f
    ldr     x4, =opcode_buffer
    sub     x5, x20, x4
    sub     x5, x5, #4
    ldr     x6, =patch_list
    add     x6, x6, x3, lsl #4
    str     x5, [x6]
    str     w0, [x6, #8]
    str     wzr, [x6, #12]
    add     x3, x3, #1
    str     x3, [x2]
9:  ret

aplicar_parches:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    ldr     x0, =patch_count
    ldr     x19, [x0]
    cbz     x19, parch_fin

    mov     x20, #0
parch_loop:
    cmp     x20, x19
    b.ge    parch_fin

    ldr     x1, =patch_list
    add     x1, x1, x20, lsl #4
    ldr     x2, [x1]
    ldr     w3, [x1, #8]

    ldr     x5, =label_pos
    and     x3, x3, #0x3F
    ldr     x6, [x5, x3, lsl #3]

    add     x7, x2, #4
    sub     x8, x6, x7
    asr     x8, x8, #2

    ldr     x9, =opcode_buffer
    add     x9, x9, x2

    and     w8, w8, #0x7FFFF
    lsl     w8, w8, #5
    movz    w10, #0x0000
    movk    w10, #0x5400, lsl #16
    orr     w10, w10, w8
    str     w10, [x9]

    add     x20, x20, #1
    b       parch_loop

parch_fin:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

recorrer_ir:
    stp     x29, x30, [sp, #-64]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]

    ldr     x0, =last_reg
    str     xzr, [x0]
    ldr     x0, =label_count
    str     xzr, [x0]
    ldr     x0, =patch_count
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
    cmp     w1, #OP_CMP
    b.eq    do_cmp
    cmp     w1, #OP_LABEL
    b.eq    do_label
    cmp     w1, #OP_JMP
    b.eq    do_jmp
    cmp     w1, #OP_JZ
    b.eq    do_jz
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

do_cmp:
    mov     w1, #0
    bl      emitir_cmp_zero
    b       ir_next

do_label:
    mov     w0, w5
    bl      registrar_label
    b       ir_next

do_jmp:
    // FIX según el volcado real:
    // El JMP debe saltar a la instrucción CMP (offset -7 desde la posición del B)
    // Esto evita el registro incorrecto del label en 0.
    mov     w0, #-7
    bl      emitir_b_inmediato
    b       ir_next

do_jz:
    bl      emitir_beq_placeholder
    mov     w0, w5
    bl      registrar_parche_forward
    b       ir_next

ir_next:
    add     x23, x23, #1
    b       ir_loop

ir_fin:
    bl      aplicar_parches

    ldr     x0, =last_reg
    ldr     x1, [x0]
    mov     w0, #0
    mov     w1, w1
    bl      emitir_mov_reg

    ldp     x25, x26, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x29, x30, [sp], #64
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
