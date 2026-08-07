.global iniciar_lexer
.global token_array_ptr
.global token_count

// Tipos de token (filosofía densa, enteros pequeños)
.equ TOKEN_EOF,     0
.equ TOKEN_SEA,     1
.equ TOKEN_FIJO,    2
.equ TOKEN_IDENT,   3
.equ TOKEN_NUMBER,  4
.equ TOKEN_ASSIGN,  5
.equ TOKEN_SEMI,    6
.equ TOKEN_UNKNOWN, 7

// Cada token ocupa 16 bytes (alineado):
// offset 0: type (u32)
// offset 4: start_offset (u32)
// offset 8: length (u32)
// offset 12: reserved / valor futuro
.equ TOKEN_SIZE, 16
.equ MAX_TOKENS, 2048

.section .bss
    .align 3
    token_array_ptr: .skip 8
    token_count:     .skip 8

.section .text

// ─────────────────────────────────────────────────────────────
// iniciar_lexer
// Lee fuente_ptr / fuente_size (zero-copy)
// Produce arreglo denso de tokens en la arena
// Convención: no destruye x28, usa x0-x7 temporalmente
// ─────────────────────────────────────────────────────────────
iniciar_lexer:
    // Prólogo: preservar registros callee-saved + lr
    stp     x19, x20, [sp, #-64]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x30, [sp, #48]     // x30 = lr

    // 1. Obtener puntero y tamaño del fuente mapeado
    ldr     x19, =fuente_ptr
    ldr     x19, [x19]              // x19 = base del fuente
    ldr     x20, =fuente_size
    ldr     x20, [x20]              // x20 = tamaño
    cbz     x19, lexer_fin          // si no hay fuente, salir limpio
    cbz     x20, lexer_fin

    // 2. Reservar espacio para tokens en la arena (MAX_TOKENS * 16)
    mov     x0, #(MAX_TOKENS * TOKEN_SIZE)
    bl      alloc_arena
    // x0 = base del arreglo de tokens
    ldr     x1, =token_array_ptr
    str     x0, [x1]
    mov     x21, x0                 // x21 = base tokens
    mov     x22, #0                 // x22 = contador de tokens

    // 3. Estado del scanner
    mov     x23, #0                 // x23 = posición actual (offset)
    mov     x24, x19                // x24 = puntero de lectura (base + pos)

scanner_loop:
    cmp     x23, x20
    b.ge    emitir_eof

    // Saltar whitespace
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
    // Guardar inicio del token
    mov     x25, x23                // x25 = start_offset

    // ¿Es dígito? → NUMBER
    cmp     w0, #'0'
    b.lt    no_numero
    cmp     w0, #'9'
    b.gt    no_numero

    // Consumir número
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
    // ¿Es letra o _ ? → IDENT o KEYWORD
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
    // Consumir identificador
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
    // Comparar contra keywords españoles (longitud fija para velocidad)
    // "sea" = 3 bytes
    mov     x0, x25                 // start
    add     x0, x19, x0             // dirección real
    sub     x1, x23, x25            // length

    // Probar "sea"
    cmp     x1, #3
    b.ne    probar_fijo
    ldrb    w2, [x0]
    cmp     w2, #'s'
    b.ne    probar_fijo
    ldrb    w2, [x0, #1]
    cmp     w2, #'e'
    b.ne    probar_fijo
    ldrb    w2, [x0, #2]
    cmp     w2, #'a'
    b.ne    probar_fijo
    mov     w0, #TOKEN_SEA
    b       guardar_token

probar_fijo:
    // "fijo" = 4 bytes
    cmp     x1, #4
    b.ne    es_ident_normal
    ldrb    w2, [x0]
    cmp     w2, #'f'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #1]
    cmp     w2, #'i'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #2]
    cmp     w2, #'j'
    b.ne    es_ident_normal
    ldrb    w2, [x0, #3]
    cmp     w2, #'o'
    b.ne    es_ident_normal
    mov     w0, #TOKEN_FIJO
    b       guardar_token

es_ident_normal:
    mov     w0, #TOKEN_IDENT
    b       guardar_token

no_ident:
    // Símbolos de un solo carácter
    cmp     w0, #'='
    b.ne    probar_semi
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_ASSIGN
    b       guardar_token

probar_semi:
    cmp     w0, #';'
    b.ne    desconocido
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_SEMI
    b       guardar_token

desconocido:
    // Caracter desconocido: avanzar uno y marcar UNKNOWN
    add     x23, x23, #1
    add     x24, x24, #1
    mov     w0, #TOKEN_UNKNOWN
    // cae a guardar_token

guardar_token:
    // w0 = tipo
    // x25 = start
    // length = x23 - x25
    cmp     x22, #MAX_TOKENS
    b.ge    lexer_fin               // proteger overflow

    // Calcular dirección del slot: base + contador * 16
    mov     x1, x22
    lsl     x1, x1, #4              // *16
    add     x1, x21, x1             // dirección del token

    str     w0, [x1]                // type
    str     w25, [x1, #4]           // start_offset
    sub     w2, w23, w25
    str     w2, [x1, #8]            // length
    str     wzr, [x1, #12]          // reserved

    add     x22, x22, #1            // incrementar contador
    b       scanner_loop

emitir_eof:
    // Token final EOF
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
    // Guardar contador final
    ldr     x0, =token_count
    str     x22, [x0]

    // Epílogo
    ldp     x25, x30, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #64
    ret
