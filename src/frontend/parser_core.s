.global iniciar_parser
.global ast_root_ptr
.global ast_node_count

// Tipos de nodo AST (densos, enteros pequeños)
.equ AST_PROGRAM,   0
.equ AST_VAR_DECL,  100
.equ AST_EOF,       255

// Tamaño de cada nodo AST: 32 bytes alineados
// 0:  type (u32)
// 4:  flags / keyword (u32)   1=sea, 2=fijo
// 8:  name_start (u32)
// 12: name_len (u32)
// 16: value (u64)             número parseado
// 24: reserved (u64)
.equ AST_NODE_SIZE, 32
.equ MAX_AST_NODES, 512

.section .bss
    .align 3
    ast_root_ptr:   .skip 8
    ast_node_count: .skip 8

.section .text

// ─────────────────────────────────────────────────────────────
// parsear_numero_token
// Entrada: x0 = start_offset del token NUMBER en el fuente
//          x1 = length
// Salida:  x0 = valor u64
// ─────────────────────────────────────────────────────────────
parsear_numero_token:
    ldr     x2, =fuente_ptr
    ldr     x2, [x2]
    add     x2, x2, x0              // x2 = dirección del dígito
    mov     x0, #0                  // acumulador
    mov     x3, #10
1:
    cbz     x1, 2f
    ldrb    w4, [x2], #1
    sub     w4, w4, #'0'
    mul     x0, x0, x3
    add     x0, x0, x4
    sub     x1, x1, #1
    b       1b
2:
    ret

// ─────────────────────────────────────────────────────────────
// iniciar_parser
// Consume el arreglo de tokens producido por el lexer
// Construye AST denso (arreglo de nodos) en la arena
// Filosofía: cero punteros sueltos, todo contiguo, O(1) acceso
// ─────────────────────────────────────────────────────────────
iniciar_parser:
    // Prólogo
    stp     x19, x20, [sp, #-80]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]
    stp     x27, x30, [sp, #64]

    // 1. Obtener tokens del lexer
    ldr     x19, =token_array_ptr
    ldr     x19, [x19]              // x19 = base tokens
    ldr     x20, =token_count
    ldr     x20, [x20]              // x20 = cantidad de tokens
    cbz     x19, parser_vacio
    cbz     x20, parser_vacio

    // 2. Reservar espacio para nodos AST en la arena
    mov     x0, #(MAX_AST_NODES * AST_NODE_SIZE)
    bl      alloc_arena
    ldr     x1, =ast_root_ptr
    str     x0, [x1]
    mov     x21, x0                 // x21 = base del AST
    mov     x22, #0                 // x22 = contador de nodos

    // 3. Índice de token actual
    mov     x23, #0                 // x23 = índice token

parser_loop:
    cmp     x23, x20
    b.ge    parser_fin

    // Cargar token actual: type en w0
    mov     x0, x23
    lsl     x0, x0, #4              // *16
    add     x0, x19, x0
    ldr     w24, [x0]               // w24 = type
    ldr     w25, [x0, #4]           // w25 = start
    ldr     w26, [x0, #8]           // w26 = length

    // ¿EOF?
    cmp     w24, #0                 // TOKEN_EOF
    b.eq    parser_fin

    // Esperamos SEA (1) o FIJO (2)
    cmp     w24, #1
    b.eq    es_decl
    cmp     w24, #2
    b.eq    es_decl
    // Si no es declaración, saltamos el token desconocido y seguimos
    add     x23, x23, #1
    b       parser_loop

es_decl:
    // Guardamos el keyword (1 o 2)
    mov     w27, w24                // w27 = keyword

    // Avanzar al siguiente token (debe ser IDENT)
    add     x23, x23, #1
    cmp     x23, x20
    b.ge    parser_fin

    mov     x0, x23
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w24, [x0]               // type
    ldr     w25, [x0, #4]           // start del nombre
    ldr     w26, [x0, #8]           // len del nombre

    cmp     w24, #3                 // TOKEN_IDENT
    b.ne    error_sintaxis

    // Guardar datos del nombre temporalmente
    mov     w9, w25                 // name_start
    mov     w10, w26                // name_len

    // Avanzar: debe ser ASSIGN (=)
    add     x23, x23, #1
    cmp     x23, x20
    b.ge    parser_fin

    mov     x0, x23
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w24, [x0]
    cmp     w24, #5                 // TOKEN_ASSIGN
    b.ne    error_sintaxis

    // Avanzar: debe ser NUMBER
    add     x23, x23, #1
    cmp     x23, x20
    b.ge    parser_fin

    mov     x0, x23
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w24, [x0]
    ldr     w25, [x0, #4]           // start del número
    ldr     w26, [x0, #8]           // len del número

    cmp     w24, #4                 // TOKEN_NUMBER
    b.ne    error_sintaxis

    // Parsear el valor numérico
    mov     x0, x25                 // start
    mov     x1, x26                 // length
    bl      parsear_numero_token    // resultado en x0
    mov     x11, x0                 // x11 = valor

    // Avanzar: debe ser SEMI (;)
    add     x23, x23, #1
    cmp     x23, x20
    b.ge    crear_nodo              // permitimos EOF después del número por ahora
    mov     x0, x23
    lsl     x0, x0, #4
    add     x0, x19, x0
    ldr     w24, [x0]
    cmp     w24, #6                 // TOKEN_SEMI
    b.ne    error_sintaxis
    add     x23, x23, #1            // consumir el ;

crear_nodo:
    // Verificar espacio
    cmp     x22, #MAX_AST_NODES
    b.ge    parser_fin

    // Dirección del nuevo nodo
    mov     x0, x22
    lsl     x0, x0, #5              // *32
    add     x0, x21, x0

    // Escribir nodo
    mov     w1, #AST_VAR_DECL
    str     w1, [x0]                // type
    str     w27, [x0, #4]           // keyword (sea/fijo)
    str     w9, [x0, #8]            // name_start
    str     w10, [x0, #12]          // name_len
    str     x11, [x0, #16]          // value (u64)
    str     xzr, [x0, #24]          // reserved

    add     x22, x22, #1
    b       parser_loop

error_sintaxis:
    // Por ahora: saltamos el token conflictivo y seguimos
    // (en el futuro emitiremos diagnóstico en español)
    add     x23, x23, #1
    b       parser_loop

parser_vacio:
    mov     x22, #0
    ldr     x0, =ast_root_ptr
    str     xzr, [x0]

parser_fin:
    // Guardar cantidad de nodos
    ldr     x0, =ast_node_count
    str     x22, [x0]

    // Epílogo
    ldp     x27, x30, [sp, #64]
    ldp     x25, x26, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #80
    ret
