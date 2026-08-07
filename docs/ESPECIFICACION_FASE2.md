# EALN-64 — Especificación Fase 2
## Expresiones, control de flujo y generación nativa

Visión: **exógena**. El lenguaje no modela “intención humana” ni metáforas de objetos.  
Modela **campos de estado densos**, transformaciones irreversibles y estabilización de trayectorias.  
El código generado debe ser predecible en costo, layout y latencia.

---

## 0. Principios no negociables (exógenos)

1. **Estado denso y contiguo**  
   Todo valor vivo vive en registros o en slots de un frame lineal. No hay indirecciones ocultas.

2. **Costo acotado y visible**  
   Cada construcción del lenguaje tiene un costo de instrucción predecible.  
   No existen “magias” de runtime.

3. **Irreversibilidad controlada**  
   Las asignaciones a `fijo` son colapsos: una vez escrito el valor, el slot no se reescribe.  
   `sea` permite reescritura, pero el layout permanece fijo.

4. **Ausencia de pausas**  
   Ninguna operación del lenguaje puede introducir recolección, reasignación o trampas de tiempo variable.

5. **Correspondencia directa con el hardware**  
   La semántica del lenguaje se define en términos de registros AArch64, flags y memoria lineal.

---

## 1. Gramática Fase 2

```
prog        := stmt*

stmt        := decl
             | asignacion
             | si_stmt
             | mientras_stmt
             | bloque

decl        := ('sea' | 'fijo') IDENT '=' expr ';'

asignacion  := IDENT '=' expr ';'          // solo si el IDENT fue declarado 'sea'

si_stmt     := 'si' expr '{' stmt* '}'
             | 'si' expr '{' stmt* '}' 'sino' '{' stmt* '}'

mientras_stmt := 'mientras' expr '{' stmt* '}'

bloque      := '{' stmt* '}'

expr        := term
             | expr ('+' | '-') term

term        := factor
             | term ('*' | '/') factor

factor      := NUMBER
             | IDENT
             | '(' expr ')'
             | '-' factor                  // unario
```

### Palabras clave nuevas
- `si`
- `sino`
- `mientras`

### Operadores
- Aritméticos: `+` `-` `*` `/`
- Unario: `-`
- (Comparaciones se introducen en 2.1: `==` `!=` `<` `>` `<=` `>=`)

---

## 2. Modelo de valores y slots

### 2.1 Tipos de valor (Fase 2)
Solo existe un tipo escalar: **entero con signo de 64 bits** (`i64`).

### 2.2 Tabla de símbolos densa (SoA)
En lugar de un mapa hash, se mantiene un arreglo contiguo:

```
struct Slot {
    u32  name_start;     // offset en el fuente
    u32  name_len;
    u32  flags;          // bit0 = fijo (inmutable), bit1 = inicializado
    u32  reg_or_slot;    // registro asignado (0-30) o índice de spill
    i64  const_value;    // si es conocido en compile-time
}
```

Todo el arreglo de slots vive en la arena. Acceso O(1) por índice.  
Búsqueda por nombre es lineal por ahora (N pequeño). Más adelante se puede sustituir por hash perfecto o tabla abierta densa.

### 2.3 Asignación de registros (exógena)
- Los primeros 8 valores vivos se intentan mantener en `x0–x7`.
- Valores adicionales van a un frame lineal en la arena (spill).
- `x8` queda reservado para número de syscall.
- `x28` queda reservado para el puntero de estado global del agente (futuro).
- No se usa el convencionalismo “callee-saved de ABI de C”. El lenguaje define su propio mapa.

---

## 3. Representación intermedia (IR densa)

Antes de emitir opcodes se construye un IR lineal (también SoA):

```
enum Op : u8 {
    OP_CONST,      // dest = imm
    OP_LOAD,       // dest = slot[src]
    OP_STORE,      // slot[dest] = src
    OP_ADD, OP_SUB, OP_MUL, OP_DIV,
    OP_NEG,
    OP_CMP,        // actualiza flags (para saltos)
    OP_JMP,        // salto incondicional
    OP_JZ, OP_JNZ, // saltos condicionales sobre flags
    OP_LABEL,
    OP_EXIT,
}

struct Instr {
    u8   op;
    u8   dest;     // registro o slot
    u8   src1;
    u8   src2;
    i64  imm;      // para CONST o offsets de salto
}
```

El IR es un arreglo contiguo de `Instr`.  
No hay árboles de expresión en el hot path de generación de código: las expresiones se bajan a IR lineal durante el parse (o en un segundo pase corto).

---

## 4. Generación de código nativo (AArch64)

### 4.1 Constantes
```
MOVZ  xN, #imm16
MOVK  xN, #imm16, LSL #16
MOVK  xN, #imm16, LSL #32
MOVK  xN, #imm16, LSL #48
```
Solo se emiten los MOVK necesarios. Valores pequeños → un solo MOVZ.

### 4.2 Aritmética
```
ADD  xD, xN, xM
SUB  xD, xN, xM
MUL  xD, xN, xM
SDIV xD, xN, xM          // división con signo
NEG  xD, xN              // o SUB xD, xzr, xN
```

### 4.3 Control de flujo
```
CMP  xN, xM              // o CMP xN, #imm
B.EQ label
B.NE label
B.LT label
B.GE label
B    label
```

Las etiquetas se resuelven en un segundo pase (backpatch) sobre el buffer de opcodes.  
No se generan trampolines ni saltos indirectos innecesarios.

### 4.4 Layout del binario generado
Sigue siendo un ELF64 mínimo:
- Un solo PT_LOAD RX
- Entry point fijo relativo al inicio del segmento
- Código puro, sin secciones de datos extra por ahora (las constantes van embebidas en el código o en un pool al final del segmento si se necesita)

---

## 5. Optimizaciones nativas (visión exógena)

### 5.1 Constant folding (colapso en compile-time)
Cualquier subárbol de expresión cuyos operandos sean constantes se reduce a una sola constante antes de emitir IR.  
Es un colapso irreversible de información: el valor final es el único que sobrevive.

### 5.2 Dead store elimination sobre `fijo`
Si un slot `fijo` se escribe y nunca se lee, la escritura puede eliminarse.  
Si se escribe y luego se lee solo una vez, el valor puede permanecer en registro sin materializarse en memoria.

### 5.3 Registro preferente y reutilización
- El resultado de una expresión se deja en el registro donde se necesita el siguiente uso cuando es posible (evita MOV innecesarios).
- Los slots de vida corta se asignan a registros de corta duración y se reutilizan agresivamente.

### 5.4 Strength reduction
- `x * 2` → `ADD x, x, x` o `LSL`
- `x * 4` → `LSL #2`
- `x / 2` (cuando es potencia de dos y sin signo) → `LSR` (en Fase 2.1 se distinguirá)

### 5.5 Layout de datos alineado a caché
Todos los arreglos densos (tokens, AST, slots, IR) se alinean a 64 bytes cuando el tamaño lo justifica.  
El objetivo no es “velocidad percibida”, sino **estabilidad de latencia** y maximización de hits de línea de caché.

### 5.6 Ausencia de trampas de tiempo
- No se generan llamadas a funciones de runtime.
- No hay divisiones por cero comprobadas en software (el hardware genera la excepción; el lenguaje no la captura por ahora).
- Los saltos son directos. No hay tablas de despacho para el control de flujo básico.

### 5.7 Futuro: NEON como acumulador de campo
Cuando existan arrays densos, las operaciones elemento a elemento se mapearán a `v0–v15` de forma sistemática.  
La semántica seguirá siendo la de un campo que se transforma en paralelo, no “un bucle que el compilador vectoriza por magia”.

---

## 6. Semántica de `si` y `mientras` (exógena)

- La condición se reduce a un valor escalar.
- Cero = trayectoria “falsa” (no se toma el bloque).
- No-cero = trayectoria “verdadera”.
- No existe el concepto de “verdad” o “falsedad” lingüística; solo existencia o anulación de un valor en el campo de estado.

`mientras` es un ciclo de estabilización: el cuerpo se re-ejecuta mientras la condición no colapse a cero.

---

## 7. Criterios de aceptación de la Fase 2

Un programa de prueba mínimo debe:

1. Declarar variables con expresiones (`sea x = 10 + 3 * 4;`)
2. Usar `si` y `mientras`
3. Generar un ELF que, al ejecutarse, deje un valor determinista en `x0` (verificable por `echo $?`)
4. No realizar ninguna syscall de asignación después del arranque del programa generado
5. Mantener el código generado por debajo de un umbral predecible de instrucciones por construcción del lenguaje

---

## 8. Orden de implementación recomendado

1. Extender el lexer con los nuevos tokens (`+ - * / ( ) si sino mientras`)
2. Bajar expresiones a IR lineal (con constant folding)
3. Tabla de slots densa + resolución de IDENT
4. Emisión de aritmética nativa
5. Saltos y labels (si / mientras)
6. Pruebas de aceptación sobre RPi

---

## 9. Fuera de alcance en Fase 2

- Funciones / llamadas
- Arrays y estructuras
- I/O (print/read)
- Punteros
- Tipos distintos de i64
- Excepciones manejadas por el lenguaje
- Self-hosting

Estos elementos se introducirán cuando el núcleo de expresiones + control de flujo esté estable y el costo de cada construcción esté medido.
