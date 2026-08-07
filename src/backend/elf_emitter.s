.global emitir_elf

.equ AT_FDCWD, -100
.equ AST_VAR_DECL, 100

.section .bss
    .align 4
    opcode_buffer: .skip 4096

.section .data
    .align 4
    archivo_salida: .string "salida.out"

    elf_header:
        .byte 0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00
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

// ─────────────────────────────────────────────────────────────────
// emitir_movz_xN
// Entrada: w0 = valor inmediato (16 bits útiles)
//          w1 = número de registro destino (0-30)
//          x20 = puntero de escritura actual (se actualiza)
// Genera: MOVZ xN, #imm
// ─────────────────────────────────────────────────────────────────
emitir_movz_xN:
    // Plantilla base MOVZ: 0xD2800000
    // bits [20:5] = imm16
    // bits [9:5]  = Rd (pero en realidad Rd está en [4:0])
    // Formato correcto MOVZ (64-bit): 1 10 100101 hw=00 imm16 Rd
    // Codificación: 0xD2800000 | (imm16 << 5) | Rd

    and     w0, w0, #0xFFFF         // solo 16 bits
    and     w1, w1, #0x1F           // registro 0-31

    mov     w2, #0xD2800000
    orr     w2, w2, w1              // Rd en bits [4:0]
    lsl     w0, w0, #5
    orr     w2, w2, w0              // imm16 en bits [20:5]

    str     w2, [x20], #4
    ret

// ─────────────────────────────────────────────────────────────────
// emitir_elf
// Lee el AST real producido por el parser (arreglo denso de nodos)
// Genera opcodes ARM64 y escribe un ELF64 ejecutable
// ─────────────────────────────────────────────────────────────────
emitir_elf:
    // Prólogo
    stp     x19, x20, [sp, #-64]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x30, [sp, #48]

    ldr     x19, =opcode_buffer
    mov     x20, x19                // x20 = cursor de escritura de opcodes

    // ── Leer AST ────────────────────────────────────────────────
    ldr     x21, =ast_root_ptr
    ldr     x21, [x21]              // x21 = base de nodos
    ldr     x22, =ast_node_count
    ldr     x22, [x22]              // x22 = cantidad de nodos

    cbz     x21, fallback_opcodes
    cbz     x22, fallback_opcodes

    // ── Generar código a partir de cada nodo ────────────────────
    mov     x23, #0                 // índice de nodo
    mov     w24, #0                 // registro destino actual (x0, x1, ...)

generar_loop:
    cmp     x23, x22
    b.ge    escribir_epilogo

    // Dirección del nodo actual (cada uno 32 bytes)
    mov     x0, x23
    lsl     x0, x0, #5              // *32
    add     x0, x21, x0

    ldr     w1, [x0]                // type
    cmp     w1, #AST_VAR_DECL
    b.ne    siguiente_nodo

    // Es una declaración de variable
    // Valor ya parseado está en offset 16 (u64)
    ldr     x2, [x0, #16]           // x2 = valor

    // Emitir MOVZ xN, #valor  (solo parte baja por ahora)
    mov     w0, w2                  // valor (bajo 16 bits)
    mov     w1, w24                 // registro destino
    bl      emitir_movz_xN

    // Avanzar al siguiente registro (máx x7 para no tocar especiales)
    add     w24, w24, #1
    cmp     w24, #8
    b.lt    siguiente_nodo
    mov     w24, #0                 // reiniciar si hay muchos

siguiente_nodo:
    add     x23, x23, #1
    b       generar_loop

fallback_opcodes:
    // Si no hay AST válido: MOVZ x0, #0
    mov     w0, #0
    mov     w1, #0
    bl      emitir_movz_xN

escribir_epilogo:
    // MOV x8, #93   (syscall exit)
    // Codificación MOVZ x8, #93
    mov     w0, #93
    mov     w1, #8
    bl      emitir_movz_xN

    // SVC #0
    // Codificación: 0xD4000001
    mov     w0, #0x0001
    movk    w0, #0xD400, lsl #16
    str     w0, [x20], #4

    // ── Actualizar tamaños en program_header ────────────────────
    sub     x25, x20, x19           // x25 = bytes de código generado
    mov     x5, #120                // header + phdr = 64+56
    add     x5, x5, x25

    ldr     x6, =program_header
    str     x5, [x6, #32]           // p_filesz
    str     x5, [x6, #40]           // p_memsz

    // ── Crear archivo de salida ─────────────────────────────────
    mov     x0, AT_FDCWD
    ldr     x1, =archivo_salida
    mov     x2, #577                // O_WRONLY | O_CREAT | O_TRUNC
    mov     x3, #493                // 0755
    mov     x8, #56                 // openat
    svc     #0
    mov     x22, x0                 // fd

    // write ELF header
    mov     x0, x22
    ldr     x1, =elf_header
    mov     x2, #64
    mov     x8, #64
    svc     #0

    // write program header
    mov     x0, x22
    ldr     x1, =program_header
    mov     x2, #56
    mov     x8, #64
    svc     #0

    // write opcodes
    mov     x0, x22
    mov     x1, x19
    mov     x2, x25
    mov     x8, #64
    svc     #0

    // close
    mov     x0, x22
    mov     x8, #57
    svc     #0

    // Epílogo
    ldp     x25, x30, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #64
    ret
