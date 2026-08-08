.global ir_init
.global ir_emit
.global ir_count
.global ir_buffer_ptr
.global ir_instr_count

// ─────────────────────────────────────────────────────────────
// IR denso — EALN-64 Fase 2
// Cada instrucción ocupa 8 bytes (SoA-friendly, alineado)
// Layout de Instr:
//   +0  u8  op
//   +1  u8  dest      (registro virtual 0-31 o slot index)
//   +2  u8  src1
//   +3  u8  src2
//   +4  i32 imm       (constante o offset de salto / label id)
// ─────────────────────────────────────────────────────────────

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

.equ IR_INSTR_SIZE,  8
.equ MAX_IR_INSTR,   4096

.section .bss
    .align 3
    ir_buffer_ptr:   .skip 8
    ir_instr_count:  .skip 8

.section .text

// ir_init
// Reserva el buffer de IR en la arena y resetea el contador.
ir_init:
    stp     x29, x30, [sp, #-16]!
    mov     x0, #(MAX_IR_INSTR * IR_INSTR_SIZE)
    bl      alloc_arena
    ldr     x1, =ir_buffer_ptr
    str     x0, [x1]
    ldr     x1, =ir_instr_count
    str     xzr, [x1]
    ldp     x29, x30, [sp], #16
    ret

// ir_emit(op, dest, src1, src2, imm)
//   w0 = op
//   w1 = dest
//   w2 = src1
//   w3 = src2
//   x4 = imm (sign-extended a 32 bits al guardar)
// Devuelve el índice de la instrucción emitida en x0, o -1 si overflow.
ir_emit:
    ldr     x5, =ir_instr_count
    ldr     x6, [x5]
    cmp     x6, #MAX_IR_INSTR
    b.ge    ir_overflow

    ldr     x7, =ir_buffer_ptr
    ldr     x7, [x7]
    mov     x8, x6
    lsl     x8, x8, #3                  // * 8
    add     x8, x7, x8

    strb    w0, [x8]                    // op
    strb    w1, [x8, #1]                // dest
    strb    w2, [x8, #2]                // src1
    strb    w3, [x8, #3]                // src2
    str     w4, [x8, #4]                // imm (32-bit)

    add     x6, x6, #1
    str     x6, [x5]
    sub     x0, x6, #1                  // índice de la instr recién emitida
    ret

ir_overflow:
    mov     x0, #-1
    ret

// ir_count → x0 = número de instrucciones emitidas
ir_count:
    ldr     x0, =ir_instr_count
    ldr     x0, [x0]
    ret
