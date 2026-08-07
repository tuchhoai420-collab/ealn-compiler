.global iniciar_parser
.global ast_root_ptr
.global ast_node_count

.equ AST_VAR_DECL,  100
.equ AST_NODE_SIZE, 32
.equ MAX_AST_NODES, 512

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

.section .bss
    .align 3
    ast_root_ptr:   .skip 8
    ast_node_count: .skip 8
    expr_tok_idx:   .skip 8

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

parse_factor:
    str     x30, [sp, #-16]!
    bl      peek_type
    cmp     w0, #TOKEN_NUMBER
    b.eq    10f
    cmp     w0, #TOKEN_LPAREN
    b.eq    20f
    cmp     w0, #TOKEN_MINUS
    b.eq    30f
    mov     x0, #0
    ldr     x30, [sp], #16
    ret

10: bl      current_number_value
    mov     x1, x0
    bl      advance_token
    mov     x0, x1
    ldr     x30, [sp], #16
    ret

20: bl      advance_token
    bl      parse_expr
    mov     x1, x0
    bl      peek_type
    cmp     w0, #TOKEN_RPAREN
    b.ne    21f
    bl      advance_token
21: mov     x0, x1
    ldr     x30, [sp], #16
    ret

30: bl      advance_token
    bl      parse_factor
    neg     x0, x0
    ldr     x30, [sp], #16
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

    mov     x0, #(MAX_AST_NODES * AST_NODE_SIZE)
    bl      alloc_arena
    ldr     x1, =ast_root_ptr
    str     x0, [x1]
    mov     x21, x0
    mov     x22, #0
    mov     x23, #0

parser_loop:
    cmp     x23, x20
    b.ge    parser_fin

    mov     x0, x23
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w24, [x0]

    cmp     w24, #TOKEN_EOF
    b.eq    parser_fin
    cmp     w24, #TOKEN_SEA
    b.eq    es_decl
    cmp     w24, #TOKEN_FIJO
    b.eq    es_decl
    add     x23, x23, #1
    b       parser_loop

es_decl:
    mov     w27, w24

    add     x23, x23, #1
    cmp     x23, x20
    b.ge    parser_fin
    mov     x0, x23
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w24, [x0]
    ldr     w25, [x0, #4]
    ldr     w26, [x0, #8]
    cmp     w24, #TOKEN_IDENT
    b.ne    error_sintaxis
    mov     w9, w25
    mov     w10, w26

    add     x23, x23, #1
    cmp     x23, x20
    b.ge    parser_fin
    mov     x0, x23
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w24, [x0]
    cmp     w24, #TOKEN_ASSIGN
    b.ne    error_sintaxis

    add     x23, x23, #1
    ldr     x0, =expr_tok_idx
    str     x23, [x0]
    bl      parse_expr
    mov     x11, x0
    ldr     x0, =expr_tok_idx
    ldr     x23, [x0]

    cmp     x23, x20
    b.ge    crear_nodo
    mov     x0, x23
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w24, [x0]
    cmp     w24, #TOKEN_SEMI
    b.ne    crear_nodo
    add     x23, x23, #1

crear_nodo:
    cmp     x22, #MAX_AST_NODES
    b.ge    parser_fin
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
    b       parser_loop

error_sintaxis:
    add     x23, x23, #1
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
