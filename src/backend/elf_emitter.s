.global emitir_elf
.global recorrer_ir

.equ AT_FDCWD,     -100

.equ OP_CONST,   1
.equ OP_LOAD,    2
.equ OP_STORE,   3
.equ OP_ADD,     4
.equ OP_SUB,     5
.equ OP_MUL,     6
.equ OP_DIV,     7
.equ OP_NEG,     8
.equ OP_CMP,     9
.equ OP_JMP,    10
.equ OP_JZ,     11
.equ OP_JNZ,    12
.equ OP_LABEL,  13
.equ OP_EXIT,   14

.equ MAX_LABELS, 64

.section .bss
    .align 4
    opcode_buffer: .skip 8192
    last_reg:      .skip 8
    // label_pos[id] = offset en bytes desde el inicio del buffer (o -1)
    label_pos:     .skip MAX_LABELS * 8
    // pending jumps: simple lista lineal (offset del instr, label_id, tipo)
    // tipo: 0=JMP, 1=JZ, 2=JNZ
    pending_count: .skip 8
    pending_off:   .skip MAX_LABELS * 8
    pending_lab:   .skip MAX_LABELS * 8
    pending_typ:   .skip MAX_LABELS * 8

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

// ─────────────────────────────────────────────────────────────
// Helpers de emisión (x20 = cursor vivo)
// ─────────────────────────────────────────────────────────────

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
    movz    w3, #0
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

emitir_neg_reg:
    and     w0, w0, #0x1F
    and     w1, w1, #0x1F
    movz    w3, #0
    movk    w3, #0xCB00, lsl #16
    orr     w3, w3, w0
    mov     w2, #31
    lsl     w2, w2, #5
    orr     w3, w3, w2
    lsl     w1, w1, #16
    orr     w3, w3, w1
    str     w3, [x20], #4
    ret

emitir_cmp0:
    and     w0, w0, #0x1F
    movz    w2, #0x001F
    movk    w2, #0xF100, lsl #16
    lsl     w0, w0, #5
    orr     w2, w2, w0
    str     w2, [x20], #4
    ret

// Emite un B (incondicional) con offset provisional 0
emitir_b_placeholder:
    movz    w2, #0
    movk    w2, #0x1400, lsl #16
    str     w2, [x20], #4
    ret

// Emite un B.EQ con offset provisional 0
emitir_beq_placeholder:
    movz    w2, #0
    movk    w2, #0x5400, lsl #16
    str     w2, [x20], #4
    ret

// Patch B: w0 = offset en instrucciones (signed), x1 = dirección del instr
patch_b:
    // B encoding: 0001 01 imm26
    and     w0, w0, #0x03FFFFFF
    movz    w2, #0
    movk    w2, #0x1400, lsl #16
    orr     w2, w2, w0
    str     w2, [x1]
    ret

// Patch B.EQ: w0 = offset en instrucciones (signed 19-bit), x1 = dirección
patch_beq:
    // B.cond: 0101 0100 imm19 0 cond
    // cond = 0000 (EQ)
    and     w0, w0, #0x0007FFFF
    lsl     w0, w0, #5
    movz    w2, #0
    movk    w2, #0x5400, lsl #16
    orr     w2, w2, w0
    str     w2, [x1]
    ret

// ─────────────────────────────────────────────────────────────
recorrer_ir:
    stp     x29, x30, [sp, #-80]!
    stp     x19, x21, [sp, #16]
    stp     x22, x23, [sp, #32]
    stp     x24, x25, [sp, #48]
    stp     x26, x27, [sp, #64]

    // x19 = base del buffer (para calcular offsets)
    mov     x19, x20

    // Inicializar label_pos = -1
    ldr     x0, =label_pos
    mov     x1, #MAX_LABELS
1:  mov     x2, #-1
    str     x2, [x0], #8
    subs    x1, x1, #1
    b.ne    1b

    ldr     x0, =pending_count
    str     xzr, [x0]
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
    b.ge    ir_patch

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
    cmp     w1, #OP_MUL
    b.eq    do_mul
    cmp     w1, #OP_DIV
    b.eq    do_div
    cmp     w1, #OP_NEG
    b.eq    do_neg
    cmp     w1, #OP_CMP
    b.eq    do_cmp
    cmp     w1, #OP_LABEL
    b.eq    do_label
    cmp     w1, #OP_JMP
    b.eq    do_jmp
    cmp     w1, #OP_JZ
    b.eq    do_jz
    cmp     w1, #OP_JNZ
    b.eq    do_jnz
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

do_mul:
    and     w0, w2, #0x7
    and     w1, w3, #0x7
    and     w2, w4, #0x7
    bl      emitir_mul_reg
    mov     x0, x23
    lsl     x0, x0, #3
    add     x0, x21, x0
    ldrb    w1, [x0, #1]
    and     x1, x1, #7
    ldr     x0, =last_reg
    str     x1, [x0]
    b       ir_next

do_div:
    and     w0, w2, #0x7
    and     w1, w3, #0x7
    and     w2, w4, #0x7
    bl      emitir_sdiv_reg
    mov     x0, x23
    lsl     x0, x0, #3
    add     x0, x21, x0
    ldrb    w1, [x0, #1]
    and     x1, x1, #7
    ldr     x0, =last_reg
    str     x1, [x0]
    b       ir_next

do_neg:
    and     w0, w2, #0x7
    and     w1, w3, #0x7
    bl      emitir_neg_reg
    and     x1, x2, #7
    ldr     x0, =last_reg
    str     x1, [x0]
    b       ir_next

do_cmp:
    and     w0, w3, #0x7
    bl      emitir_cmp0
    b       ir_next

// ── OP_LABEL imm = label_id ────────────────────────────────
do_label:
    // Guardar posición actual (offset desde base)
    sub     x0, x20, x19
    ldr     x1, =label_pos
    // x5 = label_id
    cmp     x5, #MAX_LABELS
    b.hs    ir_next
    str     x0, [x1, x5, lsl #3]
    b       ir_next

// ── OP_JMP imm = label_id ──────────────────────────────────
do_jmp:
    // Guardar pending
    ldr     x0, =pending_count
    ldr     x1, [x0]
    cmp     x1, #MAX_LABELS
    b.hs    ir_next
    // pending_off[i] = posición actual del placeholder
    sub     x2, x20, x19
    ldr     x3, =pending_off
    str     x2, [x3, x1, lsl #3]
    // pending_lab[i] = label_id
    ldr     x3, =pending_lab
    str     x5, [x3, x1, lsl #3]
    // pending_typ[i] = 0 (JMP)
    ldr     x3, =pending_typ
    str     xzr, [x3, x1, lsl #3]
    add     x1, x1, #1
    str     x1, [x0]
    // Emitir placeholder
    bl      emitir_b_placeholder
    b       ir_next

// ── OP_JZ imm = label_id ───────────────────────────────────
do_jz:
    ldr     x0, =pending_count
    ldr     x1, [x0]
    cmp     x1, #MAX_LABELS
    b.hs    ir_next
    sub     x2, x20, x19
    ldr     x3, =pending_off
    str     x2, [x3, x1, lsl #3]
    ldr     x3, =pending_lab
    str     x5, [x3, x1, lsl #3]
    ldr     x3, =pending_typ
    mov     x4, #1                  // tipo JZ
    str     x4, [x3, x1, lsl #3]
    add     x1, x1, #1
    str     x1, [x0]
    bl      emitir_beq_placeholder
    b       ir_next

// ── OP_JNZ (por ahora igual que JZ, se ajusta después) ─────
do_jnz:
    // Por simplicidad tratamos igual que JZ (se puede mejorar)
    b       do_jz

ir_next:
    add     x23, x23, #1
    b       ir_loop

// ── Backpatch ──────────────────────────────────────────────
ir_patch:
    ldr     x0, =pending_count
    ldr     x22, [x0]               // n pending
    mov     x23, #0

patch_loop:
    cmp     x23, x22
    b.ge    ir_fin

    // offset del instr
    ldr     x0, =pending_off
    ldr     x24, [x0, x23, lsl #3]  // offset bytes del placeholder
    // label_id
    ldr     x0, =pending_lab
    ldr     x25, [x0, x23, lsl #3]
    // tipo
    ldr     x0, =pending_typ
    ldr     x26, [x0, x23, lsl #3]

    // posición del label
    cmp     x25, #MAX_LABELS
    b.hs    patch_next
    ldr     x0, =label_pos
    ldr     x27, [x0, x25, lsl #3]  // offset del label
    cmp     x27, #-1
    b.eq    patch_next

    // delta en bytes = label_pos - (placeholder_pos + 4)
    // luego en instrucciones = delta / 4
    add     x0, x24, #4
    sub     x0, x27, x0
    asr     x0, x0, #2              // instrucciones

    // dirección del placeholder
    add     x1, x19, x24

    cmp     x26, #0
    b.eq    do_patch_b
    // JZ
    bl      patch_beq
    b       patch_next
do_patch_b:
    bl      patch_b

patch_next:
    add     x23, x23, #1
    b       patch_loop

ir_fin:
    // last_reg → x0
    ldr     x0, =last_reg
    ldr     x1, [x0]
    cbz     x1, 2f
    mov     w0, #0
    mov     w1, w1
    bl      emitir_mov_reg
2:
    ldp     x26, x27, [sp, #64]
    ldp     x24, x25, [sp, #48]
    ldp     x22, x23, [sp, #32]
    ldp     x19, x21, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// ─────────────────────────────────────────────────────────────
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
