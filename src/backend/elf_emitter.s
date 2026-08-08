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

.equ MAX_SLOTS,  64
.equ MAX_REGS,   8          // x0-x7

.section .bss
    .align 4
    opcode_buffer: .skip 8192
    // slot_to_reg[i] = registro físico (0-7) o 0xFF si no asignado
    slot_to_reg:   .skip MAX_SLOTS
    next_reg:      .skip 8
    last_reg:      .skip 8      // último registro que escribió un valor

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
// Helpers de emisión
// x20 = cursor (NO se restaura entre llamadas)
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
    // MOV Xd, Xn  ==  ORR Xd, XZR, Xn
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

// ─────────────────────────────────────────────────────────────
// Asignación de registros a slots
// ─────────────────────────────────────────────────────────────

// alloc_reg → w0 = siguiente registro libre (0-7, wrap)
alloc_reg:
    ldr     x1, =next_reg
    ldr     x0, [x1]
    and     x0, x0, #7
    add     x2, x0, #1
    str     x2, [x1]
    ret

// get_slot_reg(slot) → w0 = reg físico
// Si no tiene, asigna uno nuevo.
get_slot_reg:
    cmp     x0, #MAX_SLOTS
    b.hs    9f
    ldr     x1, =slot_to_reg
    ldrb    w2, [x1, x0]
    cmp     w2, #0xFF
    b.ne    8f
    // asignar
    str     x0, [sp, #-16]!
    bl      alloc_reg
    ldr     x3, [sp], #16
    ldr     x1, =slot_to_reg
    strb    w0, [x1, x3]
    ret
8:  mov     w0, w2
    ret
9:  mov     w0, #0
    ret

// ─────────────────────────────────────────────────────────────
recorrer_ir:
    // x20 = cursor vivo (NO se restaura)
    stp     x29, x30, [sp, #-64]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]

    // Inicializar slot_to_reg = 0xFF
    ldr     x0, =slot_to_reg
    mov     x1, #MAX_SLOTS
1:  mov     w2, #0xFF
    strb    w2, [x0], #1
    subs    x1, x1, #1
    b.ne    1b

    ldr     x0, =next_reg
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
    b.ge    ir_fin

    mov     x0, x23
    lsl     x0, x0, #3
    add     x0, x21, x0

    ldrb    w1, [x0]                // op
    ldrb    w2, [x0, #1]            // dest
    ldrb    w3, [x0, #2]            // src1
    ldrb    w4, [x0, #3]            // src2
    ldrsw   x5, [x0, #4]            // imm

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
    b       ir_next

// ── OP_CONST dest = imm ────────────────────────────────────
do_const:
    // Usamos dest % 8 como registro temporal
    and     w25, w2, #0x7
    mov     w0, w5
    mov     w1, w25
    bl      emitir_movz_xN
    ldr     x0, =last_reg
    str     x25, [x0]
    b       ir_next

// ── OP_LOAD dest = slot[imm] ───────────────────────────────
do_load:
    mov     x0, x5                  // slot index
    bl      get_slot_reg
    mov     w26, w0                 // reg del slot

    and     w25, w2, #0x7           // dest temporal
    cmp     w25, w26
    b.eq    1f
    mov     w0, w25
    mov     w1, w26
    bl      emitir_mov_reg
1:  ldr     x0, =last_reg
    str     x25, [x0]
    b       ir_next

// ── OP_STORE slot[imm] = src1 ──────────────────────────────
do_store:
    and     w25, w3, #0x7           // reg fuente (vreg)

    mov     x0, x5                  // slot index
    bl      get_slot_reg
    mov     w26, w0                 // reg del slot

    cmp     w26, w25
    b.eq    1f
    mov     w0, w26
    mov     w1, w25
    bl      emitir_mov_reg
1:  ldr     x0, =last_reg
    str     x26, [x0]
    b       ir_next

// ── Aritmética ─────────────────────────────────────────────
do_add:
    and     w0, w2, #0x7
    and     w1, w3, #0x7
    and     w2, w4, #0x7
    bl      emitir_add_reg
    and     x1, x0, #7              // approx, better re-read
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
    and     x1, x0, #7
    ldr     x0, =last_reg
    str     x1, [x0]
    b       ir_next

do_cmp:
    and     w0, w3, #0x7
    bl      emitir_cmp0
    b       ir_next

ir_next:
    add     x23, x23, #1
    b       ir_loop

ir_fin:
    // Forzar last_reg → x0
    ldr     x0, =last_reg
    ldr     x1, [x0]
    cbz     x1, 2f
    mov     w0, #0
    mov     w1, w1
    bl      emitir_mov_reg
2:
    ldp     x25, x26, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ─────────────────────────────────────────────────────────────
emitir_elf:
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x30, xzr, [sp, #32]

    ldr     x19, =opcode_buffer
    mov     x20, x19

    bl      recorrer_ir             // x20 avanza, no se restaura

    // exit(x0)
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
