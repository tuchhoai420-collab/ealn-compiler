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
| Test `sea i = 7;` | **Validado → exit 7** | |

### Commits clave de esta sesión

- Emitter solo consume IR (eliminado camino AST)
- Fix del cursor x20 (ya no se pisa el código generado)
- STORE/LOAD con mapeo estático slot→reg
- Backpatch de labels/JMP/JZ (código presente)
- Assign runtime (código presente, pendiente de validar en hardware)

---

## 3. Lo que está implementado pero aún no validado / incompleto

| Pieza | Estado | Riesgo |
|-------|--------|--------|
| Assign runtime (`i = i - 1`) | Código escrito | Último push; falta confirmar exit 4 en RPi |
| Backpatch JMP/JZ/LABEL | Código en emitter | Funcionaba a nivel de estructura; el hang anterior venía del folding del assign |
| `mientras` / `si` en parser | Presente en versiones anteriores | Se simplificó el parser para estabilizar; hay que reintegrar con cuidado |
| Constant folding en expresiones | Parcial / mezclado | Hay que separarlo limpio del IR |

---

## 4. Problemas que ya resolvimos (y no hay que repetir)

1. **Doble camino AST + IR** → eliminado. Solo IR genera código.
2. **Restaurar x20 al salir de `recorrer_ir`** → el epílogo pisaba todo. Cursor vivo.
3. **Tablas dinámicas de slots con stacks complejos** → causaban segfault. Mapeo estático slot N → xN por ahora.
4. **Constant folding dentro del assign del while** → generaba bucle infinito. El assign debe emitir IR de runtime.

---

## 5. Siguientes acciones (orden estricto)

### Paso A — Validar assign runtime (inmediato)
```
sea i = 5;
i = i - 1;
```
Esperado: exit status **4**.  
Si da 4 → base de mutación lista.  
Si segfault o 0/5 → depurar solo esa pieza antes de seguir.

### Paso B — Reintegrar `mientras` con assign runtime
Una vez el assign dé 4:
```
sea i = 3;
mientras i {
  i = i - 1;
}
```
Esperado: exit status **0** y que **no se cuelgue**.

Requisitos:
- Parser vuelve a emitir OP_LABEL / OP_LOAD / OP_CMP / OP_JZ / OP_JMP
- Emitter ya tiene el backpatch
- Assign ya emite LOAD/CONST/SUB/STORE en runtime

### Paso C — Separar constant folding del IR
- Parser solo construye IR + tabla de slots
- Un pase (o el mismo ir_emit con disciplina) hace folding puro
- Emitter nunca ve valores “ya calculados” mezclados con side-effects

### Paso D — Asignación de registros más limpia
- Hoy: slot N → xN (simple, suficiente para ≤8 variables)
- Después: allocador lineal de vregs → físicos, con spilling mínimo si hace falta

### Paso E — Ampliar el lenguaje (solo después de A–D estables)
- Expresiones generales en el lado derecho del assign (`i = i + j * 2`)
- `si` / `sino`
- Más de un statement en el cuerpo del while
- Output a stdout zero-libc (opcional, no prioritario)

---

## 6. Criterio de aceptación físico (RPi 500+)

Cada hito se valida **solo** con:

```bash
make clean && make
./ealn-compiler
./salida.out ; echo $?
```

El exit status es el único canal de verdad por ahora.

---

## 7. Filosofía de avance

- **Una pieza a la vez.**
- Si algo segfaulta o cuelga → rollback inmediato a la última base estable y reintroducir más fino.
- No mezclar “mejoras de IR” con “mejoras de control de flujo” en el mismo commit si se puede evitar.
- Preferir código simple y predecible sobre abstracciones tempranas.

---

## 8. Resumen en una frase

Tenemos un compilador ARM64 pure-assembly que ya genera ELF ejecutables correctos a partir de declaraciones y (en el último push) asignaciones runtime.  
El siguiente movimiento crítico es **confirmar que `i = i - 1` produce exit 4** y, con eso, rearmar el `mientras` sobre una base que ya muta estado en runtime.
