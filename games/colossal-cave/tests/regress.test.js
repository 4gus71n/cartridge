// Upstream Open Adventure regression suite, replayed against OUR wasm build.
// Each vendor/open-adventure/tests/<name>.log is fed line by line through
// CaveSession (exactly how the browser shell drives the engine) and the
// transcript must equal <name>.chk byte for byte. The save/resume tests are
// not vendored: the web build uses ADVENT_AUTOSAVE, which disables SAVE/RESUME.
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

const GAME = path.join(__dirname, "..");
const CaveSession = require(path.join(GAME, "web", "engine.js"));
const createAdvent = require(path.join(GAME, "web", "advent.js"));
const DIR = path.join(GAME, "vendor", "open-adventure", "tests");

async function replay(name) {
  const lines = fs.readFileSync(path.join(DIR, name + ".log"), "utf8").split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  let out = "";
  let exited = false;
  const s = await CaveSession.start({ createAdvent, onOutput: (t) => { out += t; }, onExit: () => { exited = true; } });
  for (const l of lines) {
    await s.idle();
    if (s.exited) break;
    s.send(l);
  }
  await s.idle();
  if (!s.exited) { s.send(null); await s.idle(); }
  return { out, exited: s.exited || exited };
}

const names = fs.readdirSync(DIR).filter((f) => f.endsWith(".log")).map((f) => f.slice(0, -4)).sort();

test("vendored regression logs are present", () => {
  assert.ok(names.length >= 90, "found " + names.length);
});

for (const name of names) {
  test("regress " + name, async () => {
    const { out, exited } = await replay(name);
    assert.equal(exited, true);
    const want = fs.readFileSync(path.join(DIR, name + ".chk"), "utf8");
    assert.equal(out, want);
  });
}

test("death without reincarnation reaches the end-of-game score", async () => {
  const { out } = await replay("death-jump");
  assert.match(out, /reincarnate/);
  assert.match(out, /You scored \d+ out of a possible 430/);
});

test("winning the endgame prints the final rating", async () => {
  const { out } = await replay("win430");
  assert.match(out, /Congratulations!!/);
});
