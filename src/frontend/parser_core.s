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

.equ OP_CONST,   1
.equ OP_LOAD,    2
.equ OP_STORE,   3
.equ OP_ADD,     4
.equ OP_SUB,     5

.section .bss
    .align 3
    ast_root_ptr:   .skip 8
    ast_node_count: .skip 8
    expr_tok_idx:   .skip 8
    slot_table_ptr: .skip 8
    slot_count:     .skip 8
    next_vreg:      .skip 8

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

// lookup_slot_index: compara nombre, devuelve índice o -1
// x0 = start, x1 = len → x0 = index
lookup_slot_index:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0
    mov     x20, x1
    ldr     x21, =slot_table_ptr
    ldr     x21, [x21]
    cbz     x21, lsi_fail
    ldr     x22, =slot_count
    ldr     x22, [x22]
    mov     x0, #0
lsi_loop:
    cmp     x0, x22
    b.ge    lsi_fail
    mov     x1, x0
    lsl     x1, x1, #5
    add     x1, x21, x1
    ldr     w2, [x1]            // name_start
    ldr     w3, [x1, #4]        // name_len
    mov     x4, x0              // guardar índice
    cmp     x20, x3
    b.ne    lsi_next
    ldr     x5, =fuente_ptr
    ldr     x5, [x5]
    add     x6, x5, x19
    add     x7, x5, x2
    mov     x3, x20
lsi_cmp:
    cbz     x3, lsi_found
    ldrb    w0, [x6], #1
    ldrb    w1, [x7], #1
    cmp     w0, w1
    b.ne    lsi_next
    sub     x3, x3, #1
    b       lsi_cmp
lsi_found:
    mov     x0, x4
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
lsi_next:
    mov     x0, x4
    add     x0, x0, #1
    b       lsi_loop
lsi_fail:
    mov     x0, #-1
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

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
    mov     w27, w0
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
    mov     w9, w0
    mov     w10, w1
    bl      advance_token
    bl      peek_type
    cmp     w0, #TOKEN_ASSIGN
    b.ne    9f
    bl      advance_token
    bl      parse_expr
    mov     x11, x0
    bl      peek_type
    cmp     w0, #TOKEN_SEMI
    b.ne    2f
    bl      advance_token
2:  mov     w0, w9
    mov     w1, w10
    mov     w2, w27
    mov     x3, x11
    bl      register_slot

    ldr     x0, =slot_count
    ldr     x0, [x0]
    sub     x0, x0, #1

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
// parse_assign: IDENT = IDENT - NUMBER ;
// Emite: LOAD, CONST, SUB, STORE
// ─────────────────────────────────────────────────────────────
parse_assign:
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    bl      current_ident_span
    mov     x19, x0                 // lhs start
    mov     x20, x1                 // lhs len
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_ASSIGN
    b.ne    asg_fail
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_IDENT
    b.ne    asg_fail
    // consumimos el ident derecho (debe ser el mismo por ahora)
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_MINUS
    b.eq    asg_sub
    cmp     w0, #TOKEN_PLUS
    b.eq    asg_add
    b       asg_fail
asg_sub:
    mov     w21, #OP_SUB
    b       asg_op
asg_add:
    mov     w21, #OP_ADD
asg_op:
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_NUMBER
    b.ne    asg_fail
    bl      current_number_value
    mov     x22, x0                 // número
    bl      advance_token

    bl      peek_type
    cmp     w0, #TOKEN_SEMI
    b.ne    1f
    bl      advance_token
1:
    // slot del lhs
    mov     x0, x19
    mov     x1, x20
    bl      lookup_slot_index
    cmp     x0, #-1
    b.eq    asg_fail
    mov     x23, x0                 // slot index

    // LOAD slot → vregA
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     w0, #OP_LOAD
    mov     w2, #0
    mov     w3, #0
    mov     x4, x23
    bl      ir_emit
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     x24, x1                 // vregA
    add     x1, x1, #1
    str     x1, [x0]

    // CONST num → vregB
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     w0, #OP_CONST
    mov     w2, #0
    mov     w3, #0
    mov     x4, x22
    bl      ir_emit
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     x9, x1                  // vregB (temporal)
    add     x1, x1, #1
    str     x1, [x0]

    // SUB/ADD vregC = vregA op vregB
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     w0, w21
    mov     w2, w24                 // src1
    mov     w3, w9                  // src2
    mov     x4, #0
    bl      ir_emit
    ldr     x0, =next_vreg
    ldr     x1, [x0]
    mov     x24, x1                 // vregC
    add     x1, x1, #1
    str     x1, [x0]

    // STORE slot = vregC
    mov     w0, #OP_STORE
    mov     w1, #0
    mov     w2, w24
    mov     w3, #0
    mov     x4, x23
    bl      ir_emit

    mov     w0, #1
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

asg_fail:
    mov     w0, #0
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
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
    bl      advance_token
    b       parser_loop

do_decl:
    bl      parse_one_decl
    b       parser_loop
do_assign:
    bl      parse_assign
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
