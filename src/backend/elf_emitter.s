.global emitir_elf

.equ AT_FDCWD,     -100
.equ AST_VAR_DECL, 100
.equ AST_ASSIGN,   101
.equ AST_WHILE,    102

.section .bss
    .align 4
    opcode_buffer: .skip 8192
    reg_name_start: .skip 32
    reg_name_len:   .skip 32

.section .data
    .align 4
    archivo_salida: .string "salida.out"
    elf_header:
        .byte 0x7F, 0x45, 0x4C, 0x46
        .byte 0x02, 0x01, 0x01, 0x00
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

emitir_movz_xN:
    and     w0, w0, #0xFFFF
    and     w1, w1, #0x1F
    mov     w2, #0xD2800000
    orr     w2, w2, w1
    lsl     w0, w0, #5
    orr     w2, w2, w0
    str     w2, [x20], #4
    ret

emitir_sub_imm:
    and     w0, w0, #0x1F
    and     w1, w1, #0xFFF
    mov     w2, #0xD1000000
    orr     w2, w2, w0
    lsl     w0, w0, #5
    orr     w2, w2, w0
    lsl     w1, w1, #10
    orr     w2, w2, w1
    str     w2, [x20], #4
    ret

emitir_add_imm:
    and     w0, w0, #0x1F
    and     w1, w1, #0xFFF
    mov     w2, #0x91000000
    orr     w2, w2, w0
    lsl     w0, w0, #5
    orr     w2, w2, w0
    lsl     w1, w1, #10
    orr     w2, w2, w1
    str     w2, [x20], #4
    ret

emitir_cmp0:
    and     w0, w0, #0x1F
    mov     w2, #0xF100001F
    lsl     w0, w0, #5
    orr     w2, w2, w0
    str     w2, [x20], #4
    ret

emitir_beq:
    and     w0, w0, #0x7FFFF
    mov     w2, #0x54000000
    lsl     w0, w0, #5
    orr     w2, w2, w0
    str     w2, [x20], #4
    ret

emitir_b:
    and     w0, w0, #0x3FFFFFF
    mov     w2, #0x14000000
    orr     w2, w2, w0
    str     w2, [x20], #4
    ret

find_reg_by_name:
    stp     x30, xzr, [sp, #-32]!
    stp     x22, x23, [sp, #16]
    mov     x22, x0
    mov     x23, x1
    mov     x9, #0
1:  cmp     x9, #8
    b.ge    9f
    ldr     x0, =reg_name_len
    ldr     w1, [x0, x9, lsl #2]
    cbz     w1, 9f
    cmp     x1, x23
    b.ne    2f
    ldr     x0, =reg_name_start
    ldr     w2, [x0, x9, lsl #2]
    ldr     x4, =fuente_ptr
    ldr     x4, [x4]
    add     x0, x4, x22
    add     x2, x4, x2
    mov     x1, x23
3:  cbz     x1, 4f
    ldrb    w5, [x0], #1
    ldrb    w6, [x2], #1
    cmp     w5, w6
    b.ne    2f
    sub     x1, x1, #1
    b       3b
4:  mov     w0, w9
    ldp     x22, x23, [sp, #16]
    ldp     x30, xzr, [sp], #32
    ret
2:  add     x9, x9, #1
    b       1b
9:  mov     w0, #0xFF
    ldp     x22, x23, [sp, #16]
    ldp     x30, xzr, [sp], #32
    ret

emitir_elf:
    stp     x19, x20, [sp, #-80]!
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]
    stp     x27, x30, [sp, #64]

    ldr     x19, =opcode_buffer
    mov     x20, x19

    ldr     x0, =reg_name_len
    mov     x1, #8
0:  str     wzr, [x0], #4
    subs    x1, x1, #1
    b.ne    0b

    ldr     x21, =ast_root_ptr
    ldr     x21, [x21]
    ldr     x22, =ast_node_count
    ldr     x22, [x22]
    cbz     x21, fallback
    cbz     x22, fallback

    mov     x23, #0
    mov     w24, #0

gen_loop:
    cmp     x23, x22
    b.ge    epilogo
    mov     x0, x23
    lsl     x0, x0, #5
    add     x0, x21, x0
    ldr     w1, [x0]
    cmp     w1, #AST_VAR_DECL
    b.eq    do_decl
    cmp     w1, #AST_ASSIGN
    b.eq    do_assign
    cmp     w1, #AST_WHILE
    b.eq    do_while
    b       next

do_decl:
    ldr     w2, [x0, #8]
    ldr     w3, [x0, #12]
    ldr     x4, [x0, #16]
    cmp     w24, #8
    b.ge    next
    ldr     x5, =reg_name_start
    str     w2, [x5, x24, lsl #2]
    ldr     x5, =reg_name_len
    str     w3, [x5, x24, lsl #2]
    mov     w0, w4
    mov     w1, w24
    bl      emitir_movz_xN
    add     w24, w24, #1
    b       next

do_assign:
    ldr     w26, [x0, #4]
    ldr     w2, [x0, #8]
    ldr     w3, [x0, #12]
    ldr     x4, [x0, #16]
    mov     x0, x2
    mov     x1, x3
    bl      find_reg_by_name
    cmp     w0, #0xFF
    b.eq    next
    mov     w1, w4
    cmp     w26, #1
    b.eq    1f
    cmp     w26, #2
    b.eq    2f
    b       next
1:  bl      emitir_sub_imm
    b       next
2:  bl      emitir_add_imm
    b       next

do_while:
    ldr     w15, [x0, #4]
    ldr     w2, [x0, #8]
    ldr     w3, [x0, #12]
    mov     x0, x2
    mov     x1, x3
    bl      find_reg_by_name
    cmp     w0, #0xFF
    b.eq    skip_wb
    mov     w25, w0
    mov     x27, x20
    mov     w0, w25
    bl      emitir_cmp0
    str     x20, [sp, #-16]!
    mov     w0, #0
    bl      emitir_beq
    add     x23, x23, #1
blp:
    cbz     w15, bld
    cmp     x23, x22
    b.ge    bld
    mov     x0, x23
    lsl     x0, x0, #5
    add     x0, x21, x0
    ldr     w1, [x0]
    cmp     w1, #AST_ASSIGN
    b.ne    bln
    ldr     w26, [x0, #4]
    ldr     w2, [x0, #8]
    ldr     w3, [x0, #12]
    ldr     x4, [x0, #16]
    mov     x0, x2
    mov     x1, x3
    bl      find_reg_by_name
    cmp     w0, #0xFF
    b.eq    bln
    mov     w1, w4
    cmp     w26, #1
    b.ne    11f
    bl      emitir_sub_imm
    b       bln
11: cmp     w26, #2
    b.ne    bln
    bl      emitir_add_imm
bln:
    add     x23, x23, #1
    sub     w15, w15, #1
    b       blp
bld:
    sub     x0, x27, x20
    asr     x0, x0, #2
    bl      emitir_b
    ldr     x1, [sp], #16
    sub     x0, x20, x1
    asr     x0, x0, #2
    and     w0, w0, #0x7FFFF
    mov     w2, #0x54000000
    lsl     w0, w0, #5
    orr     w2, w2, w0
    str     w2, [x1]
    b       gen_loop

skip_wb:
    mov     x0, x23
    lsl     x0, x0, #5
    add     x0, x21, x0
    ldr     w15, [x0, #4]
    add     x23, x23, #1
    add     x23, x23, x15
    b       gen_loop

next:
    add     x23, x23, #1
    b       gen_loop

fallback:
    mov     w0, #0
    mov     w1, #0
    bl      emitir_movz_xN

epilogo:
    mov     w0, #93
    mov     w1, #8
    bl      emitir_movz_xN
    mov     w0, #0x0001
    movk    w0, #0xD400, lsl #16
    str     w0, [x20], #4
    sub     x25, x20, x19
    mov     x5, #120
    add     x5, x5, x25
    ldr     x6, =program_header
    str     x5, [x6, #32]
    str     x5, [x6, #40]
    mov     x0, AT_FDCWD
    ldr     x1, =archivo_salida
    mov     x2, #577
    mov     x3, #493
    mov     x8, #56
    svc     #0
    mov     x22, x0
    mov     x0, x22
    ldr     x1, =elf_header
    mov     x2, #64
    mov     x8, #64
    svc     #0
    mov     x0, x22
    ldr     x1, =program_header
    mov     x2, #56
    mov     x8, #64
    svc     #0
    mov     x0, x22
    mov     x1, x19
    mov     x2, x25
    mov     x8, #64
    svc     #0
    mov     x0, x22
    mov     x8, #57
    svc     #0
    ldp     x27, x30, [sp, #64]
    ldp     x25, x26, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #80
    ret
