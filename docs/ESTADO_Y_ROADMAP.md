# EALN-64 — Estado del proyecto y siguientes acciones

Fecha: 2026-08-08  
Hardware de validación: Raspberry Pi 500+

---

## 1. Visión (recordatorio)

EALN-64 no modela intención humana ni objetos.  
Modela **campos de estado densos**, transformaciones irreversibles y trayectorias que colapsan o se estabilizan.

Principios no negociables:
- Estado denso y contiguo (SoA)
- Costo acotado y visible
- Irreversibilidad controlada (`fijo` vs `sea`)
- Zero-pause (arena, sin GC)
- Correspondencia directa con el hardware AArch64
- Zero-libc / pure assembly

---

## 2. Lo que ya funciona (validado en RPi)

| Pieza | Estado | Notas |
|-------|--------|-------|
| Arena + mmap | Hecho | 64 MB, zero-pause |
| I/O zero-copy | Hecho | mmap del fuente |
| Lexer | Hecho | tokens densos SoA |
| Parser (decls) | Hecho | `sea` / `fijo` + número |
| IR densa | Hecho | buffer de instrucciones 8 bytes |
| Emitter solo IR | Hecho | camino AST eliminado |
| Cursor x20 correcto | Hecho | no se restaura al salir de recorrer_ir |
| OP_CONST | Hecho | materializa en registro |
| OP_STORE / OP_LOAD | Hecho | mapeo estático slot N → xN |
| Valor final → x0 | Hecho | exit status predecible |
| ELF mínimo | Hecho | ejecutable nativo |
| Test `sea i = 7;` | **Validado → exit 7** |
| Assign runtime | **Validado → exit 4** | `i = i - 1` |

### Commits clave de esta sesión

- Emitter solo consume IR (eliminado camino AST)
- Fix del cursor x20
- STORE/LOAD con mapeo estático slot→reg
- Assign runtime validado (exit 4)
- **Nuevo:** soporte mínimo de labels + JMP/JZ + CMP en emitter
- **Nuevo:** parse_mientras mínimo (condición = IDENT, un solo assign)

---

## 3. Estado del Paso B (control de flujo)

| Pieza | Estado | Notas |
|-------|--------|-------|
| OP_LABEL / OP_JMP / OP_JZ / OP_CMP | Implementado | backpatch simple |
| parse_mientras | Implementado | versión mínima y segura |
| Test de estabilización | Listo | `sea i = 3; mientras i { i = i - 1; }` → exit 0 esperado |

### Limitaciones deliberadas (para no introducir regresiones)
- Condición de `mientras` solo acepta un IDENT (slot 0)
- Cuerpo del `mientras` solo acepta un assign
- Mapeo de registros sigue siendo estático slot N → xN
- No hay aún `si` / `sino`

---

## 4. Problemas que ya resolvimos (y no hay que repetir)

1. Doble camino AST + IR → eliminado.
2. Restaurar x20 al salir de `recorrer_ir` → cursor vivo.
3. Tablas dinámicas de slots complejas → mapeo estático.
4. Constant folding dentro del assign del while → assign emite IR de runtime.

---

## 5. Siguientes acciones (orden estricto)

### Paso B — Validar `mientras` en hardware (inmediato)
```
sea i = 3;
mientras i {
  i = i - 1;
}
```
Esperado: exit status **0** y que **no se cuelgue**.

### Paso C — Separar constant folding del IR
### Paso D — Asignación de registros más limpia
### Paso E — Ampliar el lenguaje (`si`, expresiones generales, múltiples statements)

---

## 6. Criterio de aceptación físico (RPi 500+)

```bash
make clean && make
./ealn-compiler
./salida.out ; echo $?
```

El exit status es el único canal de verdad por ahora.

---

## 7. Filosofía de avance

- **Una pieza a la vez.**
- Si algo segfaulta o cuelga → rollback inmediato a la última base estable.
- Preferir código simple y predecible.

---

## 8. Resumen en una frase

Tenemos un compilador ARM64 pure-assembly con declaraciones, assign runtime y (recién) control de flujo mínimo mediante `mientras`.  
El siguiente movimiento crítico es **confirmar que el test de estabilización produce exit 0** en hardware real.
