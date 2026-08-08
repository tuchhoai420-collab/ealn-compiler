AS  = as
LD  = ld

# Filosofía: pure assembly, zero-libc, un solo punto de entrada (_start)
ASM_SOURCES = src/boot/init.s \
              src/core/arena_allocator.s \
              src/core/io_zero_copy.s \
              src/core/ir.s \
              src/frontend/lexer_core.s \
              src/frontend/parser_core.s \
              src/backend/elf_emitter.s

ASM_OBJECTS = $(ASM_SOURCES:.s=.o)
EXECUTABLE  = ealn-compiler

.PHONY: all clean test

all: $(EXECUTABLE)

$(EXECUTABLE): $(ASM_OBJECTS)
	$(LD) $(ASM_OBJECTS) -o $@

%.o: %.s
	$(AS) -g $< -o $@

clean:
	rm -f $(ASM_OBJECTS) $(EXECUTABLE) salida.out

# En RPi / aarch64 nativo:
#   make clean && make
#   ./ealn-compiler
#   ./salida.out ; echo $?
# Esperado: exit status = 100 (último valor cargado en x0, o el primero si solo hay uno)
test: $(EXECUTABLE)
	./$(EXECUTABLE)
	@echo "=== salida.out generado ==="
	@ls -l salida.out
	@echo "Ejecutando binario generado (exit status debería reflejar el valor de la última variable en x0)..."
	-./salida.out ; echo "exit status = $$?"
