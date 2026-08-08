.global emitir_elf
.global recorrer_ir

.equ AT_FDCWD,     -100

// IR opcodes (deben coincidir con ir.s y parser_core.s)
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

// ─────────────────────────────────────────────────────────────
// Helpers de emisión de opcodes AArch64
// x20 = cursor de escritura en opcode_buffer
// ─────────────────────────────────────────────────────────────

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

// ADD Xd, Xn, Xm
// w0 = Rd, w1 = Rn, w2 = Rm
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
    and     w0, w0, #0x1F
    and     w1, w1, #0x1F
    movz    w3, #0
    movk    w3, #0xCB00, lsl #16
    orr     w3, w3, w0
    mov     w2, #31                 // XZR
    lsl     w2, w2, #5
    orr     w3, w3, w2
    lsl     w1, w1, #16
    orr     w3, w3, w1
    str     w3, [x20], #4
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

// MOV Xd, Xn  (ORR Xd, XZR, Xn)
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

// ─────────────────────────────────────────────────────────────
// recorrer_ir — ÚNICO camino de generación de código
// Recorre el buffer de IR denso y emite opcodes AArch64.
// x19 = base opcode_buffer (se preserva)
// x20 = cursor de escritura
// ─────────────────────────────────────────────────────────────
recorrer_ir:
    stp     x29, x30, [sp, #-80]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    // Cargar IR
    ldr     x21, =ir_buffer_ptr
    ldr     x21, [x21]
    cbz     x21, ir_vacio

    bl      ir_count
    mov     x22, x0                 // n instrucciones
    cbz     x22, ir_vacio

    mov     x23, #0                 // índice

ir_loop:
    cmp     x23, x22
    b.ge    ir_fin

    // Cargar Instr (8 bytes)
    mov     x0, x23
    lsl     x0, x0, #3
    add     x0, x21, x0

    ldrb    w1, [x0]                // op
    ldrb    w2, [x0, #1]            // dest
    ldrb    w3, [x0, #2]            // src1
    ldrb    w4, [x0, #3]            // src2
    ldrsw   x5, [x0, #4]            // imm (sign-extended)

    // Despacho
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
    cmp     w1, #OP_JMP
    b.eq    do_jmp
    cmp     w1, #OP_JZ
    b.eq    do_jz
    cmp     w1, #OP_JNZ
    b.eq    do_jnz
    cmp     w1, #OP_LABEL
    b.eq    do_label
    cmp     w1, #OP_EXIT
    b.eq    do_exit

    // op desconocido → ignorar
    b       ir_next

// ── OP_CONST dest = imm ────────────────────────────────────
do_const:
    // Solo imm16 por ahora (valores pequeños)
    mov     w0, w5
    mov     w1, w2
    bl      emitir_movz_xN
    b       ir_next

// ── OP_LOAD dest = slot[imm] ───────────────────────────────
// Temporal: tratamos el índice de slot como registro físico
// (hasta que exista frame de slots real)
do_load:
    and     w0, w2, #0x1F           // dest
    and     w1, w5, #0x1F           // "slot" como reg temporal
    cmp     w0, w1
    b.eq    ir_next                 // ya está en el mismo reg
    bl      emitir_mov_reg
    b       ir_next

// ── OP_STORE slot[imm] = src1 ──────────────────────────────
// Temporal: no-op (el valor ya vive en el registro del slot)
do_store:
    b       ir_next

// ── OP_ADD dest = src1 + src2 ──────────────────────────────
do_add:
    mov     w0, w2
    mov     w1, w3
    mov     w2, w4
    bl      emitir_add_reg
    b       ir_next

// ── OP_SUB dest = src1 - src2 ──────────────────────────────
do_sub:
    mov     w0, w2
    mov     w1, w3
    mov     w2, w4
    bl      emitir_sub_reg
    b       ir_next

// ── OP_MUL dest = src1 * src2 ──────────────────────────────
do_mul:
    mov     w0, w2
    mov     w1, w3
    mov     w2, w4
    bl      emitir_mul_reg
    b       ir_next

// ── OP_DIV dest = src1 / src2 ──────────────────────────────
do_div:
    mov     w0, w2
    mov     w1, w3
    mov     w2, w4
    bl      emitir_sdiv_reg
    b       ir_next

// ── OP_NEG dest = -src1 ────────────────────────────────────
do_neg:
    mov     w0, w2
    mov     w1, w3
    bl      emitir_neg_reg
    b       ir_next

// ── OP_CMP src1 , #0 ───────────────────────────────────────
do_cmp:
    mov     w0, w3
    bl      emitir_cmp0
    b       ir_next

// ── Saltos y labels (placeholders por ahora) ───────────────
// El backpatch real llega en el punto 4 del plan.
do_jmp:
do_jz:
do_jnz:
do_label:
    b       ir_next

// ── OP_EXIT ────────────────────────────────────────────────
do_exit:
    b       ir_next

ir_next:
    add     x23, x23, #1
    b       ir_loop

ir_vacio:
ir_fin:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// ─────────────────────────────────────────────────────────────
// emitir_elf — punto de entrada del backend
// Ahora SOLO usa el camino IR.
// ─────────────────────────────────────────────────────────────
emitir_elf:
    stp     x19, x20, [sp, #-64]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x30, xzr, [sp, #48]

    ldr     x19, =opcode_buffer
    mov     x20, x19                // cursor

    // Único camino de generación
    bl      recorrer_ir

    // Epílogo: exit syscall
    // x0 se deja con el último valor vivo (o 0 si no hubo nada)
    mov     w0, #93                 // SYS_exit
    mov     w1, #8                  // x8
    bl      emitir_movz_xN

    // svc #0
    movz    w0, #0x0001
    movk    w0, #0xD400, lsl #16
    str     w0, [x20], #4

    // Calcular tamaño del código generado
    sub     x25, x20, x19

    // Actualizar program_header (p_filesz / p_memsz)
    mov     x5, #120                // tamaño headers
    add     x5, x5, x25
    ldr     x6, =program_header
    str     x5, [x6, #32]           // p_filesz
    str     x5, [x6, #40]           // p_memsz

    // openat(AT_FDCWD, "salida.out", O_CREAT|O_WRONLY|O_TRUNC, 0755)
    mov     x0, AT_FDCWD
    ldr     x1, =archivo_salida
    mov     x2, #577                // O_CREAT|O_WRONLY|O_TRUNC
    mov     x3, #493                // 0755
    mov     x8, #56                 // openat
    svc     #0
    mov     x22, x0                 // fd

    // write ELF header
    mov     x0, x22
    ldr     x1, =elf_header
    mov     x2, #64
    mov     x8, #64                 // write
    svc     #0

    // write program header
    mov     x0, x22
    ldr     x1, =program_header
    mov     x2, #56
    mov     x8, #64
    svc     #0

    // write código
    mov     x0, x22
    mov     x1, x19
    mov     x2, x25
    mov     x8, #64
    svc     #0

    // close
    mov     x0, x22
    mov     x8, #57                 // close
    svc     #0

    ldp     x30, xzr, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #64
    ret
