# Especificación de Arquitectura de Lenguaje Nativo ARM64 (EALN-64)

## 1. Filosofía Data-Oriented
- Estructuras densas SoA (Structure of Arrays).
- Cero punteros sueltos en el hot path.
- Optimización implícita para SIMD/NEON en fases futuras.

## 2. Mapa de Registros Propietario (fase actual)
- `x0 – x3`  : Punteros de contexto / arenas
- `x4 – x7`  : Argumentos escalares / valores temporales
- `x8`       : Número de syscall (Linux AArch64)
- `x19 – x28`: Callee-saved del compilador
- `x28`      : Reservado para estado global del agente (futuro)
- `v0 – v15` : Acumuladores SIMD (fase posterior)

## 3. Memoria Zero-Pause
- Arena única de tamaño fijo (actualmente 64 MB).
- Asignación vía `sys_mmap` (MAP_PRIVATE | MAP_ANONYMOUS).
- Liberación O(1) reseteando un solo offset.
- Sin garbage collector.

## 4. Pipeline actual del compilador
1. `init_arena`
2. `map_file_zero_copy` (mmap del fuente)
3. `iniciar_lexer` → arreglo denso de tokens (16 B/token)
4. `iniciar_parser` → arreglo denso de nodos AST (32 B/nodo)
5. `emitir_elf` → genera ELF64 mínimo + opcodes MOVZ + exit

## 5. Gramática mínima soportada (fase 1)
```
decl  := ('sea' | 'fijo') IDENT '=' NUMBER ';'
prog  := decl*
```

## 6. Convención de salida
- El binario generado se llama `salida.out`.
- Cada declaración de variable emite un `MOVZ xN, #valor`.
- El programa termina con `MOVZ x8, #93 ; SVC #0` (exit).
