/* Minimal stand-in for <editline/readline.h> used by the Cartridge web build.
 * readline() is implemented in engine/web_shim.c: it suspends the wasm
 * (Asyncify) until the JS shell hands over the next line of input. */
#ifndef CARTRIDGE_READLINE_SHIM_H
#define CARTRIDGE_READLINE_SHIM_H
char *readline(const char *prompt);
int add_history(const char *line);
#endif
