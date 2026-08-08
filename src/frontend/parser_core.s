.global iniciar_parser
.global ast_root_ptr
.global ast_node_count

.equ AST_VAR_DECL,  100
.equ AST_NODE_SIZE, 32
.equ MAX_AST_NODES, 512
.equ SLOT_SIZE,     32
.equ MAX_SLOTS,     256

.equ TOKEN_EOF,      0
.equ TOKEN_SEA,      1
.equ TOKEN_FIJO,     2
.equ TOKEN_IDENT,    3
.equ TOKEN_NUMBER,   4
.equ TOKEN_ASSIGN,   5
.equ TOKEN_SEMI,     6
.equ TOKEN_PLUS,     8
.equ TOKEN_MINUS,    9
.equ TOKEN_LBRACE,  14
.equ TOKEN_RBRACE,  15
.equ TOKEN_MIENTRAS,18

.equ OP_CONST,   1
.equ OP_LOAD,    2
.equ OP_STORE,   3
.equ OP_ADD,     4
.equ OP_SUB,     5
.equ OP_CMP,     9
.equ OP_JMP,    10
.equ OP_JZ,     11
.equ OP_LABEL,  13

.section .bss
    .align 3
    ast_root_ptr:   .skip 8
    ast_node_count: .skip 8
    expr_tok_idx:   .skip 8
    slot_table_ptr: .skip 8
    slot_count:     .skip 8
    next_vreg:      .skip 8
    next_label:     .skip 8

.section .text

parsear_numero_token:
    ldr     x2, =fuente_ptr
    ldr     x2, [x2]
    add     x2, x2, x0
    mov     x0, #0
    mov     x3, #10
1:  cbz     x1, 2f
    ldrb    w4, [x2], #1
    sub     w4, w4, #'0'
    mul     x0, x0, x3
    add     x0, x0, x4
    sub     x1, x1, #1
    b       1b
2:  ret

// IMPORTANTE: peek/advance asumen x19=token_array, x20=token_count
peek_type:
    ldr     x0, =expr_tok_idx
    ldr     x0, [x0]
    cmp     x0, x20
    b.ge    1f
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w0, [x0]
    ret
1:  mov     w0, #TOKEN_EOF
    ret

advance_token:
    ldr     x0, =expr_tok_idx
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]
    ret

current_number_value:
    ldr     x0, =expr_tok_idx
    ldr     x0, [x0]
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w1, [x0, #4]
    ldr     w2, [x0, #8]
    mov     x0, x1
    mov     x1, x2
    b       parsear_numero_token

current_ident_span:
    ldr     x0, =expr_tok_idx
    ldr     x0, [x0]
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w1, [x0, #4]
    ldr     w2, [x0, #8]
    mov     x0, x1
    mov     x1, x2
    ret

register_slot:
    ldr     x4, =slot_table_ptr
    ldr     x4, [x4]
    cbz     x4, 9f
    ldr     x5, =slot_count
    ldr     x6, [x5]
    cmp     x6, #MAX_SLOTS
    b.ge    9f
    mov     x7, x6
    lsl     x7, x7, #5
    add     x7, x4, x7
    str     w0, [x7]
    str     w1, [x7, #4]
    str     w2, [x7, #8]
    str     wzr, [x7, #12]
    str     x3, [x7, #16]
    add     x6, x6, #1
    str     x6, [x5]
9:  ret

parse_expr:
    stp     x29, x30, [sp, #-16]!
    bl      peek_type
    cmp     w0, #TOKEN_NUMBER
    b.ne    9f
    bl      current_number_value
    mov     x9, x0
    bl      advance_token
    ldr     x1, =next_vreg
    ldr     x2, [x1]
    mov     w0, #OP_CONST
    mov     w1, w2
    mov     w2, #0
    mov     w3, #0
    mov     x4, x9
    bl      ir_emit
    ldr     x1, =next_vreg
    ldr     x2, [x1]
    add     x2, x2, #1
    str     x2, [x1]
    mov     x0, x9
    ldp     x29, x30, [sp], #16
    ret
9:  mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

parse_one_decl:
    stp     x29, x30, [sp, #-32]!
    bl      peek_type
    mov     w9, w0
    cmp     w0, #TOKEN_SEA
    b.eq    1f
    cmp     w0, #TOKEN_FIJO
    b.eq    1f
    mov     w0, #0
    ldp     x29, x30, [sp], #32
    ret
1:  bl      advance_token
    bl      peek_type
    cmp     w0, #TOKEN_IDENT
    b.ne    9f
    bl      current_ident_span
    mov     w10, w0
    mov     w11, w1
    bl      advance_token
    bl      peek_type
    cmp     w0, #TOKEN_ASSIGN
    b.ne    9f
    bl      advance_token
    bl      parse_expr
    mov     x12, x0
    bl      peek_type
    cmp     w0, #TOKEN_SEMI
    b.ne    2f
    bl      advance_token
2:  mov     w0, w10
    mov     w1, w11
    mov     w2, w9
    mov     x3, x12
    bl      register_slot

    ldr     x1, =next_vreg
    ldr     x2, [x1]
    sub     x2, x2, #1
    mov     w0, #OP_STORE
    mov     w1, #0
    mov     w2, w2
    mov     w3, #0
    ldr     x4, =slot_count
    ldr     x4, [x4]
    sub     x4, x4, #1
    bl      ir_emit

    mov     w0, #1
    ldp     x29, x30, [sp], #32
    ret
9:  mov     w0, #0
    ldp     x29, x30, [sp], #32
    ret

// ─────────────────────────────────────────────────────────────
// parse_assign — NO toca x19/x20
// ─────────────────────────────────────────────────────────────
parse_assign:
    stp     x29, x30, [sp, #-16]!

    bl      peek_type
    cmp     w0, #TOKEN_IDENT
    b.ne    asg_fail
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_ASSIGN
    b.ne    asg_fail
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_IDENT
    b.ne    asg_fail
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_MINUS
    b.eq    asg_sub
    cmp     w0, #TOKEN_PLUS
    b.eq    asg_add
    b       asg_fail
asg_sub:
    mov     w9, #OP_SUB
    b       asg_op
asg_add:
    mov     w9, #OP_ADD
asg_op:
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_NUMBER
    b.ne    asg_fail
    bl      current_number_value
    mov     x10, x0
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_SEMI
    b.ne    1f
    bl      advance_token
1:
    // LOAD slot0
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     w0, #OP_LOAD
    mov     w2, #0
    mov     w3, #0
    mov     x4, #0
    bl      ir_emit
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     x11, x1
    add     x1, x1, #1
    str     x1, [x0]

    // CONST num
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     w0, #OP_CONST
    mov     w2, #0
    mov     w3, #0
    mov     x4, x10
    bl      ir_emit
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     x12, x1
    add     x1, x1, #1
    str     x1, [x0]

    // SUB/ADD
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     w0, w9
    mov     w2, w11
    mov     w3, w12
    mov     x4, #0
    bl      ir_emit
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     x11, x1
    add     x1, x1, #1
    str     x1, [x0]

    // STORE slot0
    mov     w0, #OP_STORE
    mov     w1, #0
    mov     w2, w11
    mov     w3, #0
    mov     x4, #0
    bl      ir_emit

    mov     w0, #1
    ldp     x29, x30, [sp], #16
    ret

asg_fail:
    mov     w0, #0
    ldp     x29, x30, [sp], #16
    ret

// ─────────────────────────────────────────────────────────────
// parse_mientras — versión mínima y segura
// mientras IDENT { assign }
// Emite:
//   LABEL L_inicio
//   LOAD slot0 → vreg
//   CMP vreg, #0
//   JZ L_fin
//   <cuerpo>
//   JMP L_inicio
//   LABEL L_fin
// ─────────────────────────────────────────────────────────────
parse_mientras:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]     // guardar (aunque no los tocamos)
    stp     x21, x22, [sp, #32]

    // consumir 'mientras'
    bl      advance_token

    // condición debe ser IDENT (solo slot 0 por ahora)
    bl      peek_type
    cmp     w0, #TOKEN_IDENT
    b.ne    mien_fail
    bl      advance_token

    // esperar '{'
    bl      peek_type
    cmp     w0, #TOKEN_LBRACE
    b.ne    mien_fail
    bl      advance_token

    // crear dos labels
    ldr     x0, =next_label
    ldr     x1, [x0]
    mov     x21, x1                 // L_inicio
    add     x1, x1, #1
    mov     x22, x1                 // L_fin
    add     x1, x1, #1
    str     x1, [x0]

    // LABEL L_inicio
    mov     w0, #OP_LABEL
    mov     w1, #0
    mov     w2, #0
    mov     w3, #0
    mov     x4, x21
    bl      ir_emit

    // LOAD slot0 → nuevo vreg
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     w0, #OP_LOAD
    mov     w2, #0                  // dest vreg
    mov     w3, #0
    mov     x4, #0                  // slot 0
    bl      ir_emit
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     x9, x1                  // vreg de la condición
    add     x1, x1, #1
    str     x1, [x0]

    // CMP vreg, #0
    mov     w0, #OP_CMP
    mov     w1, #0
    mov     w2, w9                  // src1 = vreg
    mov     w3, #0
    mov     x4, #0
    bl      ir_emit

    // JZ L_fin
    mov     w0, #OP_JZ
    mov     w1, #0
    mov     w2, #0
    mov     w3, #0
    mov     x4, x22
    bl      ir_emit

    // cuerpo: solo un assign por ahora
    bl      parse_assign
    // ignoramos el resultado (si falla, el programa se detiene de todos modos)

    // JMP L_inicio
    mov     w0, #OP_JMP
    mov     w1, #0
    mov     w2, #0
    mov     w3, #0
    mov     x4, x21
    bl      ir_emit

    // LABEL L_fin
    mov     w0, #OP_LABEL
    mov     w1, #0
    mov     w2, #0
    mov     w3, #0
    mov     x4, x22
    bl      ir_emit

    // esperar '}'
    bl      peek_type
    cmp     w0, #TOKEN_RBRACE
    b.ne    mien_fail
    bl      advance_token

    mov     w0, #1
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

mien_fail:
    mov     w0, #0
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

iniciar_parser:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    ldr     x19, =token_array_ptr
    ldr     x19, [x19]
    ldr     x20, =token_count
    ldr     x20, [x20]
    cbz     x19, parser_vacio
    cbz     x20, parser_vacio

    mov     x0, #(MAX_SLOTS * SLOT_SIZE)
    bl      alloc_arena
    ldr     x1, =slot_table_ptr
    str     x0, [x1]
    ldr     x1, =slot_count
    str     xzr, [x1]

    mov     x0, #(MAX_AST_NODES * AST_NODE_SIZE)
    bl      alloc_arena
    ldr     x1, =ast_root_ptr
    str     x0, [x1]
    mov     x21, x0
    mov     x22, #0

    ldr     x0, =expr_tok_idx
    str     xzr, [x0]
    ldr     x0, =next_vreg
    str     xzr, [x0]
    ldr     x0, =next_label
    str     xzr, [x0]

parser_loop:
    bl      peek_type
    cmp     w0, #TOKEN_EOF
    b.eq    parser_fin
    cmp     w0, #TOKEN_SEA
    b.eq    do_decl
    cmp     w0, #TOKEN_FIJO
    b.eq    do_decl
    cmp     w0, #TOKEN_IDENT
    b.eq    do_assign
    cmp     w0, #TOKEN_MIENTRAS
    b.eq    do_mientras
    bl      advance_token
    b       parser_loop

do_decl:
    bl      parse_one_decl
    b       parser_loop
do_assign:
    bl      parse_assign
    b       parser_loop
do_mientras:
    bl      parse_mientras
    b       parser_loop

parser_vacio:
    mov     x22, #0
parser_fin:
    ldr     x0, =ast_node_count
    str     x22, [x0]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
