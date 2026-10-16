/*
 * Cartridge web shim for Open Adventure.
 *
 * - readline(): flushes stdout, then suspends the wasm via Asyncify until the
 *   JS host resolves Module.readLine(prompt) with the next input line
 *   (or null for EOF).
 * - web_turn_boundary(): called (via engine/web.patch) right before the game
 *   reads each main command. Writes the autosave file (ADVENT_AUTOSAVE) and
 *   tells the host so it can persist it (localStorage in the browser).
 */
#include <emscripten.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "advent.h"

EM_ASYNC_JS(char *, js_read_line, (const char *prompt), {
	const line = await Module.readLine(UTF8ToString(prompt));
	if (line === null || line === undefined) {
		return 0;
	}
	return stringToNewUTF8(String(line));
});

char *readline(const char *prompt) {
	fflush(stdout);
	return js_read_line(prompt ? prompt : "");
}

int add_history(const char *line) {
	(void)line;
	return 0;
}

void web_turn_boundary(void) {
	fflush(stdout);
	autosave();
	EM_ASM({
		if (Module.onTurn) {
			Module.onTurn();
		}
	});
}
