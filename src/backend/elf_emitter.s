.global emitir_elf

.equ AT_FDCWD,     -100
.equ AST_VAR_DECL, 100

.section .bss
    .align 4
    opcode_buffer: .skip 4096

.section .data
    .align 4
    archivo_salida: .string "salida.out"

    // ELF64 header (64 bytes) — entry point = 0x400078 (después de ehdr+phdr)
    elf_header:
        .byte 0x7F, 0x45, 0x4C, 0x46     // magic
        .byte 0x02, 0x01, 0x01, 0x00     // class=64, data=LE, version=1
        .skip 8
        .short 2                         // e_type = ET_EXEC
        .short 183                       // e_machine = EM_AARCH64
        .word 1                          // e_version
        .quad 0x400078                   // e_entry
        .quad 64                         // e_phoff
        .quad 0                          // e_shoff
        .word 0                          // e_flags
        .short 64                        // e_ehsize
        .short 56                        // e_phentsize
        .short 1                         // e_phnum
        .short 0, 0, 0                   // shentsize, shnum, shstrndx

    // Program header (56 bytes) — un solo segmento PT_LOAD RX
    program_header:
        .word 1                          // p_type = PT_LOAD
        .word 5                          // p_flags = PF_R | PF_X
        .quad 0                          // p_offset
        .quad 0x400000                   // p_vaddr
        .quad 0x400000                   // p_paddr
        .quad 0                          // p_filesz (se rellena en runtime)
        .quad 0                          // p_memsz  (se rellena en runtime)
        .quad 0x10000                    // p_align

.section .text

// ─────────────────────────────────────────────────────────────────
// emitir_movz_xN
// w0 = imm16, w1 = Rd, x20 = cursor (se actualiza +4)
// Genera: MOVZ xRd, #imm
// ─────────────────────────────────────────────────────────────────
emitir_movz_xN:
    and     w0, w0, #0xFFFF
    and     w1, w1, #0x1F
    mov     w2, #0xD2800000
    orr     w2, w2, w1              // Rd
    lsl     w0, w0, #5
    orr     w2, w2, w0              // imm16
    str     w2, [x20], #4
    ret

// ─────────────────────────────────────────────────────────────────
// emitir_elf
// Lee AST denso → genera MOVZ por cada VAR_DECL + exit
// Escribe ELF64 mínimo ejecutable en "salida.out"
// ─────────────────────────────────────────────────────────────────
emitir_elf:
    stp     x19, x20, [sp, #-64]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x30, [sp, #48]

    ldr     x19, =opcode_buffer
    mov     x20, x19                // cursor de opcodes

    // Leer AST
    ldr     x21, =ast_root_ptr
    ldr     x21, [x21]
    ldr     x22, =ast_node_count
    ldr     x22, [x22]

    cbz     x21, fallback_opcodes
    cbz     x22, fallback_opcodes

    // Generar código
    mov     x23, #0                 // índice de nodo
    mov     w24, #0                 // próximo registro destino (x0..)

generar_loop:
    cmp     x23, x22
    b.ge    escribir_epilogo

    // nodo = base + índice * 32
    mov     x0, x23
    lsl     x0, x0, #5
    add     x0, x21, x0

    ldr     w1, [x0]                // type
    cmp     w1, #AST_VAR_DECL
    b.ne    siguiente_nodo

    // valor u64 en offset 16
    ldr     x2, [x0, #16]

    // MOVZ xN, #valor (parte baja 16 bits por ahora)
    mov     w0, w2
    mov     w1, w24
    bl      emitir_movz_xN

    // siguiente registro (x0..x7)
    add     w24, w24, #1
    cmp     w24, #8
    b.lt    siguiente_nodo
    mov     w24, #0

siguiente_nodo:
    add     x23, x23, #1
    b       generar_loop

fallback_opcodes:
    // AST vacío → MOVZ x0, #0
    mov     w0, #0
    mov     w1, #0
    bl      emitir_movz_xN

escribir_epilogo:
    // MOVZ x8, #93   (sys_exit)
    mov     w0, #93
    mov     w1, #8
    bl      emitir_movz_xN

    // SVC #0
    mov     w0, #0x0001
    movk    w0, #0xD400, lsl #16
    str     w0, [x20], #4

    // Actualizar p_filesz / p_memsz
    sub     x25, x20, x19           // bytes de código
    mov     x5, #120                // 64 + 56
    add     x5, x5, x25

    ldr     x6, =program_header
    str     x5, [x6, #32]           // p_filesz
    str     x5, [x6, #40]           // p_memsz

    // openat(AT_FDCWD, "salida.out", O_WRONLY|O_CREAT|O_TRUNC, 0755)
    mov     x0, AT_FDCWD
    ldr     x1, =archivo_salida
    mov     x2, #577                // O_WRONLY|O_CREAT|O_TRUNC
    mov     x3, #493                // 0755
    mov     x8, #56
    svc     #0
    mov     x22, x0                 // fd

    // write ehdr
    mov     x0, x22
    ldr     x1, =elf_header
    mov     x2, #64
    mov     x8, #64
    svc     #0

    // write phdr
    mov     x0, x22
    ldr     x1, =program_header
    mov     x2, #56
    mov     x8, #64
    svc     #0

    // write code
    mov     x0, x22
    mov     x1, x19
    mov     x2, x25
    mov     x8, #64
    svc     #0

    // close
    mov     x0, x22
    mov     x8, #57
    svc     #0

    ldp     x25, x30, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #64
    ret
