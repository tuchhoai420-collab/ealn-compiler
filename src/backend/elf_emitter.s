.global emitir_elf

.equ AT_FDCWD,     -100
.equ AST_VAR_DECL, 100
.equ AST_ASSIGN,   101
.equ AST_WHILE,    102

// IR opcodes
.equ OP_CONST,   1
.equ OP_LOAD,    2
.equ OP_STORE,   3
.equ OP_ADD,     4
.equ OP_SUB,     5
.equ OP_MUL,     6
.equ OP_DIV,     7
.equ OP_NEG,     8

.section .bss
    .align 4
    opcode_buffer: .skip 8192
    reg_name_start: .skip 32
    reg_name_len:   .skip 32

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

// ADD Xd, Xn, Xm
emitir_add_reg:
    and     w0, w0, #0x1F          // Rd
    and     w1, w1, #0x1F          // Rn
    and     w2, w2, #0x1F          // Rm
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

// MUL Xd, Xn, Xm
emitir_mul_reg:
    and     w0, w0, #0x1F
    and     w1, w1, #0x1F
    and     w2, w2, #0x1F
    movz    w3, #0x7C00
    movk    w3, #0x9B00, lsl #16
    orr     w3, w3, w0
    lsl     w1, w1, #5
    orr     w3, w3, w1
    lsl     w2, w2, #16
    orr     w3, w3, w2
    str     w3, [x20], #4
    ret

// SDIV Xd, Xn, Xm
emitir_sdiv_reg:
    and     w0, w0, #0x1F
    and     w1, w1, #0x1F
    and     w2, w2, #0x1F
    movz    w3, #0x0C00
    movk    w3, #0x9AC0, lsl #16
    orr     w3, w3, w0
    lsl     w1, w1, #5
    orr     w3, w3, w1
    lsl     w2, w2, #16
    orr     w3, w3, w2
    str     w3, [x20], #4
    ret

// NEG Xd, Xm  (SUB Xd, XZR, Xm)
emitir_neg_reg:
    and     w0, w0, #0x1F          // Rd
    and     w1, w1, #0x1F          // Rm
    movz    w3, #0
    movk    w3, #0xCB00, lsl #16
    orr     w3, w3, w0
    // Rn = 31 (XZR)
    mov     w2, #31
    lsl     w2, w2, #5
    orr     w3, w3, w2
    lsl     w1, w1, #16
    orr     w3, w3, w1
    str     w3, [x20], #4
    ret

// SUB Xd, Xd, #imm12
emitir_sub_imm:
    and     w0, w0, #0x1F
    mov     w3, #0xFFF
    and     w1, w1, w3
    movz    w2, #0
    movk    w2, #0xD100, lsl #16
    orr     w2, w2, w0
    lsl     w4, w0, #5
    orr     w2, w2, w4
    lsl     w1, w1, #10
    orr     w2, w2, w1
    str     w2, [x20], #4
    ret

// ADD Xd, Xd, #imm12
emitir_add_imm:
    and     w0, w0, #0x1F
    mov     w3, #0xFFF
    and     w1, w1, w3
    movz    w2, #0
    movk    w2, #0x9100, lsl #16
    orr     w2, w2, w0
    lsl     w4, w0, #5
    orr     w2, w2, w4
    lsl     w1, w1, #10
    orr     w2, w2, w1
    str     w2, [x20], #4
    ret

// CMP Xn, #0
emitir_cmp0:
    and     w0, w0, #0x1F
    movz    w2, #0x001F
    movk    w2, #0xF100, lsl #16
    lsl     w0, w0, #5
    orr     w2, w2, w0
    str     w2, [x20], #4
    ret

patch_beq:
    movz    w3, #0xFFFF
    movk    w3, #0x7, lsl #16
    and     w0, w0, w3
    movz    w2, #0
    movk    w2, #0x5400, lsl #16
    lsl     w0, w0, #5
    orr     w2, w2, w0
    str     w2, [x1]
    ret

emitir_beq_placeholder:
    movz    w2, #0
    movk    w2, #0x5400, lsl #16
    str     w2, [x20], #4
    ret

emitir_b:
    movz    w3, #0xFFFF
    movk    w3, #0x3FF, lsl #16
    and     w0, w0, w3
    movz    w2, #0
    movk    w2, #0x1400, lsl #16
    orr     w2, w2, w0
    str     w2, [x20], #4
    ret

find_reg_by_name:
    stp     x30, xzr, [sp, #-32]!
    stp     x22, x23, [sp, #16]
    mov     x22, x0
    mov     x23, x1
    mov     x9, #0
1:  cmp     x9, #8
    b.ge    9f
    ldr     x0, =reg_name_len
    ldr     w1, [x0, x9, lsl #2]
    cbz     w1, 9f
    cmp     x1, x23
    b.ne    2f
    ldr     x0, =reg_name_start
    ldr     w2, [x0, x9, lsl #2]
    ldr     x4, =fuente_ptr
    ldr     x4, [x4]
    add     x0, x4, x22
    add     x2, x4, x2
    mov     x1, x23
3:  cbz     x1, 4f
    ldrb    w5, [x0], #1
    ldrb    w6, [x2], #1
    cmp     w5, w6
    b.ne    2f
    sub     x1, x1, #1
    b       3b
4:  mov     w0, w9
    ldp     x22, x23, [sp, #16]
    ldp     x30, xzr, [sp], #32
    ret
2:  add     x9, x9, #1
    b       1b
9:  mov     w0, #0xFF
    ldp     x22, x23, [sp, #16]
    ldp     x30, xzr, [sp], #32
    ret

// ─────────────────────────────────────────────────────────────
// Recorrido del IR + emisión real
// x20 es el puntero de emisión vivo (no se restaura)
// ─────────────────────────────────────────────────────────────
recorrer_ir:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x21, [sp, #16]

    ldr     x19, =ir_buffer_ptr
    ldr     x19, [x19]
    cbz     x19, ir_fin
    ldr     x21, =ir_instr_count
    ldr     x21, [x21]
    cbz     x21, ir_fin

    mov     x2, #0
ir_loop:
    cmp     x2, x21
    b.ge    ir_fin

    mov     x0, x2
    lsl     x0, x0, #3
    add     x0, x19, x0

    ldrb    w1, [x0]                    // op
    ldrb    w3, [x0, #1]                // dest
    ldrb    w4, [x0, #2]                // src1
    ldrb    w5, [x0, #3]                // src2
    ldr     w6, [x0, #4]                // imm

    // limitar registros a 0-7
    and     w3, w3, #7
    and     w4, w4, #7
    and     w5, w5, #7

    cmp     w1, #OP_CONST
    b.eq    ir_const
    cmp     w1, #OP_ADD
    b.eq    ir_add
    cmp     w1, #OP_SUB
    b.eq    ir_sub
    cmp     w1, #OP_MUL
    b.eq    ir_mul
    cmp     w1, #OP_DIV
    b.eq    ir_div
    cmp     w1, #OP_NEG
    b.eq    ir_neg
    b       ir_next

ir_const:
    mov     w0, w6
    mov     w1, w3
    bl      emitir_movz_xN
    b       ir_next

ir_add:
    mov     w0, w3
    mov     w1, w4
    mov     w2, w5
    bl      emitir_add_reg
    b       ir_next

ir_sub:
    mov     w0, w3
    mov     w1, w4
    mov     w2, w5
    bl      emitir_sub_reg
    b       ir_next

ir_mul:
    mov     w0, w3
    mov     w1, w4
    mov     w2, w5
    bl      emitir_mul_reg
    b       ir_next

ir_div:
    mov     w0, w3
    mov     w1, w4
    mov     w2, w5
    bl      emitir_sdiv_reg
    b       ir_next

ir_neg:
    mov     w0, w3
    mov     w1, w4
    bl      emitir_neg_reg
    b       ir_next

ir_next:
    add     x2, x2, #1
    b       ir_loop

ir_fin:
    ldp     x19, x21, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

emitir_elf:
    stp     x19, x20, [sp, #-96]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]
    stp     x27, x28, [sp, #64]
    stp     x30, xzr, [sp, #80]

    ldr     x19, =opcode_buffer
    mov     x20, x19

    ldr     x0, =reg_name_len
    mov     x1, #8
0:  str     wzr, [x0], #4
    subs    x1, x1, #1
    b.ne    0b

    ldr     x21, =ast_root_ptr
    ldr     x21, [x21]
    ldr     x22, =ast_node_count
    ldr     x22, [x22]
    cbz     x21, fallback
    cbz     x22, fallback

    mov     x23, #0
    mov     w24, #0

gen_loop:
    cmp     x23, x22
    b.ge    despues_ast
    mov     x0, x23
    lsl     x0, x0, #5
    add     x0, x21, x0
    ldr     w1, [x0]
    cmp     w1, #AST_VAR_DECL
    b.eq    do_decl
    cmp     w1, #AST_ASSIGN
    b.eq    do_assign
    cmp     w1, #AST_WHILE
    b.eq    do_while
    b       next

do_decl:
    ldr     w2, [x0, #8]
    ldr     w3, [x0, #12]
    ldr     x4, [x0, #16]
    cmp     w24, #8
    b.ge    next
    ldr     x5, =reg_name_start
    str     w2, [x5, x24, lsl #2]
    ldr     x5, =reg_name_len
    str     w3, [x5, x24, lsl #2]
    mov     w0, w4
    mov     w1, w24
    bl      emitir_movz_xN
    add     w24, w24, #1
    b       next

do_assign:
    ldr     w26, [x0, #4]
    ldr     w2, [x0, #8]
    ldr     w3, [x0, #12]
    ldr     x4, [x0, #16]
    mov     x0, x2
    mov     x1, x3
    bl      find_reg_by_name
    cmp     w0, #0xFF
    b.eq    next
    mov     w1, w4
    cmp     w26, #1
    b.eq    da_sub
    cmp     w26, #2
    b.eq    da_add
    b       next
da_sub:
    bl      emitir_sub_imm
    b       next
da_add:
    bl      emitir_add_imm
    b       next

do_while:
    ldr     w26, [x0, #4]
    ldr     w2, [x0, #8]
    ldr     w3, [x0, #12]
    mov     x0, x2
    mov     x1, x3
    bl      find_reg_by_name
    cmp     w0, #0xFF
    b.eq    skip_wb
    mov     w25, w0

    mov     x27, x20
    mov     w0, w25
    bl      emitir_cmp0
    mov     x28, x20
    bl      emitir_beq_placeholder

    add     x23, x23, #1
blp:
    cbz     w26, bld
    cmp     x23, x22
    b.ge    bld
    mov     x0, x23
    lsl     x0, x0, #5
    add     x0, x21, x0
    ldr     w1, [x0]
    cmp     w1, #AST_ASSIGN
    b.ne    bln
    ldr     w7, [x0, #4]
    ldr     w2, [x0, #8]
    ldr     w3, [x0, #12]
    ldr     x4, [x0, #16]
    mov     x0, x2
    mov     x1, x3
    str     w7, [sp, #-16]!
    str     x4, [sp, #8]
    bl      find_reg_by_name
    ldr     x4, [sp, #8]
    ldr     w7, [sp], #16
    cmp     w0, #0xFF
    b.eq    bln
    mov     w1, w4
    cmp     w7, #1
    b.ne    1f
    bl      emitir_sub_imm
    b       bln
1:  cmp     w7, #2
    b.ne    bln
    bl      emitir_add_imm
bln:
    add     x23, x23, #1
    sub     w26, w26, #1
    b       blp

bld:
    sub     x0, x27, x20
    asr     x0, x0, #2
    bl      emitir_b
    sub     x0, x20, x28
    asr     x0, x0, #2
    mov     x1, x28
    bl      patch_beq
    b       gen_loop

skip_wb:
    mov     x0, x23
    lsl     x0, x0, #5
    add     x0, x21, x0
    ldr     w26, [x0, #4]
    add     x23, x23, #1
    add     x23, x23, x26
    b       gen_loop

next:
    add     x23, x23, #1
    b       gen_loop

fallback:
    mov     w0, #0
    mov     w1, #0
    bl      emitir_movz_xN

despues_ast:
    bl      recorrer_ir

epilogo:
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

    ldp     x30, xzr, [sp, #80]
    ldp     x27, x28, [sp, #64]
    ldp     x25, x26, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #96
    ret
