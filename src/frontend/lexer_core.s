.global iniciar_lexer
.global token_array_ptr
.global token_count

// Tipos de token (densos, enteros pequeños)
.equ TOKEN_EOF,      0
.equ TOKEN_SEA,      1
.equ TOKEN_FIJO,     2
.equ TOKEN_IDENT,    3
.equ TOKEN_NUMBER,   4
.equ TOKEN_ASSIGN,   5
.equ TOKEN_SEMI,     6
.equ TOKEN_UNKNOWN,  7
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

.equ TOKEN_SIZE, 16
.equ MAX_TOKENS, 2048

.section .bss
    .align 3
    token_array_ptr: .skip 8
    token_count:     .skip 8

.section .text

iniciar_lexer:
    stp     x19, x20, [sp, #-64]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x30, [sp, #48]

    ldr     x19, =fuente_ptr
    ldr     x19, [x19]
    ldr     x20, =fuente_size
    ldr     x20, [x20]
    cbz     x19, lexer_fin
    cbz     x20, lexer_fin

    mov     x0, #(MAX_TOKENS * TOKEN_SIZE)
    bl      alloc_arena
    ldr     x1, =token_array_ptr
    str     x0, [x1]
    mov     x21, x0
    mov     x22, #0

    mov     x23, #0
    mov     x24, x19

scanner_loop:
    cmp     x23, x20
    b.ge    emitir_eof

    ldrb    w0, [x24]
    cmp     w0, #' '
    b.eq    avanzar_ws
    cmp     w0, #'\t'
    b.eq    avanzar_ws
    cmp     w0, #'\n'
    b.eq    avanzar_ws
    cmp     w0, #'\r'
    b.eq    avanzar_ws
    b       no_whitespace

avanzar_ws:
    add     x23, x23, #1
    add     x24, x24, #1
    b       scanner_loop

no_whitespace:
    mov     x25, x23

    // NUMBER
    cmp     w0, #'0'
    b.lt    no_numero
    cmp     w0, #'9'
    b.gt    no_numero
numero_loop:
    add     x23, x23, #1
    add     x24, x24, #1
    cmp     x23, x20
    b.ge    emitir_number
    ldrb    w0, [x24]
    cmp     w0, #'0'
    b.lt    emitir_number
    cmp     w0, #'9'
    b.le    numero_loop
emitir_number:
    mov     w0, #TOKEN_NUMBER
    b       guardar_token

no_numero:
    // IDENT / KEYWORD
    cmp     w0, #'_'
    b.eq    es_ident
    cmp     w0, #'a'
    b.lt    no_ident
    cmp     w0, #'z'
    b.le    es_ident
    cmp     w0, #'A'
    b.lt    no_ident
    cmp     w0, #'Z'
    b.le    es_ident
    b       no_ident

es_ident:
ident_loop:
    add     x23, x23, #1
    add     x24, x24, #1
    cmp     x23, x20
    b.ge    clasificar_ident
    ldrb    w0, [x24]
    cmp     w0, #'_'
    b.eq    ident_loop
    cmp     w0, #'0'
    b.lt    clasificar_ident
    cmp     w0, #'9'
    b.le    ident_loop
    cmp     w0, #'a'
    b.lt    clasificar_ident
    cmp     w0, #'z'
    b.le    ident_loop
    cmp     w0, #'A'
    b.lt    clasificar_ident
    cmp     w0, #'Z'
    b.le    ident_loop
    b       clasificar_ident

clasificar_ident:
    mov     x0, x25
    add     x0, x19, x0
    sub     x1, x23, x25

    // "sea" (3)
    cmp     x1, #3
    b.ne    1f
    ldrb    w2, [x0]
    cmp     w2, #'s'
    b.ne    1f
    ldrb    w2, [x0, #1]
    cmp     w2, #'e'
    b.ne    1f
    ldrb    w2, [x0, #2]
    cmp     w2, #'a'
    b.ne    1f
    mov     w0, #TOKEN_SEA
    b       guardar_token
1:
    // "fijo" (4)
    cmp     x1, #4
    b.ne    2f
    ldrb    w2, [x0]
    cmp     w2, #'f'
    b.ne    2f
    ldrb    w2, [x0, #1]
    cmp     w2, #'i'
    b.ne    2f
    ldrb    w2, [x0, #2]
    cmp     w2, #'j'
    b.ne    2f
    ldrb    w2, [x0, #3]
    cmp     w2, #'o'
    b.ne    2f
    mov     w0, #TOKEN_FIJO
    b       guardar_token
2:
    // "si" (2)
    cmp     x1, #2
    b.ne    3f
    ldrb    w2, [x0]
    cmp     w2, #'s'
    b.ne    3f
    ldrb    w2, [x0, #1]
    cmp     w2, #'i'
    b.ne    3f
    mov     w0, #TOKEN_SI
    b       guardar_token
3:
    // "sino" (4)
    cmp     x1, #4
    b.ne    4f
    ldrb    w2, [x0]
    cmp     w2, #'s'
    b.ne    4f
    ldrb    w2, [x0, #1]
    cmp     w2, #'i'
    b.ne    4f
    ldrb    w2, [x0, #2]
    cmp     w2, #'n'
    b.ne    4f
    ldrb    w2, [x0, #3]
    cmp     w2, #'o'
    b.ne    4f
    mov     w0, #TOKEN_SINO
    b       guardar_token
4:
    // "mientras" (8)
    cmp     x1, #8
    b.ne    es_ident_normal
    ldrb    w2, [x0]
    cmp     w2, #'m'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #1]
    cmp     w2, #'i'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #2]
    cmp     w2, #'e'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #3]
    cmp     w2, #'n'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #4]
    cmp     w2, #'t'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #5]
    cmp     w2, #'r'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #6]
    cmp     w2, #'a'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #7]
    cmp     w2, #'s'
    b.ne    es_ident_normal
    mov     w0, #TOKEN_MIENTRAS
    b       guardar_token

es_ident_normal:
    mov     w0, #TOKEN_IDENT
    b       guardar_token

no_ident:
    // Símbolos de un carácter
    cmp     w0, #'='
    b.ne    10f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_ASSIGN
    b       guardar_token
10:
    cmp     w0, #';'
    b.ne    11f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_SEMI
    b       guardar_token
11:
    cmp     w0, #'+'
    b.ne    12f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_PLUS
    b       guardar_token
12:
    cmp     w0, #'-'
    b.ne    13f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_MINUS
    b       guardar_token
13:
    cmp     w0, #'*'
    b.ne    14f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_STAR
    b       guardar_token
14:
    cmp     w0, #'/'
    b.ne    15f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_SLASH
    b       guardar_token
15:
    cmp     w0, #'('
    b.ne    16f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_LPAREN
    b       guardar_token
16:
    cmp     w0, #')'
    b.ne    17f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_RPAREN
    b       guardar_token
17:
    cmp     w0, #'{'
    b.ne    18f
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_LBRACE
    b       guardar_token
18:
    cmp     w0, #'}'
    b.ne    desconocido
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_RBRACE
    b       guardar_token

desconocido:
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_UNKNOWN

guardar_token:
    cmp     x22, #MAX_TOKENS
    b.ge    lexer_fin
    mov     x1, x22
    lsl     x1, x1, #4
    add     x1, x21, x1
    str     w0, [x1]
    str     w25, [x1, #4]
    sub     w2, w23, w25
    str     w2, [x1, #8]
    str     wzr, [x1, #12]
    add     x22, x22, #1
    b       scanner_loop

emitir_eof:
    cmp     x22, #MAX_TOKENS
    b.ge    lexer_fin
    mov     x1, x22
    lsl     x1, x1, #4
    add     x1, x21, x1
    mov     w0, #TOKEN_EOF
    str     w0, [x1]
    str     wzr, [x1, #4]
    str     wzr, [x1, #8]
    str     wzr, [x1, #12]
    add     x22, x22, #1

lexer_fin:
    ldr     x0, =token_count
    str     x22, [x0]
    ldp     x25, x30, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #64
    ret
