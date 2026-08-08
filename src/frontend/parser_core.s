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
.equ TOKEN_STAR,    10
.equ TOKEN_SLASH,   11
.equ TOKEN_LPAREN,  12
.equ TOKEN_RPAREN,  13
.equ TOKEN_LBRACE,  14
.equ TOKEN_RBRACE,  15
.equ TOKEN_SI,      16
.equ TOKEN_SINO,    17
.equ TOKEN_MIENTRAS,18

.section .bss
    .align 3
    ast_root_ptr:   .skip 8
    ast_node_count: .skip 8
    expr_tok_idx:   .skip 8
    slot_table_ptr: .skip 8
    slot_count:     .skip 8

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

compar_nombres:
    cmp     x1, x3
    b.ne    9f
    ldr     x4, =fuente_ptr
    ldr     x4, [x4]
    add     x0, x4, x0
    add     x2, x4, x2
1:  cbz     x1, 8f
    ldrb    w5, [x0], #1
    ldrb    w6, [x2], #1
    cmp     w5, w6
    b.ne    9f
    sub     x1, x1, #1
    b       1b
8:  mov     w0, #1
    ret
9:  mov     w0, #0
    ret

lookup_slot:
    stp     x30, x21, [sp, #-48]!
    stp     x22, x23, [sp, #16]
    stp     x24, x25, [sp, #32]
    mov     x22, x0
    mov     x23, x1
    ldr     x21, =slot_table_ptr
    ldr     x21, [x21]
    cbz     x21, 7f
    ldr     x24, =slot_count
    ldr     x24, [x24]
    mov     x25, #0
1:  cmp     x25, x24
    b.ge    7f
    mov     x0, x25
    lsl     x0, x0, #5
    add     x25, x25, #1
    add     x0, x21, x0
    ldr     w2, [x0]
    ldr     w3, [x0, #4]
    mov     x0, x22
    mov     x1, x23
    bl      compar_nombres
    cbz     w0, 1b
    sub     x25, x25, #1
    mov     x0, x25
    lsl     x0, x0, #5
    add     x0, x21, x0
    ldr     x0, [x0, #16]
    ldp     x24, x25, [sp, #32]
    ldp     x22, x23, [sp, #16]
    ldp     x30, x21, [sp], #48
    ret
7:  mov     x0, #0
    ldp     x24, x25, [sp, #32]
    ldp     x22, x23, [sp, #16]
    ldp     x30, x21, [sp], #48
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

parse_factor:
    stp     x30, xzr, [sp, #-16]!
    bl      peek_type
    cmp     w0, #TOKEN_NUMBER
    b.eq    10f
    cmp     w0, #TOKEN_IDENT
    b.eq    15f
    cmp     w0, #TOKEN_LPAREN
    b.eq    20f
    cmp     w0, #TOKEN_MINUS
    b.eq    30f
    mov     x0, #0
    ldp     x30, xzr, [sp], #16
    ret
10: bl      current_number_value
    str     x0, [sp, #8]
    bl      advance_token
    ldr     x0, [sp, #8]
    ldp     x30, xzr, [sp], #16
    ret
15: bl      current_ident_span
    bl      lookup_slot
    str     x0, [sp, #8]
    bl      advance_token
    ldr     x0, [sp, #8]
    ldp     x30, xzr, [sp], #16
    ret
20: bl      advance_token
    bl      parse_expr
    str     x0, [sp, #8]
    bl      peek_type
    cmp     w0, #TOKEN_RPAREN
    b.ne    21f
    bl      advance_token
21: ldr     x0, [sp, #8]
    ldp     x30, xzr, [sp], #16
    ret
30: bl      advance_token
    bl      parse_factor
    neg     x0, x0
    ldp     x30, xzr, [sp], #16
    ret

parse_term:
    stp     x30, xzr, [sp, #-32]!
    bl      parse_factor
    str     x0, [sp, #16]
40: bl      peek_type
    cmp     w0, #TOKEN_STAR
    b.eq    41f
    cmp     w0, #TOKEN_SLASH
    b.eq    42f
    ldr     x0, [sp, #16]
    ldp     x30, xzr, [sp], #32
    ret
41: bl      advance_token
    bl      parse_factor
    ldr     x1, [sp, #16]
    mul     x0, x1, x0
    str     x0, [sp, #16]
    b       40b
42: bl      advance_token
    bl      parse_factor
    ldr     x1, [sp, #16]
    sdiv    x0, x1, x0
    str     x0, [sp, #16]
    b       40b

parse_expr:
    stp     x30, xzr, [sp, #-32]!
    bl      parse_term
    str     x0, [sp, #16]
50: bl      peek_type
    cmp     w0, #TOKEN_PLUS
    b.eq    51f
    cmp     w0, #TOKEN_MINUS
    b.eq    52f
    ldr     x0, [sp, #16]
    ldp     x30, xzr, [sp], #32
    ret
51: bl      advance_token
    bl      parse_term
    ldr     x1, [sp, #16]
    add     x0, x1, x0
    str     x0, [sp, #16]
    b       50b
52: bl      advance_token
    bl      parse_term
    ldr     x1, [sp, #16]
    sub     x0, x1, x0
    str     x0, [sp, #16]
    b       50b

skip_block:
    stp     x30, x23, [sp, #-16]!
    bl      peek_type
    cmp     w0, #TOKEN_LBRACE
    b.ne    2f
    bl      advance_token
    mov     x23, #1
1:  cbz     x23, 2f
    bl      peek_type
    cmp     w0, #TOKEN_EOF
    b.eq    2f
    cmp     w0, #TOKEN_LBRACE
    b.ne    3f
    add     x23, x23, #1
    bl      advance_token
    b       1b
3:  cmp     w0, #TOKEN_RBRACE
    b.ne    4f
    sub     x23, x23, #1
    bl      advance_token
    b       1b
4:  bl      advance_token
    b       1b
2:  ldp     x30, x23, [sp], #16
    ret

parse_one_decl:
    stp     x30, xzr, [sp, #-16]!
    bl      peek_type
    mov     w27, w0
    cmp     w0, #TOKEN_SEA
    b.eq    1f
    cmp     w0, #TOKEN_FIJO
    b.eq    1f
    mov     w0, #0
    ldp     x30, xzr, [sp], #16
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
    cmp     x22, #MAX_AST_NODES
    b.ge    9f
    mov     x0, x22
    lsl     x0, x0, #5
    add     x0, x21, x0
    mov     w1, #AST_VAR_DECL
    str     w1, [x0]
    str     w27, [x0, #4]
    str     w9, [x0, #8]
    str     w10, [x0, #12]
    str     x11, [x0, #16]
    str     xzr, [x0, #24]
    add     x22, x22, #1
    mov     w0, #1
    ldp     x30, xzr, [sp], #16
    ret
9:  mov     w0, #0
    ldp     x30, xzr, [sp], #16
    ret

parse_block_active:
    stp     x30, xzr, [sp, #-16]!
    bl      peek_type
    cmp     w0, #TOKEN_LBRACE
    b.ne    9f
    bl      advance_token
1:  bl      peek_type
    cmp     w0, #TOKEN_RBRACE
    b.eq    2f
    cmp     w0, #TOKEN_EOF
    b.eq    9f
    cmp     w0, #TOKEN_SEA
    b.eq    3f
    cmp     w0, #TOKEN_FIJO
    b.eq    3f
    bl      advance_token
    b       1b
3:  bl      parse_one_decl
    b       1b
2:  bl      advance_token
    mov     w0, #1
    ldp     x30, xzr, [sp], #16
    ret
9:  mov     w0, #0
    ldp     x30, xzr, [sp], #16
    ret

parse_si:
    stp     x30, xzr, [sp, #-32]!
    bl      advance_token
    bl      parse_expr
    str     x0, [sp, #16]
    ldr     x0, [sp, #16]
    cbnz    x0, 1f
    bl      skip_block
    b       2f
1:  bl      parse_block_active
2:  bl      peek_type
    cmp     w0, #TOKEN_SINO
    b.ne    8f
    bl      advance_token
    ldr     x0, [sp, #16]
    cbnz    x0, 3f
    bl      parse_block_active
    b       8f
3:  bl      skip_block
8:  ldp     x30, xzr, [sp], #32
    ret

iniciar_parser:
    stp     x19, x20, [sp, #-80]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]
    stp     x27, x30, [sp, #64]

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

parser_loop:
    bl      peek_type
    cmp     w0, #TOKEN_EOF
    b.eq    parser_fin
    cmp     w0, #TOKEN_SEA
    b.eq    do_decl
    cmp     w0, #TOKEN_FIJO
    b.eq    do_decl
    cmp     w0, #TOKEN_SI
    b.eq    do_si
    bl      advance_token
    b       parser_loop

do_decl:
    bl      parse_one_decl
    b       parser_loop

do_si:
    bl      parse_si
    b       parser_loop

parser_vacio:
    mov     x22, #0
    ldr     x0, =ast_root_ptr
    str     xzr, [x0]

parser_fin:
    ldr     x0, =ast_node_count
    str     x22, [x0]
    ldp     x27, x30, [sp, #64]
    ldp     x25, x26, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #80
    ret
