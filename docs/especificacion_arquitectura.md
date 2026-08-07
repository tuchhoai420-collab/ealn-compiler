# Especificación de Arquitectura de Lenguaje Nativo ARM64 (EALN-64)

## Visión
Lenguaje de estado denso, costo predecible y transformación irreversible.  
No modela objetos ni intenciones humanas. Modela campos, slots y trayectorias que colapsan.

## 1. Filosofía Data-Oriented
- Estructuras densas SoA (Structure of Arrays).
- Cero punteros sueltos en el hot path.
- Optimización implícita para SIMD/NEON en fases posteriores.
- Costo de cada construcción del lenguaje es visible y acotado.

## 2. Mapa de Registros Propietario
- `x0 – x7`  : Valores vivos / resultados de expresiones
- `x8`       : Número de syscall (Linux AArch64)
- `x9 – x15` : Temporales de corta vida
- `x19 – x27`: Callee-saved del compilador
- `x28`      : Puntero de estado global del agente (futuro)
- `v0 – v15` : Acumuladores de campo SIMD (fase posterior)

## 3. Memoria Zero-Pause
- Arena única de tamaño fijo (64 MB en la implementación actual).
- Asignación vía `sys_mmap` (MAP_PRIVATE | MAP_ANONYMOUS).
- Liberación O(1) reseteando un solo offset.
- Sin garbage collector. Sin realloc oculto.

## 4. Pipeline del compilador
1. `init_arena`
2. `map_file_zero_copy` (mmap del fuente)
3. `iniciar_lexer` → arreglo denso de tokens
4. `iniciar_parser` → IR / nodos densos
5. `emitir_elf` → ELF64 mínimo + código nativo

## 5. Estado actual (Fase 1 — cerrada)
```
decl  := ('sea' | 'fijo') IDENT '=' NUMBER ';'
prog  := decl*
```
- Funciona de extremo a extremo en RPi.
- Los valores se reflejan en registros y en el exit status.

## 6. Siguiente (Fase 2)
Ver documento completo: [`ESPECIFICACION_FASE2.md`](ESPECIFICACION_FASE2.md)

Resumen:
- Expresiones aritméticas (`+ - * /` y unario `-`)
- Control de flujo (`si` / `sino` / `mientras`)
- Tabla de slots densa (SoA)
- IR lineal denso
- Constant folding y strength reduction
- Saltos directos AArch64

## 7. Convención de salida actual
- Binario generado: `salida.out`
- Exit status = valor final en `x0`
